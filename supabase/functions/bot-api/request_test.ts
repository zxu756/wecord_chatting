import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  isJsonContentType,
  matchRoute,
  parseBotAuthorization,
  parseLimit,
  statusForRpcError,
  validateCommands,
  validateEditBody,
  validateMessageBody,
  validateRespondBody,
} from "./request.ts";

const token = "A".repeat(40) + "_-9";
const id = "5bc6e021-f4f7-47d5-9a7b-9cb7529015e0";
const base = "https://example.supabase.co/functions/v1/bot-api";

function route(method: string, path: string) {
  return matchRoute(method, new URL(base + path));
}

Deno.test("reads Bot tokens from the Authorization header", () => {
  assertEquals(parseBotAuthorization(`Bot ${token}`), token);
  assertEquals(parseBotAuthorization(`bot   ${token} `), token);
  assertEquals(parseBotAuthorization(`Bearer ${token}`), null);
  assertEquals(parseBotAuthorization("Bot short"), null);
  assertEquals(parseBotAuthorization(`Bot ${token}=`), null);
  assertEquals(parseBotAuthorization(null), null);
});

Deno.test("routes every endpoint", () => {
  assertEquals(route("GET", "/me"), { ok: true, route: { name: "me" } });
  assertEquals(route("GET", "/channels"), {
    ok: true,
    route: { name: "channels" },
  });
  assertEquals(route("GET", `/channels/${id}/messages?limit=10`), {
    ok: true,
    route: { name: "list_messages", channelId: id, limit: 10, before: null },
  });
  assertEquals(route("POST", `/channels/${id.toUpperCase()}/messages`), {
    ok: true,
    route: { name: "send_message", channelId: id },
  });
  assertEquals(route("PUT", `/messages/${id}/reactions/%F0%9F%91%8D`), {
    ok: true,
    route: { name: "add_reaction", messageId: id, emoji: "👍" },
  });
  assertEquals(route("PATCH", `/messages/${id.toUpperCase()}`), {
    ok: true,
    route: { name: "edit_message", messageId: id },
  });
  assertEquals(route("GET", "/commands"), {
    ok: true,
    route: { name: "list_commands" },
  });
  assertEquals(route("PUT", "/commands"), {
    ok: true,
    route: { name: "set_commands" },
  });
  assertEquals(route("GET", "/interactions"), {
    ok: true,
    route: { name: "poll_interactions", limit: 25 },
  });
  assertEquals(route("POST", `/interactions/${id}/respond`), {
    ok: true,
    route: { name: "respond_interaction", interactionId: id },
  });
  // Without the /functions/v1 prefix too.
  assertEquals(matchRoute("GET", new URL("http://localhost/bot-api/me")), {
    ok: true,
    route: { name: "me" },
  });
});

Deno.test("unknown paths are 404 and wrong methods 405", () => {
  for (
    const path of [
      "/",
      "/nope",
      "/me/extra",
      "/channels/not-a-uuid/messages",
      `/channels/${id}/pins`,
      `/messages/${id}/reactions`,
      "/messages/not-a-uuid",
      `/interactions/${id}`,
      "/channels/%E0%A4%A/messages",
    ]
  ) {
    const result = route("GET", path);
    assertFalse(result.ok, path);
    if (!result.ok) assertEquals(result.status, 404, path);
  }
  for (
    const [method, path] of [
      ["POST", "/me"],
      ["DELETE", "/channels"],
      ["GET", `/messages/${id}/reactions/x`],
      ["POST", "/commands"],
      ["GET", `/interactions/${id}/respond`],
      ["PUT", `/messages/${id}`],
      ["GET", `/messages/${id}`],
    ]
  ) {
    const result = route(method, path);
    assertFalse(result.ok, path);
    if (!result.ok) assertEquals(result.status, 405, `${method} ${path}`);
  }
});

Deno.test("limits and times in the query are checked", () => {
  assertEquals(parseLimit(null, 50, 100), 50);
  assertEquals(parseLimit("100", 50, 100), 100);
  assertEquals(parseLimit("0", 50, 100), null);
  assertEquals(parseLimit("101", 50, 100), null);
  assertEquals(parseLimit("1.5", 50, 100), null);
  const bad = route("GET", `/channels/${id}/messages?before=yesterday`);
  assertFalse(bad.ok);
  const good = route(
    "GET",
    `/channels/${id}/messages?before=2026-10-16T10:00:00Z`,
  );
  assert(good.ok);
});

Deno.test("accepts JSON content types only", () => {
  assert(isJsonContentType("application/json; charset=utf-8"));
  assertFalse(isJsonContentType("text/plain"));
  assertFalse(isJsonContentType(null));
});

Deno.test("validates message bodies", () => {
  assertEquals(validateMessageBody({ content: " hi " }), {
    ok: true,
    value: { content: "hi", replyTo: null },
  });
  assertEquals(validateMessageBody({ content: "hi", reply_to: id }), {
    ok: true,
    value: { content: "hi", replyTo: id },
  });
  assertEquals(validateMessageBody({ content: "  " }), {
    ok: false,
    error: "content_required",
  });
  assertEquals(validateMessageBody({ content: "x".repeat(2001) }), {
    ok: false,
    error: "content_too_long",
  });
  assertEquals(validateMessageBody({ content: "hi", reply_to: "nope" }), {
    ok: false,
    error: "invalid_reply_to",
  });
  assertEquals(validateMessageBody([]), {
    ok: false,
    error: "body_must_be_object",
  });
});

