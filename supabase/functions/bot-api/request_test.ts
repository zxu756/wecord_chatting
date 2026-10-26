import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  cleanFileName,
  isJsonContentType,
  matchRoute,
  parseBotAuthorization,
  parseLimit,
  routeTemplate,
  statusForRpcError,
  storageFileName,
  validateCommands,
  validateEditBody,
  validateMessageBody,
  validatePollBody,
  validateRespondBody,
  validateThreadBody,
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

Deno.test("routes the endpoints of the bot API 2.0", () => {
  assertEquals(route("DELETE", `/messages/${id}`), {
    ok: true,
    route: { name: "delete_message", messageId: id },
  });
  assertEquals(route("DELETE", `/messages/${id}/reactions/%F0%9F%91%8D`), {
    ok: true,
    route: { name: "remove_reaction", messageId: id, emoji: "👍" },
  });
  assertEquals(route("POST", `/messages/${id}/thread`), {
    ok: true,
    route: { name: "create_thread", messageId: id },
  });
  assertEquals(route("GET", "/chats"), { ok: true, route: { name: "chats" } });
  assertEquals(route("GET", `/chats/${id}/messages?limit=7`), {
    ok: true,
    route: { name: "list_chat_messages", chatId: id, limit: 7, before: null },
  });
  assertEquals(route("POST", `/chats/${id}/messages`), {
    ok: true,
    route: { name: "send_chat_message", chatId: id },
  });
  assertEquals(route("POST", `/chats/${id}/files`), {
    ok: true,
    route: { name: "send_chat_file", chatId: id },
  });
  assertEquals(route("POST", `/chats/${id}/polls`), {
    ok: true,
    route: { name: "create_poll", chatId: id },
  });
  assertEquals(route("GET", `/chats/${id}/members?limit=5&after=${id}`), {
    ok: true,
    route: { name: "list_members", chatId: id, limit: 5, after: id },
  });
  assertEquals(route("GET", `/chats/${id}/members`), {
    ok: true,
    route: { name: "list_members", chatId: id, limit: 100, after: null },
  });
  assertEquals(route("GET", `/chats/${id}/members/${id}`), {
    ok: true,
    route: { name: "get_member", chatId: id, userId: id },
  });
});

Deno.test("refuses the wrong method, the wrong id and the wrong query", () => {
  assertEquals(route("GET", `/messages/${id}`), {
    ok: false,
    status: 405,
    error: "method_not_allowed",
  });
  assertEquals(route("GET", `/messages/${id}/thread`), {
    ok: false,
    status: 405,
    error: "method_not_allowed",
  });
  assertEquals(route("POST", `/messages/${id}/reactions/x`), {
    ok: false,
    status: 405,
    error: "method_not_allowed",
  });
  assertEquals(route("DELETE", "/chats"), {
    ok: false,
    status: 405,
    error: "method_not_allowed",
  });
  assertEquals(route("PUT", `/chats/${id}/files`), {
    ok: false,
    status: 405,
    error: "method_not_allowed",
  });
  assertEquals(route("POST", `/chats/${id}/members`), {
    ok: false,
    status: 405,
    error: "method_not_allowed",
  });
  assertEquals(route("GET", "/chats/not-an-id/messages").ok, false);
  assertEquals(route("GET", `/chats/${id}/other`).ok, false);
  assertEquals(route("GET", `/chats/${id}/members/x`).ok, false);
  assertEquals(route("GET", `/chats/${id}/members?limit=500`), {
    ok: false,
    status: 400,
    error: "invalid_limit",
  });
  assertEquals(route("GET", `/chats/${id}/members?after=x`), {
    ok: false,
    status: 400,
    error: "invalid_after",
  });
  assertEquals(route("GET", `/chats/${id}/messages?before=yesterday-ish`), {
    ok: false,
    status: 400,
    error: "invalid_before",
  });
});

Deno.test("the call log keeps templates, never ids", () => {
  const samples: [string, string, string][] = [
    ["GET", `/chats/${id}/messages`, "/chats/{id}/messages"],
    ["POST", `/chats/${id}/files`, "/chats/{id}/files"],
    ["GET", `/chats/${id}/members/${id}`, "/chats/{id}/members/{user}"],
    ["DELETE", `/messages/${id}`, "/messages/{id}"],
    ["PUT", `/messages/${id}/reactions/x`, "/messages/{id}/reactions/{emoji}"],
    ["POST", `/messages/${id}/thread`, "/messages/{id}/thread"],
    ["GET", "/me", "/me"],
    ["PUT", "/commands", "/commands"],
    ["POST", `/interactions/${id}/respond`, "/interactions/{id}/respond"],
  ];
  for (const [method, path, expected] of samples) {
    const matched = route(method, path);
    assert(matched.ok);
    assertEquals(routeTemplate(matched.route), expected);
    assertFalse(routeTemplate(matched.route).includes(id));
  }
});

