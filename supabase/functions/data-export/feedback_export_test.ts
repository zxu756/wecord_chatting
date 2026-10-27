// Feedback and help (K7): my own feedback and the replies in the archive.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  buildExportFiles,
  type ExportData,
  feedbackFilesToSign,
} from "./export_builder.ts";

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

const withShot = {
  id: "fb-1",
  message: "The send button <b>is</b> hidden",
  app_version: "1.4.0",
  platform: "web",
  status: "closed",
  created_at: "2026-10-20T08:00:00Z",
  replied_at: "2026-10-21T08:00:00Z",
  screenshot_bucket: "feedback-screenshots",
  screenshot_path: "u-1/s-1.jpg",
  replies: [{ body: "Fixed in 1.4.1", published_at: "2026-10-21T08:00:00Z" }],
};

const plain = {
  id: "fb-2",
  message: "Dark mode please",
  app_version: "1.4.0",
  platform: "ios",
  status: "open",
  created_at: "2026-10-22T08:00:00Z",
  replied_at: null,
  screenshot_bucket: null,
  screenshot_path: null,
  replies: [],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("feedback adds a page and a JSON file with the replies", () => {
  const files = texts({
    ...base,
    feedback: [withShot, plain],
    attachmentLinks: {
      "feedback-screenshots/u-1/s-1.jpg": "https://files.example/shot?t=1",
    },
  });
  assert("pages/feedback.html" in files);
  assert("data/feedback.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/feedback.html"');
  assertStringIncludes(files["README.txt"], "data/feedback.json");

  const page = files["pages/feedback.html"];
  // Text is escaped; the version and platform, the reply and the link show.
  assertStringIncludes(page, "The send button &lt;b&gt;is&lt;/b&gt; hidden");
  assert(!page.includes("<b>is</b>"));
  assertStringIncludes(page, "web 1.4.0");
  assertStringIncludes(page, "Fixed in 1.4.1");
  assertStringIncludes(page, "https://files.example/shot?t=1");
  assertStringIncludes(page, "Dark mode please");

  const json = JSON.parse(files["data/feedback.json"]);
  assertEquals(json.length, 2);
  assertEquals(json[0].replies[0].body, "Fixed in 1.4.1");
  assertEquals(
    json[0].screenshot.download_url,
    "https://files.example/shot?t=1",
  );
  assertEquals(json[1].screenshot, null);
  // The raw bucket and path are replaced by the link.
  assert(!("screenshot_path" in json[0]));
});

Deno.test("no feedback says so; an export without the part has no page", () => {
  const empty = texts({ ...base, feedback: [] });
  assertStringIncludes(empty["pages/feedback.html"], "No feedback.");
  const absent = texts(base);
  assert(!("pages/feedback.html" in absent));
  assert(!("data/feedback.json" in absent));
  const failed = texts({ ...base, feedback: null });
  assert(!("pages/feedback.html" in failed));
});

Deno.test("the screenshots I attached are linked, once", () => {
  assertEquals(feedbackFilesToSign([withShot, withShot, plain]), [
    { bucket: "feedback-screenshots", path: "u-1/s-1.jpg" },
  ]);
});
