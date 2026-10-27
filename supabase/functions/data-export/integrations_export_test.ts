// The RSS feeds and GitHub connections I added (I6): in the archive, names
// escaped, never a secret.
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

const integrations = {
  feeds: [
    {
      circle: "Hike <Club>",
      channel: "news",
      address: "https://blog.example.com/feed.xml",
      title: "Blog <b>",
      running: true,
      added_at: "2026-10-20T09:00:00Z",
    },
  ],
  github: [
    {
      circle: "Hike <Club>",
      channel: "dev",
      name: "app<repo>",
      events: ["push", "issues"],
      running: false,
      paused_reason: "too_many_failures",
      added_at: "2026-10-21T09:00:00Z",
    },
  ],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("feeds and GitHub connections add a page and a JSON file", () => {
  const files = texts({ ...base, integrations });
  const json = JSON.parse(files["data/integrations.json"]);
  assertEquals(json.feeds.length, 1);
  assertEquals(json.github[0].events, ["push", "issues"]);
  const html = files["pages/integrations.html"];
  assertStringIncludes(html, "https://blog.example.com/feed.xml");
  assertStringIncludes(html, "push, issues");
  assertStringIncludes(html, "paused (too many failures)");
  assertStringIncludes(files["index.html"], "pages/integrations.html");
  assertStringIncludes(files["index.html"], "1 feed · 1 GitHub");
  assertStringIncludes(files["README.txt"], "data/integrations.json");
});

Deno.test("what people wrote is escaped, and no secret is there", () => {
  const files = texts({ ...base, integrations });
  const html = files["pages/integrations.html"];
  assertFalse(html.includes("Hike <Club>"));
  assertFalse(html.includes("app<repo>"));
  assertStringIncludes(html, "app&lt;repo&gt;");
  assertFalse(/secret|token/i.test(files["data/integrations.json"]));
});

Deno.test("nothing is added when it could not be read, or in older callers", () => {
  for (const value of [undefined, null]) {
    const files = texts({ ...base, integrations: value });
    assertFalse("data/integrations.json" in files);
    assertFalse("pages/integrations.html" in files);
  }
});

Deno.test("none still gives the files, with empty sections", () => {
  const files = texts({ ...base, integrations: { feeds: [], github: [] } });
  assert("data/integrations.json" in files);
  assertStringIncludes(files["pages/integrations.html"], "None.");
});
