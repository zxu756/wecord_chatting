import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  ADMIN_TOKEN_TTL_SECONDS,
  base64UrlDecode,
  base64UrlEncode,
  buildAdminClaims,
  buildClaims,
  callRoomName,
  canPublishIn,
  CAPTIONS_HOST_ATTRIBUTE,
  enforcementRequest,
  liveKitHttpUrl,
  parseCallId,
  parseChannelId,
  parseEnforceRequest,
  publishSourcesFor,
  readLiveKitConfig,
  signJwt,
  TOKEN_TTL_SECONDS,
  verifyJwt,
} from "./token.ts";

const channelId = "5bc6e021-f4f7-47d5-9a7b-9cb7529015e0";
const userId = "00000000-0000-0000-0000-00000000000a";

Deno.test("config needs the url, key and secret", () => {
  const env: Record<string, string> = {
    LIVEKIT_URL: "wss://example.livekit.cloud",
    LIVEKIT_API_KEY: "APIkey",
    LIVEKIT_API_SECRET: "secret",
  };
  assertEquals(readLiveKitConfig((name) => env[name]), {
    url: "wss://example.livekit.cloud",
    apiKey: "APIkey",
    apiSecret: "secret",
  });
  for (const missing of Object.keys(env)) {
    const partial = { ...env, [missing]: " " };
    assertEquals(readLiveKitConfig((name) => partial[name]), null, missing);
  }
  assertEquals(readLiveKitConfig(() => undefined), null);
});

Deno.test("parses the channel id", () => {
  assertEquals(parseChannelId({ channel_id: channelId }), channelId);
  assertEquals(
    parseChannelId({ channel_id: ` ${channelId.toUpperCase()} ` }),
    channelId,
  );
  for (
    const body of [
      null,
      "x",
      {},
      { channel_id: 42 },
      { channel_id: "not-a-uuid" },
      { channel_id: `${channelId}x` },
    ]
  ) {
    assertEquals(parseChannelId(body), null, JSON.stringify(body));
  }
});

Deno.test("claims grant joining one room for an hour", () => {
  const claims = buildClaims({
    apiKey: "APIkey",
    identity: userId,
    name: "Ada",
    room: channelId,
    nowSeconds: 1_000,
  });
  assertEquals(claims, {
    iss: "APIkey",
    sub: userId,
    name: "Ada",
    nbf: 1_000,
    exp: 1_000 + TOKEN_TTL_SECONDS,
    video: {
      room: channelId,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    },
  });
});

Deno.test("base64url round-trips without padding", () => {
  for (const length of [0, 1, 2, 3, 4, 31, 32, 33]) {
    const bytes = new Uint8Array(length).map((_, index) => (index * 97) % 256);
    const encoded = base64UrlEncode(bytes);
    assert(!/[+/=]/.test(encoded), encoded);
    assertEquals(base64UrlDecode(encoded), bytes);
  }
});

Deno.test("signed tokens verify with the secret and carry the claims", async () => {
  const claims = buildClaims({
    apiKey: "APIkey",
    identity: userId,
    name: "Ada Lovelace ✨",
    room: channelId,
    nowSeconds: 1_700_000_000,
  });
  const token = await signJwt(claims, "secret");
  const [header] = token.split(".");
  assertEquals(
    JSON.parse(new TextDecoder().decode(base64UrlDecode(header))),
    { alg: "HS256", typ: "JWT" },
  );
  assertEquals(await verifyJwt(token, "secret"), { ...claims });
  assertEquals(await verifyJwt(token, "other secret"), null);

  // A changed payload no longer verifies.
  const [h, , s] = token.split(".");
  const forged = base64UrlEncode(
    new TextEncoder().encode(JSON.stringify({ ...claims, sub: "someone" })),
  );
  assertEquals(await verifyJwt(`${h}.${forged}.${s}`, "secret"), null);
  assertEquals(await verifyJwt("a.b", "secret"), null);
});

Deno.test("matches a token signed independently", async () => {
  // Signed with Python's hmac / hashlib for the same claims.
  const expected = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
    "eyJpc3MiOiJrIiwic3ViIjoidSIsIm5hbWUiOiJuIiwibmJmIjowLCJleHAiOjM2MDAs" +
    "InZpZGVvIjp7InJvb20iOiJyIiwicm9vbUpvaW4iOnRydWUsImNhblB1Ymxpc2giOnRy" +
    "dWUsImNhblN1YnNjcmliZSI6dHJ1ZSwiY2FuUHVibGlzaERhdGEiOnRydWV9fQ." +
    "HUg1BAhzCiVLk2OWwHyS7RVO7XcjsfSfETHqEGJTQ00";
  const claims = buildClaims({
    apiKey: "k",
    identity: "u",
    name: "n",
    room: "r",
    nowSeconds: 0,
  });
  assertEquals(await signJwt(claims, "secret"), expected);
});

Deno.test("server-muted members can't publish their microphone", () => {
  assertEquals(
    publishSourcesFor({ serverMute: false, serverDeaf: false }),
    null,
  );
  const sources = ["camera", "screen_share", "screen_share_audio"];
  assertEquals(
    publishSourcesFor({ serverMute: true, serverDeaf: false }),
    sources,
  );
  assertEquals(
    publishSourcesFor({ serverMute: false, serverDeaf: true }),
    sources,
  );
  const claims = buildClaims({
    apiKey: "k",
    identity: userId,
    name: "n",
    room: channelId,
    nowSeconds: 0,
    publishSources: sources,
  });
  assertEquals(claims.video.canPublishSources, sources);
  assertEquals(claims.video.canPublish, true);
});

