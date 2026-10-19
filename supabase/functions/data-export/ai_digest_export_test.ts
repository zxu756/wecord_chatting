// Daily digest (F3): the settings in the archive, and no digest text.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { buildExportFiles, type ExportData } from "./export_builder.ts";

const base: ExportData = {
  generatedAt: "2026-10-23T14:03:00.000Z",
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
  conversations: [],
  messages: [],
  circles: [],
  moments: null,
  extras: null,
  files: [],
  attachmentLinks: {},
  linksExpireAt: "2026-10-30T14:03:00.000Z",
  skipped: [],
};

const digest = {
  enabled: true,
  deliver_at: "08:00",
  language: "zh",
  time_zone: "Asia/Shanghai",
  subscriptions: [
    {
      conversation_id: "c-2",
      name: "Climbing <crew>",
      circle: null,
      since: "2026-10-20T08:00:00Z",
    },
    {
      conversation_id: "c-3",
      name: "general",
      circle: "Hikers",
      since: "2026-10-21T08:00:00Z",
    },
  ],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("the digest settings add a page and a JSON file", () => {
  const files = texts({ ...base, aiDigest: digest });
  assert("pages/ai_digest.html" in files);
  assert("data/ai_digest.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/ai_digest.html"');
  assertStringIncludes(files["index.html"], "2 chats followed");
  assertStringIncludes(files["README.txt"], "data/ai_digest.json");

  const page = files["pages/ai_digest.html"];
  assertStringIncludes(page, "08:00");
  assertStringIncludes(page, "Asia/Shanghai");
  assertStringIncludes(page, "Climbing &lt;crew&gt;");
  assert(!page.includes("<crew>"));
  assertStringIncludes(page, "in Hikers");
  assertStringIncludes(page, "not included");

  const json = JSON.parse(files["data/ai_digest.json"]);
  assertEquals(json.enabled, true);
  assertEquals(json.subscriptions.length, 2);
});

Deno.test("a person who never used it says so; an export without the part has no page", () => {
  const off = texts({
    ...base,
    aiDigest: { enabled: false, subscriptions: [] },
  });
  assertStringIncludes(off["pages/ai_digest.html"], "No chats followed.");
  assertStringIncludes(off["pages/ai_digest.html"], "off");
  const absent = texts(base);
  assert(!("pages/ai_digest.html" in absent));
  assert(!("data/ai_digest.json" in absent));
  const failed = texts({ ...base, aiDigest: null });
  assert(!("pages/ai_digest.html" in failed));
});
