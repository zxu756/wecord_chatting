// Workflow automation (D9): the workflows I made and the runs about me are in
// the archive - names escaped, nothing about what other people did.
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

const workflows = {
  workflows_made: [
    {
      name: "Welcome <new> people",
      where: "Hike <Club>",
      trigger: "member_joined",
      trigger_config: {},
      actions: [{ type: "send_message", text: "Hi" }, { type: "add_role" }],
      running: true,
      paused_reason: null,
      created_at: "2026-10-20T00:00:00Z",
    },
    {
      name: "Friday report",
      where: null,
      trigger: "schedule",
      trigger_config: { recurrence: "weekly" },
      actions: [{ type: "send_form" }],
      running: false,
      paused_reason: "creator_gone",
      created_at: "2026-10-10T00:00:00Z",
    },
  ],
  runs_about_me: [
    {
      workflow: "Thank <you>",
      status: "succeeded",
      at: "2026-10-25T10:00:00Z",
    },
  ],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("workflows add a page and a JSON file", () => {
  const files = texts({ ...base, workflows });
  assert("pages/workflows.html" in files);
  assert("data/workflows.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/workflows.html"');
  assertStringIncludes(files["index.html"], "2 workflows");
  assertStringIncludes(files["README.txt"], "data/workflows.json");

  const page = files["pages/workflows.html"];
  assertStringIncludes(page, "Welcome &lt;new&gt; people");
  assertStringIncludes(page, "Hike &lt;Club&gt;");
  assertStringIncludes(page, "send_message, add_role");
  assertStringIncludes(page, "paused (creator_gone)");
  assertStringIncludes(page, "Thank &lt;you&gt;");
  assert(!page.includes("<new>"));
  assert(!page.includes("<Club>"));
  assert(!page.includes("<you>"));

  const json = JSON.parse(files["data/workflows.json"]);
  assertEquals(json.workflows_made.length, 2);
  assertEquals(json.workflows_made[1].paused_reason, "creator_gone");
  assertEquals(json.runs_about_me[0].status, "succeeded");
});

Deno.test("an export without workflows has no page; an empty one says so", () => {
  const without = texts(base);
  assert(!("pages/workflows.html" in without));
  assert(!("data/workflows.json" in without));

  const empty = texts({
    ...base,
    workflows: { workflows_made: [], runs_about_me: [] },
  });
  assertStringIncludes(empty["pages/workflows.html"], "None.");
  assertStringIncludes(empty["index.html"], "0 workflows");
});
