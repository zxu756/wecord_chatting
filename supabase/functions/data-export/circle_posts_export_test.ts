// Circle posts 2.0 (B8): the posts I wrote in circles in the archive - titles
// and text escaped, the topics, the featured mark, a link to the picture and
// never other people's posts.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  buildExportFiles,
  circlePostsFilesToSign,
  type ExportData,
} from "./export_builder.ts";

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

const circlePosts = {
  posts: [
    {
      circle: "Book <Club>",
      title: "Lake & hills",
      text: "A <b>trip</b> #hiking",
      tags: ["hiking", "lake"],
      featured: true,
      featured_at: "2026-10-28T09:00:00Z",
      written_at: "2026-10-27T10:00:00Z",
      bucket: "chat-media",
      path: "circle-1/p1.jpg",
      description: "A <lake>",
    },
    {
      title: "Plain",
      text: "No picture",
      tags: [],
      featured: false,
      written_at: "2026-10-26T10:00:00Z",
    },
  ],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("circle posts add a page and a JSON file", () => {
  const files = texts({
    ...base,
    circlePosts,
    attachmentLinks: {
      "chat-media/circle-1/p1.jpg": "https://files.example.com/p1.jpg",
    },
  });
  assert("pages/circle_posts.html" in files);
  assert("data/circle_posts.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/circle_posts.html"');
  assertStringIncludes(files["index.html"], "2 posts");
  assertStringIncludes(files["README.txt"], "data/circle_posts.json");

  const page = files["pages/circle_posts.html"];
  assertStringIncludes(page, "Book &lt;Club&gt;");
  assertStringIncludes(page, "Lake &amp; hills");
  assertStringIncludes(page, "A &lt;b&gt;trip&lt;/b&gt; #hiking");
  assertStringIncludes(page, "#hiking #lake");
  assertStringIncludes(page, "Featured");
  assertStringIncludes(page, "https://files.example.com/p1.jpg");
  assert(!page.includes("<Club>"));
  assert(!page.includes("<b>"));

  const json = JSON.parse(files["data/circle_posts.json"]);
  assertEquals(json.posts.length, 2);
  assertEquals(json.posts[0].tags, ["hiking", "lake"]);
  assertEquals(
    json.posts[0].file.download_url,
    "https://files.example.com/p1.jpg",
  );
  // The storage path is in the file reference, not repeated beside it.
  assert(!("path" in json.posts[0]));
  assert(!("file" in json.posts[1]));
});

Deno.test("an export without the part has no page; an empty one says so", () => {
  const without = texts(base);
  assert(!("pages/circle_posts.html" in without));
  assert(!("data/circle_posts.json" in without));

  const empty = texts({ ...base, circlePosts: { posts: [] } });
  assertStringIncludes(empty["pages/circle_posts.html"], "None.");
  assertStringIncludes(empty["index.html"], "0 posts");
});

Deno.test("the pictures of my posts are the files to sign", () => {
  assertEquals(circlePostsFilesToSign(circlePosts), [
    { bucket: "chat-media", path: "circle-1/p1.jpg" },
  ]);
  assertEquals(circlePostsFilesToSign(null), []);
  assertEquals(
    circlePostsFilesToSign({ posts: [{ bucket: "chat-media" }] }),
    [],
  );
});
