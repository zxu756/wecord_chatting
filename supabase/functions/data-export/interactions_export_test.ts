// Bot buttons and commands (I1): what I pressed or typed into bots' components
// and what bots told me privately, in the archive - names escaped, nothing of
// anyone else's.
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

const interactions = {
  presses: [
    {
      sent_at: "2026-10-28T09:00:00Z",
      kind: "component",
      bot: "Help<er>",
      circle: "Hike <Club>",
      component: "Add a note",
      component_type: "modal",
      values: { text: "<b>line one</b>", name: "Ada" },
      answered: true,
    },
    {
      sent_at: "2026-10-28T09:05:00Z",
      kind: "command",
      bot: "Helper",
      circle: "Hike <Club>",
      command: "ping",
      options: "now",
      answered: false,
    },
    {
      sent_at: "2026-10-28T09:06:00Z",
      kind: "component",
      bot: "Helper",
      circle: "Hike <Club>",
      component: "Pick a trail",
      component_type: "select",
      values: ["ridge", "lake"],
      answered: true,
    },
  ],
  private_replies: [
    {
      received_at: "2026-10-28T09:01:00Z",
      bot: "Helper",
      text: "Only for <you>",
    },
  ],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("bot interactions add a page and a JSON file", () => {
  const files = texts({ ...base, interactions });
  assert("data/bot_interactions.json" in files);
  const json = JSON.parse(files["data/bot_interactions.json"]);
  assertEquals(json.presses.length, 3);
  assertEquals(json.private_replies.length, 1);
  assertEquals(json.presses[0].values, {
    text: "<b>line one</b>",
    name: "Ada",
  });
  assert("pages/bot_interactions.html" in files);
  const html = files["pages/bot_interactions.html"];
  assertStringIncludes(html, "Add a note");
  assertStringIncludes(html, "/ping now");
  assertStringIncludes(html, "not answered");
  assertStringIncludes(html, "ridge");
  assertStringIncludes(html, "Only for");
  assertStringIncludes(files["index.html"], "pages/bot_interactions.html");
  assertStringIncludes(files["index.html"], "3 presses · 1 private replies");
  assertStringIncludes(files["README.txt"], "data/bot_interactions.json");
});

Deno.test("what bots and people wrote is escaped in the page", () => {
  const html = texts({ ...base, interactions })["pages/bot_interactions.html"];
  assertFalse(html.includes("<b>line one</b>"));
  assertFalse(html.includes("Help<er>"));
  assertFalse(html.includes("Hike <Club>"));
  assertFalse(html.includes("Only for <you>"));
  assertStringIncludes(html, "&lt;b&gt;line one&lt;/b&gt;");
  assertStringIncludes(html, "Help&lt;er&gt;");
});

Deno.test("nothing is added when it could not be read, or in older callers", () => {
  for (const interactionsValue of [undefined, null]) {
    const files = texts({ ...base, interactions: interactionsValue });
    assertFalse("data/bot_interactions.json" in files);
    assertFalse("pages/bot_interactions.html" in files);
  }
});

Deno.test("an empty list still gives the files, with empty sections", () => {
  const files = texts({
    ...base,
    interactions: { presses: [], private_replies: [] },
  });
  assertEquals(JSON.parse(files["data/bot_interactions.json"]), {
    presses: [],
    private_replies: [],
  });
  assertStringIncludes(files["pages/bot_interactions.html"], "None.");
});
