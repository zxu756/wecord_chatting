import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  base64UrlDecode,
  base64UrlEncode,
  buildClaims,
  parseChannelId,
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
