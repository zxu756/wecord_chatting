import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { callbackHeaders, signBody } from "./sign.ts";
import { isAuthorized } from "./auth.ts";

// Worked out independently: HMAC-SHA256, key "secret", message
// "1700000000.{"a":1}".
async function reference(
  key: string,
  message: string,
): Promise<string> {
  const k = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign(
    "HMAC",
    k,
    new TextEncoder().encode(message),
  );
  return [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("the signature is v1= and the HMAC of timestamp.body", async () => {
  const body = '{"a":1}';
  const signature = await signBody("secret", 1700000000, body);
  assertEquals(
    signature,
    "v1=" + await reference("secret", '1700000000.{"a":1}'),
  );
  assert(/^v1=[0-9a-f]{64}$/.test(signature));
});

Deno.test("the signature changes with the secret, the time and the body", async () => {
  const base = await signBody("secret", 1700000000, "{}");
  assertNotEquals(base, await signBody("other", 1700000000, "{}"));
  assertNotEquals(base, await signBody("secret", 1700000001, "{}"));
  assertNotEquals(base, await signBody("secret", 1700000000, "{ }"));
  // The same input always gives the same signature.
  assertEquals(base, await signBody("secret", 1700000000, "{}"));
});

Deno.test("the headers carry the time, the signature and the delivery", async () => {
  const headers = await callbackHeaders("secret", 1700000000, "{}", "abc");
  assertEquals(headers["X-WeCord-Timestamp"], "1700000000");
  assertEquals(headers["X-WeCord-Delivery"], "abc");
  assertEquals(
    headers["X-WeCord-Signature"],
    await signBody("secret", 1700000000, "{}"),
  );
  assertEquals(headers["Content-Type"], "application/json");
});

Deno.test("only the dispatch secret as a bearer token is let in", () => {
  assert(isAuthorized("Bearer s3cret", "s3cret"));
  assert(!isAuthorized("Bearer other", "s3cret"));
  assert(!isAuthorized("s3cret", "s3cret"));
  assert(!isAuthorized("Bearer s3cret ", "s3cret"));
  assert(!isAuthorized(null, "s3cret"));
  assert(!isAuthorized("Bearer ", ""));
  assert(!isAuthorized("", ""));
});
