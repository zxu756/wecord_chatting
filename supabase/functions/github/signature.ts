// Checking that a request really came from GitHub (and from the repository
// whose owner we gave the secret to): GitHub signs the raw body with the
// secret as HMAC-SHA256 and sends it as `X-Hub-Signature-256: sha256=<hex>`.
// The compare takes the same time wherever the two differ.

const encoder = new TextEncoder();
const HEADER_PATTERN = /^sha256=([0-9a-f]{64})$/;

function toHex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/** `sha256=<hex>` for [body] with [secret], as GitHub writes it. */
export async function githubSignature(
  secret: string,
  body: Uint8Array,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return `sha256=${
    toHex(await crypto.subtle.sign("HMAC", key, body as BufferSource))
  }`;
}

/** Whether [header] is the signature of [body] under [secret]. */
export async function verifyGithubSignature(
  secret: string,
  body: Uint8Array,
  header: string | null,
): Promise<boolean> {
  if (secret === "" || header === null || !HEADER_PATTERN.test(header)) {
    return false;
  }
  const expected = encoder.encode(await githubSignature(secret, body));
  const given = encoder.encode(header);
  let difference = expected.length ^ given.length;
  for (let index = 0; index < expected.length; index++) {
    difference |= expected[index] ^ (given[index] ?? 0);
  }
  return difference === 0;
}
