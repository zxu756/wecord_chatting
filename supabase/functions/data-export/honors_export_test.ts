// Circle titles and honors (C7): my titles, honors and streaks, and the
// circles I stay out of, in the archive - names escaped.
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

const honors = {
  titles: [
    {
      circle_id: "c-1",
      circle_name: "Pixel <Club>",
      title: "Scout",
      given_at: "2026-10-27T09:00:00Z",
    },
  ],
  honors: [
    {
      circle_id: "c-1",
      circle_name: "Pixel <Club>",
      kind: "weekly",
      level: 3,
      period_start: "2026-10-19",
      awarded_at: "2026-10-27T00:40:00Z",
    },
    {
      circle_id: "c-1",
      circle_name: "Pixel <Club>",
      kind: "streak",
      level: 30,
      period_start: "2026-10-20",
      awarded_at: "2026-10-27T00:40:00Z",
    },
  ],
  streaks: [
    {
      circle_id: "c-1",
      circle_name: "Pixel <Club>",
      current_streak: 12,
      best_streak: 31,
      as_of: "2026-10-27",
    },
  ],
  opted_out: [
    { circle_id: "c-2", circle_name: "Other", since: "2026-10-01T00:00:00Z" },
  ],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("titles and honors add a page and a JSON file", () => {
  const files = texts({ ...base, honors });
  assert("pages/honors.html" in files);
  assert("data/honors.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/honors.html"');
  assertStringIncludes(files["index.html"], "1 titles · 2 honors");
  assertStringIncludes(files["README.txt"], "data/honors.json");

  const page = files["pages/honors.html"];
  assertStringIncludes(page, "Scout");
  assertStringIncludes(page, "Pixel &lt;Club&gt;");
  assertStringIncludes(page, "30-day streak");
  assertStringIncludes(page, "Week level 3");
  assertStringIncludes(page, "streak 12 days, best 31");
  assertStringIncludes(page, "Other");
  // Nothing a circle's name says becomes markup.
  assert(!page.includes("<Club>"));

  const json = JSON.parse(files["data/honors.json"]);
  assertEquals(json.titles.length, 1);
  assertEquals(json.honors.length, 2);
  assertEquals(json.opted_out.length, 1);
});

Deno.test("an export without the part has no page; an empty one says so", () => {
  const without = texts(base);
  assert(!("pages/honors.html" in without));
  assert(!("data/honors.json" in without));

  const empty = texts({
    ...base,
    honors: { titles: [], honors: [], streaks: [], opted_out: [] },
  });
  assertStringIncludes(empty["pages/honors.html"], "No titles.");
  assertStringIncludes(empty["pages/honors.html"], "No honors.");
  assertStringIncludes(empty["index.html"], "0 titles · 0 honors");
});
