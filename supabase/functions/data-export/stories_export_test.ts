// The Daily (B1): my dailies, close friends and reports in the archive.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  buildExportFiles,
  type ExportData,
  storyFilesToSign,
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

const stories = {
  stories: [
    {
      id: "s-1",
      media_kind: "video",
      caption: "Sunrise <b>walk</b>",
      audience: "close",
      created_at: "2026-10-24T08:00:00Z",
      expires_at: "2026-10-25T08:00:00Z",
      viewer_count: 3,
      width: 720,
      height: 1280,
      duration_ms: 9000,
      bucket: "stories",
      path: "u-1/s-1-v.mp4",
      poster_path: "u-1/s-1.jpg",
      thumb_path: "u-1/s-1-t.jpg",
    },
    {
      id: "s-2",
      media_kind: "photo",
      caption: "",
      audience: "friends",
      created_at: "2026-10-24T09:00:00Z",
      expires_at: "2026-10-25T09:00:00Z",
      viewer_count: 1,
      bucket: "stories",
      path: "u-1/s-2.jpg",
      poster_path: null,
      thumb_path: "u-1/s-2-t.jpg",
    },
  ],
  close_friends: [{ user_id: "u-2", name: "Bart", username: "bart" }],
  reports: [{
    reason: "spam",
    details: "ads",
    status: "open",
    created_at: "2026-10-22T08:00:00Z",
    handled_at: null,
  }],
};

const links = {
  "stories/u-1/s-1-v.mp4": "https://files.example/s1v?t=1",
  "stories/u-1/s-1.jpg": "https://files.example/s1?t=1",
  "stories/u-1/s-1-t.jpg": "https://files.example/s1t?t=1",
  "stories/u-1/s-2.jpg": "https://files.example/s2?t=1",
  "stories/u-1/s-2-t.jpg": "https://files.example/s2t?t=1",
};

Deno.test("every file of every daily is linked, once", () => {
  const files = storyFilesToSign(stories);
  assertEquals(files.length, 5);
  assert(files.every((file) => file.bucket === "stories"));
  assertEquals(storyFilesToSign(null), []);
  assertEquals(storyFilesToSign({ stories: [] }), []);
});

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("the archive has the dailies with links, and not who viewed", () => {
  const files = texts({ ...base, stories, attachmentLinks: links });
  const value = JSON.parse(files["data/stories.json"]);
  assertEquals(value.dailies.length, 2);
  const video = value.dailies[0];
  assertEquals(video.audience, "close");
  assertEquals(video.viewer_count, 3);
  assertEquals(video.file.download_url, "https://files.example/s1v?t=1");
  assert(!("path" in video) && !("bucket" in video));
  assertEquals(value.dailies[1].poster, null);
  assertEquals(value.close_friends.length, 1);
  assertEquals(value.reports_you_filed.length, 1);
  assert(!files["data/stories.json"].includes("viewer_id"));
});

Deno.test("the page escapes the caption and says what each audience was", () => {
  const files = texts({ ...base, stories, attachmentLinks: links });
  const html = files["pages/stories.html"];
  assertStringIncludes(html, "Sunrise &lt;b&gt;walk&lt;/b&gt;");
  assert(!html.includes("<b>walk</b>"));
  assertStringIncludes(html, "Close friends");
  assertStringIncludes(html, "3 viewers");
  assertStringIncludes(html, "1 viewer,");
  assertStringIncludes(html, "Bart");
  assertStringIncludes(html, "https://files.example/s1v?t=1");
  assertStringIncludes(files["index.html"], 'href="pages/stories.html"');
  assertStringIncludes(files["README.txt"], "data/stories.json");
});

Deno.test("an export without the part leaves it out", () => {
  const files = texts({ ...base, stories: null });
  assert(!("data/stories.json" in files));
  assert(!("pages/stories.html" in files));
});
