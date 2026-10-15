// Pure helpers for minting LiveKit access tokens: HS256 JWTs signed with
// the project's API secret, with a video grant for one room. No network.

export interface LiveKitConfig {
  url: string;
  apiKey: string;
  apiSecret: string;
}

/// The LiveKit settings from the environment, or null when any is missing
/// (voice is not set up for this project yet).
export function readLiveKitConfig(
  get: (name: string) => string | undefined,
): LiveKitConfig | null {
  const url = get("LIVEKIT_URL")?.trim();
  const apiKey = get("LIVEKIT_API_KEY")?.trim();
  const apiSecret = get("LIVEKIT_API_SECRET")?.trim();
  if (!url || !apiKey || !apiSecret) {
    return null;
  }
  return { url, apiKey, apiSecret };
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function parseUuidField(body: unknown, field: string): string | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }
  const value = (body as Record<string, unknown>)[field];
  if (typeof value !== "string" || !uuidPattern.test(value.trim())) {
    return null;
  }
  return value.trim().toLowerCase();
}

/// The voice channel id from a request body, lowercased, or null.
export function parseChannelId(body: unknown): string | null {
  return parseUuidField(body, "channel_id");
}

/// The direct or group call id from a request body, lowercased, or null.
export function parseCallId(body: unknown): string | null {
  return parseUuidField(body, "call_id");
}

/// The LiveKit room of a direct or group call.
export function callRoomName(callId: string): string {
  return `call-${callId}`;
}

export interface VideoGrant {
  room: string;
  roomJoin?: boolean;
  roomAdmin?: boolean;
  canPublish?: boolean;
  canSubscribe?: boolean;
  canPublishData?: boolean;
  /// What may be published; every source when absent.
  canPublishSources?: string[];
}

/// What a server-muted or server-deafened member may still publish: their
/// camera and screen, not their microphone. Null when unrestricted.
export function publishSourcesFor(flags: {
  serverMute: boolean;
  serverDeaf: boolean;
}): string[] | null {
  if (!flags.serverMute && !flags.serverDeaf) {
    return null;
  }
  return ["camera", "screen_share", "screen_share_audio"];
}

export interface LiveKitClaims {
  iss: string;
  sub: string;
  name: string;
  nbf: number;
  exp: number;
  video: VideoGrant;
}

/// How long a token may be used to join; LiveKit keeps a joined
/// participant connected past it.
export const TOKEN_TTL_SECONDS = 60 * 60;

/// Whether someone may publish at all: everyone in voice channels and
/// calls, only the speakers on a stage (the audience just listens).
export function canPublishIn(access: {
  kind?: string | null;
  stageSpeaker?: boolean | null;
}): boolean {
  return access.kind !== "stage" || access.stageSpeaker === true;
}

/// Claims letting [identity] (the user id) join [room] (the channel id) as
/// [name], valid from [nowSeconds] for an hour.
/// [publishSources] limits what they may publish (see [publishSourcesFor]);
/// [canPublish] false makes them a listener (a stage's audience).
export function buildClaims(options: {
  apiKey: string;
  identity: string;
  name: string;
  room: string;
  nowSeconds: number;
  publishSources?: string[] | null;
  canPublish?: boolean;
}): LiveKitClaims {
  const canPublish = options.canPublish ?? true;
  const video: VideoGrant = {
    room: options.room,
    roomJoin: true,
    canPublish,
    canSubscribe: true,
    canPublishData: canPublish,
  };
  if (canPublish && options.publishSources) {
    video.canPublishSources = options.publishSources;
  }
  return {
    iss: options.apiKey,
    sub: options.identity,
    name: options.name,
    nbf: options.nowSeconds,
    exp: options.nowSeconds + TOKEN_TTL_SECONDS,
    video,
  };
}

/// How long a server-side admin token lives: one request.
export const ADMIN_TOKEN_TTL_SECONDS = 60;

/// Claims for this function itself to manage [room] through LiveKit's
/// RoomService API.
export function buildAdminClaims(options: {
  apiKey: string;
  room: string;
  nowSeconds: number;
}): LiveKitClaims {
  return {
    iss: options.apiKey,
    sub: "wecord-moderation",
    name: "WeCord moderation",
    nbf: options.nowSeconds,
    exp: options.nowSeconds + ADMIN_TOKEN_TTL_SECONDS,
    video: { room: options.room, roomAdmin: true },
  };
}

