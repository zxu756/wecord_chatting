// Signing what is sent to a bot, so the bot can tell it came from WeCord and
// is fresh.
//
//   X-WeCord-Timestamp: <seconds since 1970>
//   X-WeCord-Signature: v1=<hex HMAC-SHA256 of "<timestamp>.<body>" with the
//                          bot's callback secret as the key>
//   X-WeCord-Delivery:  <interaction id>
//
// A bot checks the signature with a constant-time compare, rejects a
// timestamp more than five minutes from its own clock (replay) and remembers
// the delivery ids it has seen for that long (docs/bot-api.md).

const encoder = new TextEncoder();

function toHex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/// `v1=<hex>` for [body] sent at [timestamp] seconds.
export async function signBody(
  secret: string,
  timestamp: number,
  body: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(`${timestamp}.${body}`),
  );
  return `v1=${toHex(signature)}`;
}

/// The headers of a callback request.
export async function callbackHeaders(
  secret: string,
  timestamp: number,
  body: string,
  interactionId: string,
): Promise<Record<string, string>> {
  return {
    "Content-Type": "application/json",
    "User-Agent": "WeCord-Bot-Callbacks/1",
    "X-WeCord-Timestamp": String(timestamp),
    "X-WeCord-Signature": await signBody(secret, timestamp, body),
    "X-WeCord-Delivery": interactionId,
  };
}