Deno.test("admin claims manage one room briefly", () => {
  const claims = buildAdminClaims({
    apiKey: "k",
    room: channelId,
    nowSeconds: 10,
  });
  assertEquals(claims.video, { room: channelId, roomAdmin: true });
  assertEquals(claims.exp, 10 + ADMIN_TOKEN_TTL_SECONDS);
});

Deno.test("the HTTP API sits beside the websocket url", () => {
  assertEquals(
    liveKitHttpUrl("wss://x.livekit.cloud/"),
    "https://x.livekit.cloud",
  );
  assertEquals(
    liveKitHttpUrl(" ws://localhost:7880 "),
    "http://localhost:7880",
  );
});

Deno.test("enforce requests parse and pick the RoomService call", () => {
  assertEquals(
    parseEnforceRequest({
      enforce: { channel_id: channelId, user_id: userId },
    }),
    { channelId, userId },
  );
  assertEquals(
    parseEnforceRequest({ enforce: { channel_id: channelId } }),
    null,
  );
  assertEquals(
    parseEnforceRequest({ channel_id: channelId, user_id: userId }),
    null,
  );

  const state = {
    channel_id: channelId,
    user_id: userId,
    in_channel: false,
    server_mute: false,
    server_deaf: false,
  };
  assertEquals(enforcementRequest(state), {
    method: "RemoveParticipant",
    body: { room: channelId, identity: userId },
  });
  const muted = enforcementRequest({
    ...state,
    in_channel: true,
    server_mute: true,
  });
  assertEquals(muted.method, "UpdateParticipant");
  assertEquals(
    (muted.body.permission as Record<string, unknown>).can_publish_sources,
    ["CAMERA", "SCREEN_SHARE", "SCREEN_SHARE_AUDIO"],
  );
  const free = enforcementRequest({ ...state, in_channel: true });
  assertEquals(
    (free.body.permission as Record<string, unknown>).can_publish_sources,
    [],
  );
});

Deno.test("call ids parse on their own and name their room", () => {
  assertEquals(parseCallId({ call_id: channelId }), channelId);
  assertEquals(parseCallId({ channel_id: channelId }), null);
  assertEquals(parseChannelId({ call_id: channelId }), null);
  assertEquals(parseCallId({ call_id: "nope" }), null);
  assertEquals(callRoomName(channelId), `call-${channelId}`);
});

Deno.test("a stage's audience only listens; its speakers publish", () => {
  assertEquals(canPublishIn({}), true);
  assertEquals(canPublishIn({ kind: "voice" }), true);
  assertEquals(canPublishIn({ kind: "stage" }), false);
  assertEquals(canPublishIn({ kind: "stage", stageSpeaker: false }), false);
  assertEquals(canPublishIn({ kind: "stage", stageSpeaker: true }), true);

  const audience = buildClaims({
    apiKey: "k",
    identity: userId,
    name: "n",
    room: channelId,
    nowSeconds: 0,
    publishSources: ["camera"],
    canPublish: false,
  });
  assertEquals(audience.video, {
    room: channelId,
    roomJoin: true,
    canPublish: false,
    canSubscribe: true,
    canPublishData: false,
  });

  const state = {
    channel_id: channelId,
    user_id: userId,
    in_channel: true,
    server_mute: false,
    server_deaf: false,
    stage: true,
    stage_speaker: false,
  };
  const listener = enforcementRequest(state).body.permission as Record<
    string,
    unknown
  >;
  assertEquals(listener.can_publish, false);
  assertEquals(listener.can_publish_data, false);
  assertEquals(listener.can_subscribe, true);
  const speaker = enforcementRequest({ ...state, stage_speaker: true }).body
    .permission as Record<string, unknown>;
  assertEquals(speaker.can_publish, true);
  assertEquals(speaker.can_publish_sources, []);
  const mutedSpeaker = enforcementRequest({
    ...state,
    stage_speaker: true,
    server_mute: true,
  }).body.permission as Record<string, unknown>;
  assertEquals(mutedSpeaker.can_publish, true);
  assertEquals(mutedSpeaker.can_publish_sources, [
    "CAMERA",
    "SCREEN_SHARE",
    "SCREEN_SHARE_AUDIO",
  ]);
});

Deno.test("a token carries the captions attribute only for someone who may host", async () => {
  const base = {
    apiKey: "APIkey",
    identity: userId,
    name: "Ada",
    room: channelId,
    nowSeconds: 1_700_000_000,
  };
  assertEquals(CAPTIONS_HOST_ATTRIBUTE, "cap");
  assertEquals(buildClaims(base).attributes, undefined);
  assertEquals(
    buildClaims({ ...base, captionsHost: false }).attributes,
    undefined,
  );
  const host = buildClaims({ ...base, captionsHost: true });
  assertEquals(host.attributes, { cap: "1" });
  // The attribute is inside the signed part: it cannot be added afterwards.
  const jwt = await signJwt(host, "secret");
  const payload = await verifyJwt(jwt, "secret");
  assertEquals(payload?.attributes, { cap: "1" });
  const [header, , signature] = (await signJwt(buildClaims(base), "secret"))
    .split(".");
  const forged = base64UrlEncode(
    new TextEncoder().encode(
      JSON.stringify({ ...buildClaims(base), attributes: { cap: "1" } }),
    ),
  );
  assertEquals(
    await verifyJwt(`${header}.${forged}.${signature}`, "secret"),
    null,
  );
});
