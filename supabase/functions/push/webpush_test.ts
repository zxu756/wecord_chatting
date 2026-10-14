import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  base64UrlDecode,
  base64UrlEncode,
  deriveContentKeys,
  encryptPayload,
  readVapidKeys,
  vapidAuthorization,
} from "./webpush.ts";

async function receiver() {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" },
    true,
    ["deriveBits"],
  ) as CryptoKeyPair;
  const publicKey = new Uint8Array(
    await crypto.subtle.exportKey("raw", pair.publicKey),
  );
  const auth = crypto.getRandomValues(new Uint8Array(16));
  return { pair, publicKey, auth };
}

Deno.test("a browser can decrypt what we encrypt", async () => {
  const browser = await receiver();
  const payload = new TextEncoder().encode(
    JSON.stringify({ title: "Alice", body: "hello 你好" }),
  );

  const message = await encryptPayload({
    endpoint: "https://push.example.com/x",
    p256dh: base64UrlEncode(browser.publicKey),
    auth: base64UrlEncode(browser.auth),
  }, payload);

  const salt = message.slice(0, 16);
  const recordSize = new DataView(message.buffer).getUint32(16);
  const keyLength = message[20];
  const senderPublic = message.slice(21, 21 + keyLength);
  const ciphertext = message.slice(21 + keyLength);
  assertEquals(recordSize, 4096);
  assertEquals(keyLength, 65);

  const senderKey = await crypto.subtle.importKey(
    "raw",
    senderPublic,
    { name: "ECDH", namedCurve: "P-256" },
    false,
    [],
  );
  const sharedSecret = new Uint8Array(
    await crypto.subtle.deriveBits(
      { name: "ECDH", public: senderKey },
      browser.pair.privateKey,
      256,
    ),
  );
  const { key, nonce } = await deriveContentKeys({
    sharedSecret,
    authSecret: browser.auth,
    receiverPublic: browser.publicKey,
    senderPublic,
    salt,
  });
  const aesKey = await crypto.subtle.importKey("raw", key, "AES-GCM", false, [
    "decrypt",
  ]);
  const plain = new Uint8Array(
    await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: nonce },
      aesKey,
      ciphertext,
    ),
  );
  assertEquals(plain[plain.length - 1], 2);
  assertEquals(plain.slice(0, -1), payload);
});

Deno.test("the VAPID token is signed by our key for the push origin", async () => {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  ) as CryptoKeyPair;
  const jwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
  const publicKey = base64UrlEncode(
    new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)),
  );
  const keys = readVapidKeys((name) =>
    ({
      VAPID_PUBLIC_KEY: publicKey,
      VAPID_PRIVATE_KEY: jwk.d,
      VAPID_SUBJECT: "mailto:ops@example.com",
    })[name]
  )!;

  const header = await vapidAuthorization(
    keys,
    "https://fcm.googleapis.com/fcm/send/abc",
    1_700_000_000,
  );

  const match = /^vapid t=([^,]+), k=(.+)$/.exec(header)!;
  assertEquals(match[2], publicKey);
  const [head, claims, signature] = match[1].split(".");
  const decoded = JSON.parse(new TextDecoder().decode(base64UrlDecode(claims)));
  assertEquals(decoded.aud, "https://fcm.googleapis.com");
  assertEquals(decoded.sub, "mailto:ops@example.com");
  assertEquals(decoded.exp, 1_700_000_000 + 12 * 60 * 60);
  assert(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      pair.publicKey,
      base64UrlDecode(signature),
      new TextEncoder().encode(`${head}.${claims}`),
    ),
  );
});

Deno.test("keys are required, the subject has a default", () => {
  assertEquals(readVapidKeys(() => undefined), null);
  assertEquals(
    readVapidKeys((name) => name === "VAPID_PUBLIC_KEY" ? "p" : undefined),
    null,
  );
  assertEquals(
    readVapidKeys((name) =>
      ({ VAPID_PUBLIC_KEY: "p", VAPID_PRIVATE_KEY: "d" })[name]
    )?.subject,
    "mailto:push@wecord.invalid",
  );
});
