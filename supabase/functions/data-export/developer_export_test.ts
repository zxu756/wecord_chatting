// The bots I made (I2 and I3): their settings and event addresses in the
// archive - names escaped, never a token or a secret.
import {
  assert,
  assertEquals,
  assertFalse,
  assertStringIncludes,
} from "jsr:@std/assert@1";
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

const developer = {
  bots: [
    {
      name: "Help<er>",
      circle: "Hike <Club>",
      made_at: "2026-10-20T09:00:00Z",
      description: "Helps <b>with</b> plans",
      open_to_direct_chats: true,
      open_to_groups: false,
      event_address: "https://example.com/events",
      event_kinds: ["message.created", "reaction.added"],
      event_subscription_on: false,
      callback_address: "https://example.com/callback",
    },
    {
      name: "Quiet",
      circle: "Hike <Club>",
      made_at: "2026-10-21T09:00:00Z",
      open_to_direct_chats: false,
      open_to_groups: false,
    },
  ],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("the bots I made add a page and a JSON file", () => {
  const files = texts({ ...base, developer });
  assert("data/developer.json" in files);
  const json = JSON.parse(files["data/developer.json"]);
  assertEquals(json.bots.length, 2);
  assertEquals(json.bots[0].event_address, "https://example.com/events");
  assertEquals(json.bots[0].event_kinds, ["message.created", "reaction.added"]);
  assert("pages/developer.html" in files);
  const html = files["pages/developer.html"];
  assertStringIncludes(html, "Quiet");
  assertStringIncludes(html, "Open to direct chats");
  assertStringIncludes(html, "Only in its circle");
  assertStringIncludes(html, "Events (paused)");
  assertStringIncludes(html, "message.created, reaction.added");
  assertStringIncludes(html, "Button presses go to");
  assertStringIncludes(files["index.html"], "pages/developer.html");
  assertStringIncludes(files["index.html"], "2 bots");
  assertStringIncludes(files["README.txt"], "data/developer.json");
});

Deno.test("what people wrote is escaped in the page", () => {
  const html = texts({ ...base, developer })["pages/developer.html"];
  assertFalse(html.includes("Help<er>"));
  assertFalse(html.includes("Hike <Club>"));
  assertFalse(html.includes("<b>with</b>"));
  assertStringIncludes(html, "Help&lt;er&gt;");
  assertStringIncludes(html, "Helps &lt;b&gt;with&lt;/b&gt; plans");
});

Deno.test("only the fields the database gave are kept, and no secret is invented", () => {
  const files = texts({ ...base, developer });
  const everything = Object.values(files).join("\n");
  assertFalse(/token|secret/i.test(files["data/developer.json"]));
  assert(everything.includes("Quiet"));
});

Deno.test("nothing is added when it could not be read, or in older callers", () => {
  for (const value of [undefined, null]) {
    const files = texts({ ...base, developer: value });
    assertFalse("data/developer.json" in files);
    assertFalse("pages/developer.html" in files);
  }
});

Deno.test("no bots still gives the files, with an empty section", () => {
  const files = texts({ ...base, developer: { bots: [] } });
  assertEquals(JSON.parse(files["data/developer.json"]), { bots: [] });
  assertStringIncludes(files["pages/developer.html"], "None.");
  assertStringIncludes(files["index.html"], "0 bots");
});
