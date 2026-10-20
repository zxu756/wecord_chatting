// Moments 2.0 (B2): pins, reminders and the pictures on comments, in the
// archive.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  buildExportFiles,
  type ExportData,
  type ExportMoments,
  momentsMoreFilesToSign,
} from "./export_builder.ts";

const moments: ExportMoments = {
  settings: null,
  friendPrefs: [],
  posts: [
    {
      id: "p-1",
      body: "North lot <b>sunrise</b>",
      kind: "photos",
      visibility: "friends",
      created_at: "2026-10-20T08:00:00Z",
      pinned_at: "2026-10-21T08:00:00Z",
      mentioned_user_ids: ["u-2", "u-3"],
      photos: [
        {
          path: "u-1/p-1-0.jpg",
          thumb: "u-1/p-1-0-t.jpg",
          alt: "A dog asleep <on> a sofa",
        },
        { path: "u-1/p-1-1.jpg", thumb: "u-1/p-1-1-t.jpg" },
      ],
      audience_friends: [],
      audience_tags: [],
    },
  ],
  comments: [
    {
      id: "c-1",
      post_id: "p-9",
      post_author: { id: "u-2", username: "bob", display_name: "Bob" },
      reply_to: null,
      text: "",
      created_at: "2026-10-20T09:00:00Z",
    },
  ],
  likes: [],
  tags: [],
  stars: [],
};

const more = {
  pinned: [{ post_id: "p-1", pinned_at: "2026-10-21T08:00:00Z" }],
  reminded: [
    {
      post_id: "p-1",
      created_at: "2026-10-20T08:00:00Z",
      people: [
        { id: "u-2", username: "bob", display_name: "Bob" },
        { id: "u-3", username: "cy", display_name: "Cy" },
      ],
    },
  ],
  reminded_by: [
    {
      post_id: "p-7",
      from: { id: "u-2", username: "bob", display_name: "Bob" },
      created_at: "2026-10-19T08:00:00Z",
    },
  ],
  comment_pictures: [
    {
      comment_id: "c-1",
      post_id: "p-9",
      bucket: "moments",
      path: "u-1/c-c-1.png",
      description: "a cat <waving>",
      created_at: "2026-10-20T09:00:00Z",
    },
    {
      comment_id: "c-2",
      post_id: "p-9",
      bucket: "moments",
      path: "u-1/c-c-2.gif",
      description: null,
      created_at: "2026-10-20T09:05:00Z",
    },
  ],
};

const base: ExportData = {
  generatedAt: "2026-10-26T14:03:00.000Z",
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
  moments,
  extras: null,
  momentsMore: more,
  files: [],
  attachmentLinks: {
    "moments/u-1/c-c-1.png": "https://files.test/c1?sig=1",
  },
  linksExpireAt: "2026-11-02T14:03:00.000Z",
  skipped: [],
};

function fileOf(data: ExportData, path: string): string {
  const found = buildExportFiles(data).find((file) => file.path === path);
  assert(found, `${path} is missing`);
  return found.content;
}

Deno.test("the pictures on my comments are linked, never put in the ZIP", () => {
  assertEquals(momentsMoreFilesToSign(more), [
    { bucket: "moments", path: "u-1/c-c-1.png" },
    { bucket: "moments", path: "u-1/c-c-2.gif" },
  ]);
  assertEquals(momentsMoreFilesToSign(null), []);
  assertEquals(momentsMoreFilesToSign({ comment_pictures: [{ path: 3 }] }), []);
});

Deno.test("data/moments_more.json carries pins, reminders and pictures", () => {
  const json = JSON.parse(fileOf(base, "data/moments_more.json")) as Record<
    string,
    unknown
  >;
  assertEquals((json["pinned_posts"] as unknown[]).length, 1);
  assertEquals((json["reminded_by_you"] as unknown[]).length, 1);
  assertEquals((json["reminded_you"] as unknown[]).length, 1);
  const pictures = json["comment_pictures"] as Record<string, unknown>[];
  assertEquals(pictures.length, 2);
  assertEquals(pictures[0]["description"], "a cat <waving>");
  const file = pictures[0]["file"] as Record<string, unknown>;
  assertEquals(file["download_url"], "https://files.test/c1?sig=1");
  // A reminder you got names the person and when, never their words.
  assert(!("body" in (json["reminded_you"] as Record<string, unknown>[])[0]));
});

Deno.test("no file is written when the Moments extras could not be read", () => {
  const files = buildExportFiles({ ...base, momentsMore: null });
  assert(!files.some((file) => file.path === "data/moments_more.json"));
  const withoutField = { ...base };
  delete withoutField.momentsMore;
  assert(
    !buildExportFiles(withoutField).some((file) =>
      file.path === "data/moments_more.json"
    ),
  );
});

Deno.test("the Moments page shows pins, descriptions, reminders and pictures", () => {
  const page = fileOf(base, "pages/moments.html");
  assertStringIncludes(page, "Pinned");
  // Escaped, never raw.
  assertStringIncludes(page, "Description: A dog asleep &lt;on&gt; a sofa");
  assertStringIncludes(page, "Reminded to read: Bob, Cy");
  assertStringIncludes(page, "Reminders you got");
  assertStringIncludes(page, "Bob reminded you to read a post");
  assertStringIncludes(page, "https://files.test/c1?sig=1");
  assert(!page.includes("<on>"));
});

Deno.test("the README names the new file", () => {
  const readme = fileOf(base, "README.txt");
  assertStringIncludes(readme, "data/moments_more.json");
});