Deno.test("validates a poll", () => {
  assertEquals(
    validatePollBody({
      question: " Where? ",
      options: ["Lake", " Ridge "],
      multiple: true,
      duration_hours: 24,
    }),
    {
      ok: true,
      value: {
        question: "Where?",
        options: ["Lake", "Ridge"],
        multi: true,
        durationHours: 24,
        anonymous: false,
      },
    },
  );
  assertEquals(validatePollBody({ question: "", options: ["a", "b"] }), {
    ok: false,
    error: "question_required",
  });
  assertEquals(validatePollBody({ question: "q", options: "a" }), {
    ok: false,
    error: "options_must_be_array",
  });
  assertEquals(validatePollBody({ question: "q", options: ["only"] }), {
    ok: false,
    error: "options_must_be_2_to_10",
  });
  assertEquals(
    validatePollBody({
      question: "q",
      options: Array.from({ length: 11 }, (_, i) => `o${i}`),
    }),
    { ok: false, error: "options_must_be_2_to_10" },
  );
  assertEquals(validatePollBody({ question: "q", options: ["a", " "] }), {
    ok: false,
    error: "invalid_option",
  });
  assertEquals(validatePollBody({ question: "q", options: ["a", "A"] }), {
    ok: false,
    error: "duplicate_option",
  });
  assertEquals(
    validatePollBody({ question: "q", options: ["a", "x".repeat(101)] }),
    { ok: false, error: "option_too_long" },
  );
  assertEquals(
    validatePollBody({ question: "x".repeat(301), options: ["a", "b"] }),
    { ok: false, error: "question_too_long" },
  );
  assertEquals(
    validatePollBody({ question: "q", options: ["a", "b"], duration_hours: 0 }),
    { ok: false, error: "invalid_duration_hours" },
  );
  assertEquals(
    validatePollBody({
      question: "q",
      options: ["a", "b"],
      duration_hours: 24.5,
    }),
    { ok: false, error: "invalid_duration_hours" },
  );
  assertEquals(
    validatePollBody({ question: "q", options: ["a", "b"], anonymous: "yes" }),
    { ok: false, error: "invalid_anonymous" },
  );
  assertEquals(validatePollBody([]), {
    ok: false,
    error: "body_must_be_object",
  });
});

Deno.test("validates a thread title; no body is fine", () => {
  assertEquals(validateThreadBody(null), { ok: true, value: { title: null } });
  assertEquals(validateThreadBody({}), { ok: true, value: { title: null } });
  assertEquals(validateThreadBody({ title: " Plans " }), {
    ok: true,
    value: { title: "Plans" },
  });
  assertEquals(validateThreadBody({ title: "x".repeat(101) }), {
    ok: false,
    error: "title_too_long",
  });
  assertEquals(validateThreadBody({ title: "  " }), {
    ok: false,
    error: "invalid_title",
  });
  assertEquals(validateThreadBody([]), {
    ok: false,
    error: "body_must_be_object",
  });
});

Deno.test("file names lose folders and hidden characters", () => {
  assertEquals(cleanFileName("notes.txt"), "notes.txt");
  assertEquals(cleanFileName("../../etc/passwd"), "passwd");
  assertEquals(cleanFileName("C:\\Users\\me\\a.pdf"), "a.pdf");
  assertEquals(cleanFileName("a\u202etxt.exe"), "atxt.exe");
  assertEquals(cleanFileName("zero\u200bwidth.txt"), "zerowidth.txt");
  assertEquals(cleanFileName("line\nbreak.txt"), "linebreak.txt");
  assertEquals(cleanFileName(".."), "file");
  assertEquals(cleanFileName("   "), "file");
  assertEquals([...cleanFileName("x".repeat(500))].length, 120);
  assertEquals(storageFileName("Résumé final.pdf"), "R_sum__final.pdf");
  assertEquals(storageFileName(".hidden"), "_hidden");
  assertEquals(storageFileName("a/b/c.txt"), "c.txt");
  assert(storageFileName("x".repeat(500)).length <= 100);
  assertEquals(storageFileName(""), "file");
});

Deno.test("maps the database errors the new routes raise", () => {
  assertEquals(statusForRpcError("23505").status, 409);
  assertEquals(statusForRpcError("54000").status, 400);
  assertEquals(statusForRpcError("P0002").status, 404);
});
