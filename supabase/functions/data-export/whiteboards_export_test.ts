// Whiteboards (D10): the boards I started and what I drew or wrote on boards
// of my chats, in the archive - names and words escaped, nothing of anybody
// else's.
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

const whiteboards = {
  boards_made: [
    {
      title: "Trip <plan>",
      chat: "Hike crew",
      elements: 12,
      created_at: "2026-10-20T09:00:00Z",
    },
    {
      title: "",
      chat: null,
      elements: 0,
      created_at: "2026-10-21T09:00:00Z",
    },
  ],
  drawn_on: [
    {
      board: "周末计划",
      chat: "Hike crew",
      strokes: 4,
      shapes: 2,
      sticky_notes: 3,
      texts: 1,
      pictures: 0,
      words: ["Pack the <tent>", "带上炉子"],
    },
  ],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("whiteboards add a page and a JSON file", () => {
  const files = texts({ ...base, whiteboards });
  assert("pages/whiteboards.html" in files);
  assert("data/whiteboards.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/whiteboards.html"');
  assertStringIncludes(files["index.html"], "2 started · 1 drawn on");
  assertStringIncludes(files["README.txt"], "data/whiteboards.json");

  const page = files["pages/whiteboards.html"];
  assertStringIncludes(page, "Trip &lt;plan&gt;");
  assertStringIncludes(page, "Untitled whiteboard");
  assertStringIncludes(page, "周末计划");
  assertStringIncludes(page, "Pack the &lt;tent&gt;");
  assertStringIncludes(page, "带上炉子");
  assertStringIncludes(page, "4 lines");
  assert(!page.includes("<tent>"));

  const json = JSON.parse(files["data/whiteboards.json"]);
  assertEquals(json.boards_made.length, 2);
  assertEquals(json.drawn_on[0].sticky_notes, 3);
  assertEquals(json.drawn_on[0].words.length, 2);
});

Deno.test("an older export without whiteboards has neither file", () => {
  const without = texts(base);
  assert(!("pages/whiteboards.html" in without));
  assert(!("data/whiteboards.json" in without));
});

Deno.test("empty whiteboards say so", () => {
  const empty = texts({
    ...base,
    whiteboards: { boards_made: [], drawn_on: [] },
  });
  assertStringIncludes(empty["pages/whiteboards.html"], "None.");
});
