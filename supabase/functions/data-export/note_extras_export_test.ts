// Notes 2.0 (D5): the comments I wrote, my templates and the pages I
// published, in the archive - and no link, no one else's words.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { buildExportFiles, type ExportData } from "./export_builder.ts";

const base: ExportData = {
  generatedAt: "2026-10-24T14:03:00.000Z",
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
  linksExpireAt: "2026-10-31T14:03:00.000Z",
  skipped: [],
};

const extras = {
  comments: [
    {
      id: "c-1",
      note_id: "n-1",
      note_title: "Trip <plan>",
      reply: false,
      quoted: "the <b>train</b>",
      body: "Is this <script>alert(1)</script> final?",
      created_at: "2026-10-24T09:00:00Z",
      edited_at: null,
      resolved: true,
    },
    {
      id: "c-2",
      note_id: "n-1",
      note_title: "",
      reply: true,
      quoted: null,
      body: "Yes",
      created_at: "2026-10-24T09:05:00Z",
      edited_at: null,
      resolved: false,
    },
  ],
  templates: [
    {
      id: "t-1",
      name: "Weekly <report>",
      icon: "x",
      title: "Week",
      blocks: [{ kind: "h2", text: "Done" }, { kind: "bullet", text: "x" }],
      created_at: "2026-10-23T09:00:00Z",
    },
  ],
  published: [
    {
      note_id: "n-1",
      note_title: "Trip <plan>",
      published_at: "2026-10-24T10:00:00Z",
      allow_indexing: true,
    },
  ],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("comments, templates and published pages add a page and a JSON file", () => {
  const files = texts({ ...base, noteExtras: extras });
  assert("pages/note_extras.html" in files);
  assert("data/note_extras.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/note_extras.html"');
  assertStringIncludes(
    files["index.html"],
    "2 comments · 1 template · 1 published",
  );
  assertStringIncludes(files["README.txt"], "data/note_extras.json");

  const page = files["pages/note_extras.html"];
  assertStringIncludes(page, "Trip &lt;plan&gt;");
  assertStringIncludes(page, "Weekly &lt;report&gt;");
  assertStringIncludes(page, "Untitled note");
  assertStringIncludes(page, "search engines allowed");
  assertStringIncludes(page, "are not included");
  // Nothing a note or comment says becomes markup.
  assert(!page.includes("<script>"));
  assert(!page.includes("<b>train"));
  assert(!page.includes("<plan>"));

  const json = JSON.parse(files["data/note_extras.json"]);
  assertEquals(json.comments.length, 2);
  assertEquals(json.templates[0].blocks.length, 2);
  assertEquals(json.published[0].note_id, "n-1");
  assert(!("token" in json.published[0]));
});

Deno.test("an export without the part has no page; an empty one says so", () => {
  const without = texts(base);
  assert(!("pages/note_extras.html" in without));
  assert(!("data/note_extras.json" in without));

  const empty = texts({
    ...base,
    noteExtras: { comments: [], templates: [], published: [] },
  });
  assertStringIncludes(empty["pages/note_extras.html"], "No comments.");
  assertStringIncludes(empty["pages/note_extras.html"], "No templates.");
  assertStringIncludes(empty["pages/note_extras.html"], "No published pages.");
  assertStringIncludes(
    empty["index.html"],
    "0 comments · 0 templates · 0 published",
  );
});
