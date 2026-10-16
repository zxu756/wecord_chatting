import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { isBotLogin, parseBotsRequest, statusForRpcError } from "./request.ts";

const circle = "5bc6e021-f4f7-47d5-9a7b-9cb7529015e0";
const role = "1f0e2a7c-3b4d-4e5f-8a9b-0c1d2e3f4a5b";
const bot = "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d";

Deno.test("a POST with a circle and a name creates a bot", () => {
  assertEquals(
    parseBotsRequest("POST", { circle_id: circle, name: " Helper " }),
    {
      ok: true,
      action: "create",
      circleId: circle,
      name: "Helper",
      roleId: null,
    },
  );
  assertEquals(
    parseBotsRequest("POST", {
      action: "create",
      circle_id: circle,
      name: "Helper",
      role_id: role,
    }),
    {
      ok: true,
      action: "create",
      circleId: circle,
      name: "Helper",
      roleId: role,
    },
  );
});

Deno.test("bad create requests are 400", () => {
  for (
    const body of [
      { circle_id: "nope", name: "Helper" },
      { circle_id: circle, name: "  " },
      { circle_id: circle, name: "x".repeat(33) },
      { circle_id: circle, name: "Helper", role_id: 3 },
      { action: "rename", circle_id: circle, name: "Helper" },
    ]
  ) {
    const parsed = parseBotsRequest("POST", body);
    assertFalse(parsed.ok);
    if (!parsed.ok) assertEquals(parsed.status, 400);
  }
  const notJson = parseBotsRequest("POST", null);
  assertFalse(notJson.ok);
  if (!notJson.ok) assertEquals(notJson.error, "invalid_json");
});

Deno.test("delete by action, by DELETE body or by query", () => {
  const expected = { ok: true, action: "delete", botId: bot } as const;
  assertEquals(
    parseBotsRequest("POST", { action: "delete", bot_id: bot }),
    expected,
  );
  assertEquals(
    parseBotsRequest("DELETE", { bot_id: bot.toUpperCase() }),
    expected,
  );
  assertEquals(
    parseBotsRequest("DELETE", null, new URLSearchParams({ bot_id: bot })),
    expected,
  );
});

Deno.test("bad delete requests are refused", () => {
  for (
    const [method, body] of [
      ["POST", { action: "delete" }],
      ["POST", { action: "delete", bot_id: "x" }],
      ["DELETE", { action: "create", bot_id: bot }],
      ["DELETE", null],
    ] as const
  ) {
    const parsed = parseBotsRequest(method, body);
    assertFalse(parsed.ok);
  }
  const get = parseBotsRequest("GET", {});
  assertFalse(get.ok);
  if (!get.ok) assertEquals(get.status, 405);
});

Deno.test("rpc errors map to HTTP statuses", () => {
  assertEquals(statusForRpcError("42501"), 403);
  assertEquals(statusForRpcError("22023"), 400);
  assertEquals(statusForRpcError("54000"), 400);
  assertEquals(statusForRpcError("P0002"), 404);
  assertEquals(statusForRpcError(undefined), 500);
});

Deno.test("only bot logins are deleted", () => {
  assert(isBotLogin({ app_metadata: { provider: "bot" } }));
  assertFalse(isBotLogin({ app_metadata: { provider: "email" } }));
  assertFalse(isBotLogin({}));
  assertFalse(isBotLogin(null));
});
