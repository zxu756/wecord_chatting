import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  isDeclaredTooLarge,
  isHttpUrl,
  isJsonContentType,
  parseWebhookPath,
  statusForRpcError,
  validatePayload,
} from "./request.ts";

const id = "5bc6e021-f4f7-47d5-9a7b-9cb7529015e0";
const token = "A".repeat(40) + "_-9";

Deno.test("parses the webhook id and token from the path", () => {
  assertEquals(parseWebhookPath(`/webhook/${id}/${token}`), {
    ok: true,
    id,
    token,
  });
  assertEquals(
    parseWebhookPath(`/functions/v1/webhook/${id.toUpperCase()}/${token}/`),
    { ok: true, id, token },
  );
});

Deno.test("unknown shapes and malformed ids are 404", () => {
  for (
    const path of [
      "/webhook",
      `/webhook/${id}`,
      `/webhook/${id}/${token}/extra`,
      `/webhook/not-a-uuid/${token}`,
      `/webhook/${id.slice(0, -1)}/${token}`,
      `/other/${id}/${token}`,
      `/webhook/%E0%A4%A/${token}`,
    ]
  ) {
    assertEquals(parseWebhookPath(path), { ok: false, status: 404 }, path);
  }
});

Deno.test("malformed tokens are 401", () => {
  for (
    const bad of [
      "short",
      "A".repeat(44),
      "A".repeat(42) + "=",
      "A".repeat(42) + "+",
      "%E0%A4%A",
    ]
  ) {
    assertEquals(
      parseWebhookPath(`/webhook/${id}/${bad}`),
      { ok: false, status: 401 },
      bad,
    );
  }
});

Deno.test("accepts JSON content types only", () => {
  assert(isJsonContentType("application/json"));
  assert(isJsonContentType("Application/JSON; charset=utf-8"));
  assert(isJsonContentType("application/vnd.api+json"));
  assertFalse(isJsonContentType(null));
  assertFalse(isJsonContentType("text/plain"));
  assertFalse(isJsonContentType("multipart/form-data"));
});

Deno.test("flags declared bodies over 16 KB", () => {
  assertFalse(isDeclaredTooLarge(null));
  assertFalse(isDeclaredTooLarge("16384"));
  assert(isDeclaredTooLarge("16385"));
  assertFalse(isDeclaredTooLarge("nonsense"));
});

Deno.test("validates content, username and avatar", () => {
  assertEquals(
    validatePayload({
      content: "  **Build** passed ",
      username: " CI ",
      avatar_url: "https://example.com/ci.png",
    }),
    {
      ok: true,
      payload: {
        content: "**Build** passed",
        username: "CI",
        avatarUrl: "https://example.com/ci.png",
      },
    },
  );
  assertEquals(
    validatePayload({ content: "hi", username: "", avatar_url: "" }),
    {
      ok: true,
      payload: { content: "hi", username: null, avatarUrl: null },
    },
  );
  assertEquals(validatePayload({ content: "x".repeat(2000) }).ok, true);

  const failures: [unknown, string][] = [
    [null, "body_must_be_object"],
    [[], "body_must_be_object"],
    ["text", "body_must_be_object"],
    [{}, "content_required"],
    [{ content: 5 }, "content_required"],
    [{ content: "   " }, "content_required"],
    [{ content: "x".repeat(2001) }, "content_too_long"],
    [{ content: "hi", username: 7 }, "invalid_username"],
    [{ content: "hi", username: "u".repeat(81) }, "invalid_username"],
    [
      { content: "hi", avatar_url: "javascript:alert(1)" },
      "invalid_avatar_url",
    ],
    [
      { content: "hi", avatar_url: "ftp://example.com/a.png" },
      "invalid_avatar_url",
    ],
    [{ content: "hi", avatar_url: 3 }, "invalid_avatar_url"],
  ];
  for (const [body, error] of failures) {
    assertEquals(validatePayload(body), { ok: false, error }, String(body));
  }
});

Deno.test("http urls", () => {
  assert(isHttpUrl("http://example.com"));
  assert(isHttpUrl("https://example.com/a.png?x=1"));
  assertFalse(isHttpUrl("https://exa mple.com"));
  assertFalse(isHttpUrl("data:image/png;base64,AAAA"));
  assertFalse(isHttpUrl(`https://example.com/${"a".repeat(2048)}`));
});

Deno.test("maps RPC errors to statuses", () => {
  assertEquals(statusForRpcError("P0002").status, 404);
  assertEquals(statusForRpcError("28000").status, 401);
  assertEquals(statusForRpcError("22023").status, 400);
  assertEquals(statusForRpcError("42501").status, 403);
  assertEquals(statusForRpcError("WH429").status, 429);
  assertEquals(statusForRpcError("XX000").status, 500);
  assertEquals(statusForRpcError(undefined).status, 500);
});