/// LiveKit's HTTP API base for its websocket [url] (wss becomes https).
export function liveKitHttpUrl(url: string): string {
  return url
    .trim()
    .replace(/^wss:/i, "https:")
    .replace(/^ws:/i, "http:")
    .replace(/\/+$/, "");
}

/// A moderator's request to make a voice channel's room match the
/// database for one member: {enforce: {channel_id, user_id}}.
export function parseEnforceRequest(
  body: unknown,
): { channelId: string; userId: string } | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }
  const enforce = (body as Record<string, unknown>).enforce;
  const channelId = parseChannelId(enforce);
  const userId = parseUuidField(enforce, "user_id");
  if (!channelId || !userId) {
    return null;
  }
  return { channelId, userId };
}

export interface EnforcementState {
  channel_id: string;
  user_id: string;
  in_channel: boolean;
  server_mute: boolean;
  server_deaf: boolean;
  /// A stage channel, where only [stage_speaker]s publish.
  stage?: boolean;
  stage_speaker?: boolean;
}

/// The RoomService call that makes the room match [state]: remove a
/// member who is no longer in the channel, otherwise set what they may
/// publish (nothing for a stage's audience). The body is Twirp JSON.
export function enforcementRequest(state: EnforcementState): {
  method: "RemoveParticipant" | "UpdateParticipant";
  body: Record<string, unknown>;
} {
  if (!state.in_channel) {
    return {
      method: "RemoveParticipant",
      body: { room: state.channel_id, identity: state.user_id },
    };
  }
  const sources = publishSourcesFor({
    serverMute: state.server_mute,
    serverDeaf: state.server_deaf,
  });
  const canPublish = canPublishIn({
    kind: state.stage ? "stage" : "voice",
    stageSpeaker: state.stage_speaker,
  });
  return {
    method: "UpdateParticipant",
    body: {
      room: state.channel_id,
      identity: state.user_id,
      permission: {
        can_subscribe: true,
        can_publish: canPublish,
        can_publish_data: canPublish,
        // Empty allows every source.
        can_publish_sources: (sources ?? []).map((source) =>
          source.toUpperCase()
        ),
      },
    },
  };
}

export function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/,
    "",
  );
}

export function base64UrlDecode(value: string): Uint8Array<ArrayBuffer> {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/") +
    "=".repeat((4 - (value.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

const encoder = new TextEncoder();

function hmacKey(secret: string, usage: "sign" | "verify") {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    [usage],
  );
}

/// An HS256 JWT of [claims] signed with [secret].
export async function signJwt(
  claims: LiveKitClaims,
  secret: string,
): Promise<string> {
  const header = base64UrlEncode(
    encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })),
  );
  const payload = base64UrlEncode(encoder.encode(JSON.stringify(claims)));
  const signingInput = `${header}.${payload}`;
  const signature = await crypto.subtle.sign(
    "HMAC",
    await hmacKey(secret, "sign"),
    encoder.encode(signingInput),
  );
  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

/// The payload of [token] when its HS256 signature matches [secret],
/// otherwise null. Used by the tests to check what was signed.
export async function verifyJwt(
  token: string,
  secret: string,
): Promise<Record<string, unknown> | null> {
  const parts = token.split(".");
  if (parts.length !== 3) {
    return null;
  }
  const [header, payload, signature] = parts;
  let headerJson: unknown;
  try {
    headerJson = JSON.parse(new TextDecoder().decode(base64UrlDecode(header)));
  } catch {
    return null;
  }
  if ((headerJson as Record<string, unknown>)?.alg !== "HS256") {
    return null;
  }
  const valid = await crypto.subtle.verify(
    "HMAC",
    await hmacKey(secret, "verify"),
    base64UrlDecode(signature),
    encoder.encode(`${header}.${payload}`),
  );
  if (!valid) {
    return null;
  }
  return JSON.parse(new TextDecoder().decode(base64UrlDecode(payload)));
}
