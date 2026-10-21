// Circle knowledge base (D6): the pages I made and the ones I read, in the
// archive - titles escaped, none for a page I can no longer read.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { buildExportFiles, type ExportData } from "./export_builder.ts";

const base: ExportData = {
  generatedAt: "2026-10-27T14:03:00.000Z",
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
  linksExpireAt: "2026-11-03T14:03:00.000Z",
  skipped: [],
};

const knowledge = {
  pages_made: [
    {
      page_id: "p-1",
      circle_id: "c-1",
      circle_name: "Pixel <Club>",
      title: "Rules <script>alert(1)</script>",
      created_at: "2026-10-27T09:00:00Z",
    },
  ],
  pages_read: [
    {
      page_id: "p-2",
      circle_id: "c-1",
      circle_name: "Pixel <Club>",
      title: null,
      read_at: "2026-10-27T10:00:00Z",
    },
    {
      page_id: "p-3",
      circle_id: "c-2",
      circle_name: "Other",
      title: "Welcome",
      read_at: "2026-10-26T10:00:00Z",
    },
  ],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("knowledge base pages add a page and a JSON file", () => {
  const files = texts({ ...base, knowledge });
  assert("pages/knowledge.html" in files);
  assert("data/knowledge.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/knowledge.html"');
  assertStringIncludes(files["index.html"], "1 made · 2 read");
  assertStringIncludes(files["README.txt"], "data/knowledge.json");

  const page = files["pages/knowledge.html"];
  assertStringIncludes(page, "Pixel &lt;Club&gt;");
  assertStringIncludes(page, "Welcome");
  // A page I can no longer read has no title.
  assertStringIncludes(page, "A page you can no longer read");
  // Nothing a title says becomes markup.
  assert(!page.includes("<script>"));
  assert(!page.includes("<Club>"));

  const json = JSON.parse(files["data/knowledge.json"]);
  assertEquals(json.pages_made.length, 1);
  assertEquals(json.pages_read.length, 2);
  assertEquals(json.pages_read[0].title, null);
});

Deno.test("an export without the part has no page; an empty one says so", () => {
  const without = texts(base);
  assert(!("pages/knowledge.html" in without));
  assert(!("data/knowledge.json" in without));

  const empty = texts({
    ...base,
    knowledge: { pages_made: [], pages_read: [] },
  });
  assertStringIncludes(empty["pages/knowledge.html"], "No pages.");
  assertStringIncludes(empty["pages/knowledge.html"], "No pages read.");
  assertStringIncludes(empty["index.html"], "0 made · 0 read");
});
