// Web Push without dependencies: VAPID (RFC 8292) authorization and
// aes128gcm payload encryption (RFC 8291), on WebCrypto.

export interface VapidKeys {
  /// The uncompressed P-256 public key (65 bytes), base64url.
  publicKey: string;
  /// The private scalar d (32 bytes), base64url.
  privateKey: string;
  /// A contact for push services, "mailto:…" or "https://…".
  subject: string;
}

export interface PushSubscriptionKeys {
  endpoint: string;
  /// The browser's P-256 public key, base64url.
  p256dh: string;
  /// The 16-byte authentication secret, base64url.
  auth: string;
}

const encoder = new TextEncoder();

export function base64UrlEncode(bytes: Uint8Array<ArrayBuffer>): string {
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
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function concat(...parts: Uint8Array<ArrayBuffer>[]): Uint8Array<ArrayBuffer> {
  const length = parts.reduce((sum, part) => sum + part.length, 0);
  const result = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

/// The VAPID keys from the environment, or null when any is missing.
export function readVapidKeys(
  get: (name: string) => string | undefined,
): VapidKeys | null {
  const publicKey = get("VAPID_PUBLIC_KEY")?.trim();
  const privateKey = get("VAPID_PRIVATE_KEY")?.trim();
  const subject = get("VAPID_SUBJECT")?.trim() ||
    "mailto:push@wecord.invalid";
  if (!publicKey || !privateKey) {
    return null;
  }
  return { publicKey, privateKey, subject };
}

function vapidSigningKey(keys: VapidKeys): Promise<CryptoKey> {
  const publicBytes = base64UrlDecode(keys.publicKey);
  if (publicBytes.length !== 65 || publicBytes[0] !== 4) {
    throw new Error("VAPID public key must be an uncompressed P-256 point");
  }
  return crypto.subtle.importKey(
    "jwk",
    {
      kty: "EC",
      crv: "P-256",
      d: keys.privateKey,
      x: base64UrlEncode(publicBytes.slice(1, 33)),
      y: base64UrlEncode(publicBytes.slice(33, 65)),
      ext: true,
    },
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

/// The Authorization header value for a push to [endpoint].
export async function vapidAuthorization(
  keys: VapidKeys,
  endpoint: string,
  nowSeconds: number,
): Promise<string> {
  const header = base64UrlEncode(
    encoder.encode(JSON.stringify({ typ: "JWT", alg: "ES256" })),
  );
  const claims = base64UrlEncode(encoder.encode(JSON.stringify({
    aud: new URL(endpoint).origin,
    exp: nowSeconds + 12 * 60 * 60,
    sub: keys.subject,
  })));
  const signingInput = `${header}.${claims}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      await vapidSigningKey(keys),
      encoder.encode(signingInput),
    ),
  );
  return `vapid t=${signingInput}.${
    base64UrlEncode(signature)
  }, k=${keys.publicKey}`;
}

async function hkdf(
  salt: Uint8Array<ArrayBuffer>,
  ikm: Uint8Array<ArrayBuffer>,
  info: Uint8Array<ArrayBuffer>,
  length: number,
): Promise<Uint8Array<ArrayBuffer>> {
  const key = await crypto.subtle.importKey("raw", ikm, "HKDF", false, [
    "deriveBits",
  ]);
  return new Uint8Array(
    await crypto.subtle.deriveBits(
      { name: "HKDF", hash: "SHA-256", salt, info },
      key,
      length * 8,
    ),
  );
}

/// The content encryption key and nonce for one message (RFC 8291 §3.4).
export async function deriveContentKeys(options: {
  sharedSecret: Uint8Array<ArrayBuffer>;
  authSecret: Uint8Array<ArrayBuffer>;
  receiverPublic: Uint8Array<ArrayBuffer>;
  senderPublic: Uint8Array<ArrayBuffer>;
  salt: Uint8Array<ArrayBuffer>;
}): Promise<{ key: Uint8Array<ArrayBuffer>; nonce: Uint8Array<ArrayBuffer> }> {
  const keyInfo = concat(
    encoder.encode("WebPush: info\0"),
    options.receiverPublic,
    options.senderPublic,
  );
  const ikm = await hkdf(
    options.authSecret,
    options.sharedSecret,
    keyInfo,
    32,
  );
  return {
    key: await hkdf(
      options.salt,
      ikm,
      encoder.encode("Content-Encoding: aes128gcm\0"),
      16,
    ),
    nonce: await hkdf(
      options.salt,
      ikm,
      encoder.encode("Content-Encoding: nonce\0"),
      12,
    ),
  };
}

/// [payload] encrypted for the subscription as one aes128gcm record.
export async function encryptPayload(
  subscription: PushSubscriptionKeys,
  payload: Uint8Array<ArrayBuffer>,
): Promise<Uint8Array<ArrayBuffer>> {
  const receiverPublic = base64UrlDecode(subscription.p256dh);
  const authSecret = base64UrlDecode(subscription.auth);
  const sender = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" },
    true,
    ["deriveBits"],
  ) as CryptoKeyPair;
  const senderPublic = new Uint8Array(
    await crypto.subtle.exportKey("raw", sender.publicKey),
  );
  const receiverKey = await crypto.subtle.importKey(
    "raw",
    receiverPublic,
    { name: "ECDH", namedCurve: "P-256" },
    false,
    [],
  );
  const sharedSecret = new Uint8Array(
    await crypto.subtle.deriveBits(
      { name: "ECDH", public: receiverKey },
      sender.privateKey,
      256,
    ),
  );
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const { key, nonce } = await deriveContentKeys({
    sharedSecret,
    authSecret,
    receiverPublic,
    senderPublic,
    salt,
  });
  const aesKey = await crypto.subtle.importKey("raw", key, "AES-GCM", false, [
    "encrypt",
  ]);
  // A single, last record: the payload then the 0x02 delimiter.
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv: nonce },
      aesKey,
      concat(payload, new Uint8Array([2])),
    ),
  );
  const recordSize = new Uint8Array(4);
  new DataView(recordSize.buffer).setUint32(0, 4096);
  return concat(
    salt,
    recordSize,
    new Uint8Array([senderPublic.length]),
    senderPublic,
    ciphertext,
  );
}

/// Sends [payload] to one subscription. Returns the push service's status.
export async function sendWebPush(
  keys: VapidKeys,
  subscription: PushSubscriptionKeys,
  payload: unknown,
  options: { nowSeconds: number; ttlSeconds?: number } = {
    nowSeconds: Math.floor(Date.now() / 1000),
  },
): Promise<number> {
  const body = await encryptPayload(
    subscription,
    encoder.encode(JSON.stringify(payload)),
  );
  const response = await fetch(subscription.endpoint, {
    method: "POST",
    headers: {
      Authorization: await vapidAuthorization(
        keys,
        subscription.endpoint,
        options.nowSeconds,
      ),
      "Content-Encoding": "aes128gcm",
      "Content-Type": "application/octet-stream",
      TTL: String(options.ttlSeconds ?? 24 * 60 * 60),
      Urgency: "high",
    },
    body,
  });
  await response.body?.cancel();
  return response.status;
}
