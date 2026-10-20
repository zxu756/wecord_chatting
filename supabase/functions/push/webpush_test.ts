import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  base64UrlDecode,
  base64UrlEncode,
  deriveContentKeys,
  encryptPayload,
  readVapidKeys,
  sendWebPush,
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

/// Sends [payload] through sendWebPush to a browser we hold the keys of, and
/// returns what the browser decrypts.
async function sentAndDecrypted(payload: unknown): Promise<unknown> {
  const browser = await receiver();
  const vapid = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  ) as CryptoKeyPair;
  const jwk = await crypto.subtle.exportKey("jwk", vapid.privateKey);
  const keys = {
    publicKey: base64UrlEncode(
      new Uint8Array(await crypto.subtle.exportKey("raw", vapid.publicKey)),
    ),
    privateKey: jwk.d!,
    subject: "mailto:ops@example.com",
  };

  const realFetch = globalThis.fetch;
  let sent: Uint8Array | null = null;
  globalThis.fetch = (_input, init) => {
    sent = new Uint8Array(init!.body as Uint8Array);
    return Promise.resolve(new Response(null, { status: 201 }));
  };
  try {
    const status = await sendWebPush(keys, {
      endpoint: "https://push.example.com/x",
      p256dh: base64UrlEncode(browser.publicKey),
      auth: base64UrlEncode(browser.auth),
    }, payload, {
      nowSeconds: 1_700_000_000,
      siteOrigin: "https://wecord.example",
    });
    assertEquals(status, 201);
  } finally {
    globalThis.fetch = realFetch;
  }

  const message = sent!;
  const salt = message.slice(0, 16);
  const keyLength = message[20];
  const senderPublic = message.slice(21, 21 + keyLength);
  const ciphertext = message.slice(21 + keyLength);
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
  return JSON.parse(new TextDecoder().decode(plain.slice(0, -1)));
}

Deno.test("a notification goes out classic and declarative in one message", async () => {
  const received = await sentAndDecrypted({
    title: "Ada",
    body: "hello",
    tag: "c1",
    url: "/#/chats/c1",
  }) as Record<string, unknown>;
  // Older browsers' service worker reads these.
  assertEquals(received.title, "Ada");
  assertEquals(received.url, "/#/chats/c1");
  // Safari 18.4+ reads these.
  assertEquals(received.web_push, 8030);
  assertEquals(
    (received.notification as Record<string, unknown>).navigate,
    "https://wecord.example/#/chats/c1",
  );
});

Deno.test("a payload that is not a notification is sent as it is", async () => {
  assertEquals(await sentAndDecrypted({ ping: true }), { ping: true });
});
