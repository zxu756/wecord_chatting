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

/// The voice channel id from a request body, lowercased, or null.
export function parseChannelId(body: unknown): string | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }
  const value = (body as Record<string, unknown>).channel_id;
  if (typeof value !== "string" || !uuidPattern.test(value.trim())) {
    return null;
  }
  return value.trim().toLowerCase();
}

export interface VideoGrant {
  room: string;
  roomJoin: boolean;
  canPublish: boolean;
  canSubscribe: boolean;
  canPublishData: boolean;
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

/// Claims letting [identity] (the user id) join [room] (the channel id) as
/// [name], valid from [nowSeconds] for an hour.
export function buildClaims(options: {
  apiKey: string;
  identity: string;
  name: string;
  room: string;
  nowSeconds: number;
}): LiveKitClaims {
  return {
    iss: options.apiKey,
    sub: options.identity,
    name: options.name,
    nbf: options.nowSeconds,
    exp: options.nowSeconds + TOKEN_TTL_SECONDS,
    video: {
      room: options.room,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
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
