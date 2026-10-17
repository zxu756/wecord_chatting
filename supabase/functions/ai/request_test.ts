import { assertEquals } from "jsr:@std/assert@1";
import { MAX_TEXT_CHARS, parseAiRequest } from "./request.ts";

const id = "11111111-2222-3333-4444-555555555555";

Deno.test("status needs nothing else", () => {
  assertEquals(parseAiRequest({ action: "status" }), { action: "status" });
});

Deno.test("summarize reads the conversation, marker and language", () => {
  assertEquals(
    parseAiRequest({
      action: "summarize",
      conversation_id: id,
      after_message_id: id,
      language: "zh",
    }),
    {
      action: "summarize",
      conversationId: id,
      afterMessageId: id,
      recent: false,
      language: "zh",
    },
  );
  // No marker sent: the server's; null: from the beginning.
  const stored = parseAiRequest({ action: "summarize", conversation_id: id });
  assertEquals(
    stored?.action === "summarize" && stored.afterMessageId,
    undefined,
  );
  const fromStart = parseAiRequest({
    action: "summarize",
    conversation_id: id,
    after_message_id: null,
    recent: true,
    language: "fr",
  });
  assertEquals(fromStart, {
    action: "summarize",
    conversationId: id,
    afterMessageId: null,
    recent: true,
    language: "en",
  });
  assertEquals(parseAiRequest({ action: "summarize" }), null);
  assertEquals(
    parseAiRequest({ action: "summarize", conversation_id: "nope" }),
    null,
  );
  assertEquals(
    parseAiRequest({
      action: "summarize",
      conversation_id: id,
      after_message_id: "x",
    }),
    null,
  );
});

Deno.test("rewrite needs a known mode, text, and a target to translate", () => {
  assertEquals(
    parseAiRequest({ action: "rewrite", mode: "shorter", text: " hi there " }),
    {
      action: "rewrite",
      mode: "shorter",
      text: "hi there",
      target: null,
      conversationId: null,
    },
  );
  assertEquals(
    parseAiRequest({ action: "rewrite", mode: "translate", text: "hi" }),
    null,
  );
  assertEquals(
    parseAiRequest({
      action: "rewrite",
      mode: "translate",
      text: "hi",
      target: "ja",
      conversation_id: id,
    })?.action,
    "rewrite",
  );
  assertEquals(
    parseAiRequest({ action: "rewrite", mode: "rude", text: "hi" }),
    null,
  );
  assertEquals(
    parseAiRequest({ action: "rewrite", mode: "fix", text: "   " }),
    null,
  );
  assertEquals(
    parseAiRequest({
      action: "rewrite",
      mode: "fix",
      text: "x".repeat(MAX_TEXT_CHARS + 1),
    }),
    null,
  );
});

Deno.test("translate needs text and a supported language", () => {
  assertEquals(
    parseAiRequest({ action: "translate", text: "hola", target: "en" }),
    { action: "translate", text: "hola", target: "en", conversationId: null },
  );
  assertEquals(
    parseAiRequest({ action: "translate", text: "hola", target: "xx" }),
    null,
  );
  assertEquals(parseAiRequest({ action: "translate", target: "en" }), null);
});

Deno.test("anything else is refused", () => {
  assertEquals(parseAiRequest(null), null);
  assertEquals(parseAiRequest([]), null);
  assertEquals(parseAiRequest({ action: "delete_everything" }), null);
  assertEquals(parseAiRequest("status"), null);
});

Deno.test("a guard request names one message", () => {
  const id = "11111111-2222-3333-4444-555555555555";
  assertEquals(parseAiRequest({ action: "guard", message_id: id }), {
    action: "guard",
    messageId: id,
  });
  assertEquals(parseAiRequest({ action: "guard" }), null);
  assertEquals(parseAiRequest({ action: "guard", message_id: null }), null);
  assertEquals(parseAiRequest({ action: "guard", message_id: "nope" }), null);
});
