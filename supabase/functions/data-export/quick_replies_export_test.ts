// Quick replies and the away auto-reply (A8): what I keep and what I set, in
// the archive - names escaped, nothing of anybody else's.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { buildExportFiles, type ExportData } from "./export_builder.ts";

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
  conversations: [],
  messages: [],
  circles: [],
  moments: null,
  extras: null,
  files: [],
  attachmentLinks: {},
  linksExpireAt: "2026-11-04T14:03:00.000Z",
  skipped: [],
};

const quickReplies = {
  quick_replies: [
    {
      shortcut: "addr",
      body: "12 Main <Street>",
      created_at: "2026-10-20T09:00:00Z",
      updated_at: "2026-10-20T09:00:00Z",
    },
    {
      shortcut: "地址",
      body: "朝阳路 1 号",
      created_at: "2026-10-21T09:00:00Z",
      updated_at: "2026-10-21T09:00:00Z",
    },
  ],
  away: {
    enabled: true,
    message: "Back on <Monday>",
    until: "2026-11-02T00:00:00Z",
    during_quiet_hours: true,
  },
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("quick replies add a page and a JSON file", () => {
  const files = texts({ ...base, quickReplies });
  assert("pages/quick_replies.html" in files);
  assert("data/quick_replies.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/quick_replies.html"');
  assertStringIncludes(files["index.html"], "2 quick replies");
  assertStringIncludes(files["README.txt"], "data/quick_replies.json");

  const page = files["pages/quick_replies.html"];
  assertStringIncludes(page, "/addr");
  assertStringIncludes(page, "12 Main &lt;Street&gt;");
  assertStringIncludes(page, "朝阳路 1 号");
  assertStringIncludes(page, "Back on &lt;Monday&gt;");
  assertStringIncludes(page, "also during quiet hours");
  assert(!page.includes("<Street>"));
  assert(!page.includes("<Monday>"));

  const json = JSON.parse(files["data/quick_replies.json"]);
  assertEquals(json.quick_replies.length, 2);
  assertEquals(json.away.message, "Back on <Monday>");
});

Deno.test("an export without the part has no page; an empty one says so", () => {
  const without = texts(base);
  assert(!("pages/quick_replies.html" in without));
  assert(!("data/quick_replies.json" in without));

  const empty = texts({
    ...base,
    quickReplies: { quick_replies: [], away: null },
  });
  assertStringIncludes(empty["pages/quick_replies.html"], "No quick replies.");
  assertStringIncludes(empty["pages/quick_replies.html"], "None.");
  assertStringIncludes(empty["index.html"], "0 quick replies");
  assertEquals(JSON.parse(empty["data/quick_replies.json"]).away, null);
});
