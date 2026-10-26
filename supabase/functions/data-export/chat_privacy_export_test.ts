// Advanced chat privacy (G6) in the data export: a restricted chat's words
// and files stay out of the archive, the rest is kept and says why; the chats
// the person asked to restrict and the screenshot reports they caused are in
// a page of their own, names escaped, nothing of anyone else's.
import {
  assert,
  assertEquals,
  assertFalse,
  assertStringIncludes,
} from "jsr:@std/assert@1";
import {
  isMissingFunction,
  withholdMessage,
  withholdRestricted,
} from "./chat_privacy.ts";
import {
  attachmentsToSign,
  buildExportFiles,
  type ExportData,
  type ExportMessage,
} from "./export_builder.ts";

const secretFile = {
  kind: "image",
  bucket: "chat-images",
  path: "chat-1/secret.jpg",
  name: "secret.jpg",
  size: 100,
};

function message(
  id: string,
  conversationId: string,
  overrides: Partial<ExportMessage> = {},
): ExportMessage {
  return {
    id,
    conversationId,
    type: "text",
    body: `words of ${id}`,
    attachment: null,
    createdAt: "2026-10-28T09:00:00Z",
    editedAt: null,
    recalledAt: null,
    ...overrides,
  };
}

const messages = [
  message("m1", "plan", { type: "image", attachment: secretFile }),
  message("m2", "plan"),
  message("m3", "open"),
  message("m4", "plan", { recalledAt: "2026-10-28T10:00:00Z", body: "" }),
];

const base: ExportData = {
  generatedAt: "2026-10-28T14:03:00.000Z",
  user: {
    id: "u-1",
    email: "ada@example.com",
    createdAt: null,
    lastSignInAt: null,
  },
  profile: { id: "u-1", username: "ada", display_name: "Ada" },
  settings: {},
  friends: [],
  friendRequests: [],
  blocked: [],
  conversations: [
    {
      id: "plan",
      kind: "group",
      name: "Plan <Secret>",
      circleName: null,
      joinedAt: null,
      role: "owner",
      createdAt: null,
      restricted: true,
    },
    {
      id: "open",
      kind: "group",
      name: "Open",
      circleName: null,
      joinedAt: null,
      role: "member",
      createdAt: null,
    },
  ],
  messages: [],
  circles: [],
  moments: null,
  extras: null,
  files: [],
  attachmentLinks: {},
  linksExpireAt: "2026-11-04T14:03:00.000Z",
  skipped: [],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("a restricted chat's messages lose their words and files", () => {
  const out = withholdRestricted(messages, new Set(["plan"]));
  assertEquals(out.length, 4);
  for (const id of ["m1", "m2"]) {
    const m = out.find((x) => x.id === id)!;
    assertEquals(m.body, "");
    assertEquals(m.attachment, null);
    assertEquals(m.withheld, true);
  }
  // Kept: that it was sent, and when.
  assertEquals(out[0].createdAt, "2026-10-28T09:00:00Z");
  assertEquals(out[0].type, "image");
  // Other chats and already deleted messages are as they were.
  assertEquals(out.find((x) => x.id === "m3"), messages[2]);
  assertEquals(out.find((x) => x.id === "m4"), messages[3]);
});

Deno.test("no restricted chat, nothing changes", () => {
  assertEquals(withholdRestricted(messages, new Set()), messages);
});

Deno.test("the original message is not touched", () => {
  const copy = withholdMessage(messages[0]);
  assertEquals(messages[0].body, "words of m1");
  assertEquals(copy.withheld, true);
});

Deno.test("withheld files are not signed for download", () => {
  const out = withholdRestricted(messages, new Set(["plan"]));
  assertEquals(attachmentsToSign(out), []);
  assertEquals(attachmentsToSign(messages).length, 1);
});

Deno.test("the archive says a chat's words are left out, and leaves them out", () => {
  const out = withholdRestricted(messages, new Set(["plan"]));
  const files = texts({ ...base, messages: out });
  const all = JSON.stringify(files);
  assertFalse(all.includes("words of m1"));
  assertFalse(all.includes("words of m2"));
  assertFalse(all.includes("secret.jpg"));
  assertStringIncludes(all, "words of m3");

  const json = JSON.parse(files["data/messages.json"]);
  const m2 = json.find((m: { id: string }) => m.id === "m2");
  assertEquals(m2.text, "");
  assertEquals(m2.attachment, null);
  assert(typeof m2.withheld === "string");
  assertFalse("withheld" in json.find((m: { id: string }) => m.id === "m3"));

  const planPage =
    Object.entries(files).find(([path]) =>
      path.startsWith("messages/") && path.includes("plan")
    )![1];
  assertStringIncludes(planPage, "advanced chat privacy");
  assertStringIncludes(planPage, "3 messages");
  const conversations = JSON.parse(files["data/conversations.json"]);
  assertEquals(
    conversations.find((c: { id: string }) => c.id === "plan")
      .messages_from_you,
    3,
  );
});

Deno.test("the chats I asked to restrict and my reports get a page and a file", () => {
  const files = texts({
    ...base,
    chatPrivacy: {
      requested_in: [
        { conversation_id: "plan", kind: "group", restricted_now: true },
      ],
      screenshot_reports: [
        {
          reported_at: "2026-10-28T09:30:00Z",
          event: "recording",
          conversation_id: "open",
        },
        {
          reported_at: "2026-10-28T09:31:00Z",
          event: "screenshot",
          conversation_id: "gone",
        },
      ],
    },
  });
  const json = JSON.parse(files["data/chat_privacy.json"]);
  assertEquals(json.requested_in[0].chat, "Plan <Secret>");
  assertEquals(json.screenshot_reports.length, 2);
  assertEquals(json.screenshot_reports[1].chat, null);
  const html = files["pages/chat_privacy.html"];
  assertStringIncludes(html, "Plan &lt;Secret&gt;");
  assertFalse(html.includes("Plan <Secret>"));
  assertStringIncludes(html, "restricted now");
  assertStringIncludes(html, "Screen recording");
  assertStringIncludes(html, "A conversation");
  assertStringIncludes(files["index.html"], "pages/chat_privacy.html");
  assertStringIncludes(files["index.html"], "1 chats · 2 screenshot reports");
  assertStringIncludes(files["README.txt"], "data/chat_privacy.json");
});

Deno.test("nothing is added when it could not be read, or in older callers", () => {
  for (const chatPrivacy of [undefined, null]) {
    const files = texts({ ...base, chatPrivacy });
    assertFalse("data/chat_privacy.json" in files);
    assertFalse("pages/chat_privacy.html" in files);
  }
});

Deno.test("a missing database function is told apart from a failing one", () => {
  assert(isMissingFunction({ code: "PGRST202" }));
  assert(isMissingFunction({ code: "42883" }));
  assertFalse(isMissingFunction({ code: "57014" }));
  assertFalse(isMissingFunction(null));
  assertFalse(isMissingFunction("PGRST202"));
});