Deno.test("validates command lists", () => {
  assertEquals(
    validateCommands([{ name: "ping", description: " Replies " }]),
    { ok: true, value: [{ name: "ping", description: "Replies" }] },
  );
  assertEquals(
    validateCommands({ commands: [] }),
    { ok: true, value: [] },
  );
  assertEquals(validateCommands({}), {
    ok: false,
    error: "commands_must_be_array",
  });
  assertEquals(validateCommands([{ name: "Ping", description: "x" }]), {
    ok: false,
    error: "invalid_command_name",
  });
  assertEquals(validateCommands([{ name: "ping", description: "" }]), {
    ok: false,
    error: "invalid_command_description",
  });
  assertEquals(
    validateCommands([
      { name: "ping", description: "a" },
      { name: "ping", description: "b" },
    ]),
    { ok: false, error: "duplicate_command" },
  );
  assertEquals(
    validateCommands(
      Array.from(
        { length: 26 },
        (_, i) => ({ name: `c${i}`, description: "d" }),
      ),
    ),
    { ok: false, error: "too_many_commands" },
  );
});

Deno.test("maps database errors to statuses", () => {
  assertEquals(statusForRpcError("28000").status, 401);
  assertEquals(statusForRpcError("42501").status, 403);
  assertEquals(statusForRpcError("P0002").status, 404);
  assertEquals(statusForRpcError("22023").status, 400);
  assertEquals(statusForRpcError("23505").status, 409);
  assertEquals(statusForRpcError("BT429").status, 429);
  assertEquals(statusForRpcError("P0001").error, "slowmode");
  assertEquals(statusForRpcError(undefined).status, 500);
});

const button = { type: "button", id: "go", label: "Go" };

Deno.test("message bodies carry components through", () => {
  assertEquals(validateMessageBody({ content: "hi", components: [[button]] }), {
    ok: true,
    value: { content: "hi", replyTo: null, components: [[button]] },
  });
  // None, null and an empty list mean no components.
  for (const components of [undefined, null, []]) {
    assertEquals(validateMessageBody({ content: "hi", components }), {
      ok: true,
      value: { content: "hi", replyTo: null },
    });
  }
  assertEquals(validateMessageBody({ content: "hi", components: "x" }), {
    ok: false,
    error: "components_must_be_array",
  });
  assertEquals(validateMessageBody({ content: "hi", components: {} }), {
    ok: false,
    error: "components_must_be_array",
  });
});

Deno.test("validates edits of the bot's own message", () => {
  assertEquals(validateEditBody({ content: " new " }), {
    ok: true,
    value: { content: "new", changeComponents: false, components: null },
  });
  assertEquals(validateEditBody({ components: [[button]] }), {
    ok: true,
    value: { content: null, changeComponents: true, components: [[button]] },
  });
  // null and [] take the components off.
  assertEquals(validateEditBody({ components: null }), {
    ok: true,
    value: { content: null, changeComponents: true, components: null },
  });
  assertEquals(validateEditBody({ components: [] }), {
    ok: true,
    value: { content: null, changeComponents: true, components: null },
  });
  assertEquals(validateEditBody({}), { ok: false, error: "nothing_to_change" });
  assertEquals(validateEditBody({ content: "  " }), {
    ok: false,
    error: "content_required",
  });
  assertEquals(validateEditBody({ content: "x".repeat(2001) }), {
    ok: false,
    error: "content_too_long",
  });
  assertEquals(validateEditBody([]), {
    ok: false,
    error: "body_must_be_object",
  });
  assertEquals(validateEditBody({ components: 5 }), {
    ok: false,
    error: "components_must_be_array",
  });
});

Deno.test("validates answers to interactions", () => {
  // The old form: a message.
  assertEquals(validateRespondBody({ content: " pong " }), {
    ok: true,
    value: { type: "message", response: { type: "message", content: "pong" } },
  });
  assertEquals(
    validateRespondBody({
      type: "ephemeral",
      content: "psst",
      components: [[button]],
    }),
    {
      ok: true,
      value: {
        type: "ephemeral",
        response: {
          type: "ephemeral",
          content: "psst",
          components: [[button]],
        },
      },
    },
  );
  assertEquals(validateRespondBody({ type: "update", components: null }), {
    ok: true,
    value: {
      type: "update",
      response: { type: "update", components: null },
    },
  });
  assertEquals(validateRespondBody({ type: "ack" }), {
    ok: true,
    value: { type: "ack", response: { type: "ack" } },
  });
  assertEquals(validateRespondBody({ type: "shout", content: "x" }), {
    ok: false,
    error: "invalid_type",
  });
  assertEquals(validateRespondBody({ type: 5 }), {
    ok: false,
    error: "invalid_type",
  });
  assertEquals(validateRespondBody({ type: "message" }), {
    ok: false,
    error: "content_required",
  });
  assertEquals(validateRespondBody({ type: "ephemeral", content: "" }), {
    ok: false,
    error: "content_required",
  });
  assertEquals(validateRespondBody({ type: "update" }), {
    ok: false,
    error: "nothing_to_change",
  });
  assertEquals(validateRespondBody({ type: "ack", content: "x" }), {
    ok: false,
    error: "ack_has_no_content",
  });
  assertEquals(validateRespondBody({ content: "x".repeat(2001) }), {
    ok: false,
    error: "content_too_long",
  });
  assertEquals(validateRespondBody({ content: "x", components: "no" }), {
    ok: false,
    error: "components_must_be_array",
  });
  assertEquals(validateRespondBody("x"), {
    ok: false,
    error: "body_must_be_object",
  });
});
