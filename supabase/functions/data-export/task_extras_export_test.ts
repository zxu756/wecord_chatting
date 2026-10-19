// Task lists 2.0 (D7): the fields of my lists, the values on the tasks I made,
// subtasks and repeat rules, in the archive.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { buildExportFiles, type ExportData } from "./export_builder.ts";

const base: ExportData = {
  generatedAt: "2026-10-25T14:03:00.000Z",
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
  linksExpireAt: "2026-11-01T14:03:00.000Z",
  skipped: [],
};

const taskExtras = {
  lists: [{
    id: "l-1",
    conversation_id: "c-1",
    title: "Chores <home>",
    created_by_me: true,
    fields: [{ id: "cost", name: "Cost", type: "number" }],
    items: [
      {
        id: "i-1",
        title: "Bins <now>",
        parent_id: null,
        repeat: { freq: "weekly", interval: 2 },
        values: [
          { field: "Cost", type: "number", value: 4 },
          {
            field: "Owner",
            type: "person",
            value: { id: "u-2", username: "bob", display_name: "Bob" },
          },
        ],
      },
      {
        id: "i-2",
        title: "Glass",
        parent_id: "i-1",
        repeat: null,
        values: [],
      },
    ],
  }],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("fields, subtasks and repeats add a page and a JSON file", () => {
  const files = texts({ ...base, taskExtras });
  assert("pages/task_extras.html" in files);
  assert("data/task_extras.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/task_extras.html"');
  assertStringIncludes(files["README.txt"], "data/task_extras.json");

  const page = files["pages/task_extras.html"];
  assertStringIncludes(page, "Chores &lt;home&gt;");
  assertStringIncludes(page, "Bins &lt;now&gt;");
  assertStringIncludes(page, "repeats every 2 weeks");
  assertStringIncludes(page, "Owner: Bob");
  assertStringIncludes(page, "Cost: 4");
  assertStringIncludes(page, "subtask");
  assertStringIncludes(page, "fields: Cost");
  // Nothing a title says becomes markup.
  assert(!page.includes("<home>"));
  assert(!page.includes("<now>"));

  const json = JSON.parse(files["data/task_extras.json"]);
  assertEquals(json.lists[0].items.length, 2);
});

Deno.test("an export without the part has no page", () => {
  const without = texts(base);
  assert(!("pages/task_extras.html" in without));
  assert(!("data/task_extras.json" in without));
});
