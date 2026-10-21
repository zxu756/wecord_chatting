// Picture posts and Q&A (C9): my media posts (with a link for the picture and
// the description I wrote), my questions and the answers of mine that were
// accepted, in the archive - names escaped, nobody else's words.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  buildExportFiles,
  channelPostFilesToSign,
  type ExportData,
} from "./export_builder.ts";

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

const channelPosts = {
  media_posts: [
    {
      circle_id: "c-1",
      circle_name: "Pixel <Club>",
      channel_name: "photos",
      title: "Sunset at the pier",
      posted_at: "2026-10-27T09:00:00Z",
      picture: {
        bucket: "chat-images",
        path: "conv-1/kite.png",
        description: "A red kite <over> the pier",
      },
    },
  ],
  questions: [
    {
      circle_id: "c-1",
      circle_name: "Pixel <Club>",
      channel_name: "help",
      title: "How do I focus?",
      asked_at: "2026-10-26T09:00:00Z",
      solved: true,
      solved_at: "2026-10-26T10:00:00Z",
      answer_accepted: true,
      solved_by_you: true,
    },
    {
      circle_id: "c-1",
      circle_name: "Pixel <Club>",
      channel_name: "help",
      title: "Open one",
      asked_at: "2026-10-25T09:00:00Z",
      solved: false,
      solved_at: null,
      answer_accepted: false,
      solved_by_you: false,
    },
  ],
  accepted_answers: [
    {
      circle_id: "c-2",
      circle_name: "Other",
      channel_name: "help",
      accepted_at: "2026-10-24T09:00:00Z",
    },
  ],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("picture posts and questions add a page and a JSON file", () => {
  const files = texts({
    ...base,
    channelPosts,
    attachmentLinks: {
      "chat-images/conv-1/kite.png": "https://files.example.com/kite.png",
    },
  });
  assert("pages/channel_posts.html" in files);
  assert("data/channel_posts.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/channel_posts.html"');
  assertStringIncludes(files["index.html"], "1 picture posts · 2 questions");
  assertStringIncludes(files["README.txt"], "data/channel_posts.json");

  const page = files["pages/channel_posts.html"];
  assertStringIncludes(page, "Sunset at the pier");
  assertStringIncludes(page, "Pixel &lt;Club&gt;");
  assertStringIncludes(page, "A red kite &lt;over&gt; the pier");
  assertStringIncludes(page, "https://files.example.com/kite.png");
  assertStringIncludes(page, "solved, answer accepted");
  assertStringIncludes(page, "marked by you");
  assertStringIncludes(page, "open");
  assertStringIncludes(page, "An answer of yours was accepted");
  assert(!page.includes("<Club>"));
  assert(!page.includes("<over>"));

  const json = JSON.parse(files["data/channel_posts.json"]);
  assertEquals(json.media_posts.length, 1);
  assertEquals(
    json.media_posts[0].picture.file.download_url,
    "https://files.example.com/kite.png",
  );
  assertEquals(
    json.media_posts[0].picture.description,
    "A red kite <over> the pier",
  );
  assertEquals(json.questions.length, 2);
  assertEquals(json.accepted_answers.length, 1);
  // Not the title of somebody else's question.
  assertEquals(Object.keys(json.accepted_answers[0]).includes("title"), false);
});

Deno.test("an export without the part has no page; an empty one says so", () => {
  const without = texts(base);
  assert(!("pages/channel_posts.html" in without));
  assert(!("data/channel_posts.json" in without));

  const empty = texts({
    ...base,
    channelPosts: { media_posts: [], questions: [], accepted_answers: [] },
  });
  assertStringIncludes(empty["pages/channel_posts.html"], "No picture posts.");
  assertStringIncludes(empty["pages/channel_posts.html"], "No questions.");
  assertStringIncludes(empty["index.html"], "0 picture posts · 0 questions");
});

Deno.test("the pictures of media posts are the files to sign", () => {
  assertEquals(channelPostFilesToSign(channelPosts), [
    { bucket: "chat-images", path: "conv-1/kite.png" },
  ]);
  assertEquals(channelPostFilesToSign(null), []);
  assertEquals(
    channelPostFilesToSign({
      media_posts: [{ title: "x", picture: null }, { picture: { path: 5 } }],
    }),
    [],
  );
});
