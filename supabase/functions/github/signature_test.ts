import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { githubSignature, verifyGithubSignature } from "./signature.ts";
import {
  isDeclaredTooLarge,
  isJsonContentType,
  MAX_BODY_BYTES,
  parseGithubPath,
  statusForRpcError,
} from "./request.ts";

const secret = "s3cr3t-".repeat(6) + "abc";
const body = new TextEncoder().encode('{"zen":"Keep it logically awesome."}');

Deno.test("GitHub's own example: the documented test vector", async () => {
  // From GitHub's documentation, "Validating webhook deliveries".
  const signature = await githubSignature(
    "It's a Secret to Everybody",
    new TextEncoder().encode("Hello, World!"),
  );
  assertEquals(
    signature,
    "sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17",
  );
});

Deno.test("a signature made with the secret passes", async () => {
  const header = await githubSignature(secret, body);
  assert(await verifyGithubSignature(secret, body, header));
});

Deno.test("anything else fails", async () => {
  const header = await githubSignature(secret, body);
  assertFalse(await verifyGithubSignature(secret, body, null));
  assertFalse(await verifyGithubSignature(secret, body, ""));
  assertFalse(await verifyGithubSignature("", body, header));
  assertFalse(await verifyGithubSignature("other-secret", body, header));
  assertFalse(
    await verifyGithubSignature(
      secret,
      new TextEncoder().encode('{"zen":"x"}'),
      header,
    ),
  );
  // The old SHA-1 header, the wrong prefix, upper case, short, long.
  assertFalse(
    await verifyGithubSignature(
      secret,
      body,
      header.replace("sha256=", "sha1="),
    ),
  );
  assertFalse(await verifyGithubSignature(secret, body, header.toUpperCase()));
  assertFalse(await verifyGithubSignature(secret, body, header.slice(0, -2)));
  assertFalse(await verifyGithubSignature(secret, body, header + "00"));
  assertFalse(
    await verifyGithubSignature(secret, body, header.replace("sha256=", "")),
  );
});

Deno.test("the path holds the connection id", () => {
  const id = "0b1c2d3e-4f50-4a6b-8c7d-9e0f1a2b3c4d";
  assertEquals(parseGithubPath(`/functions/v1/github/${id}`), { ok: true, id });
  assertEquals(parseGithubPath(`/github/${id.toUpperCase()}`), {
    ok: true,
    id,
  });
  assertEquals(parseGithubPath(`/github/${id}/`), { ok: true, id });
  for (
    const bad of [
      "/github",
      "/github/nope",
      `/github/${id}/extra`,
      `/other/${id}`,
      "/",
      `/github/%E0%A4%A`,
    ]
  ) {
    assertEquals(parseGithubPath(bad), { ok: false }, bad);
  }
});

Deno.test("limits and statuses", () => {
  assert(isJsonContentType("application/json; charset=utf-8"));
  assertFalse(isJsonContentType("application/x-www-form-urlencoded"));
  assertFalse(isJsonContentType(null));
  assertFalse(isDeclaredTooLarge(null));
  assertFalse(isDeclaredTooLarge(String(MAX_BODY_BYTES)));
  assert(isDeclaredTooLarge(String(MAX_BODY_BYTES + 1)));
  assertEquals(statusForRpcError("P0002").status, 404);
  assertEquals(statusForRpcError("42501").status, 403);
  assertEquals(statusForRpcError("WH429").status, 429);
  assertEquals(statusForRpcError("22023").status, 400);
  assertEquals(statusForRpcError("XX000").status, 500);
});
