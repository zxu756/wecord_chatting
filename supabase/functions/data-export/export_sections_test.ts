// Moments, friend tags, chains, notes, lists, saved messages, reminders,
// scheduled messages and wallpapers in the archive.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { unzipSync } from "npm:fflate@0.8.2";
import {
  buildExportFiles,
  buildExportZip,
  type ExportData,
  type ExportExtras,
  exportFileZipPath,
  type ExportMoments,
  ownedFiles,
} from "./export_builder.ts";

const person = (id: string, name: string) => ({
  id,
  username: name.toLowerCase(),
  display_name: name,
});

const base: ExportData = {
  generatedAt: "2026-10-17T14:03:00.000Z",
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
  conversations: [
    {
      id: "c-1",
      kind: "direct",
      name: "Bart",
      circleName: null,
      joinedAt: null,
      role: "member",
      createdAt: null,
    },
    {
      id: "c-2",
      kind: "group",
      name: "Climbing crew",
      circleName: null,
      joinedAt: null,
      role: "owner",
      createdAt: null,
    },
  ],
  messages: [],
  circles: [],
  moments: null,
  extras: null,
  files: [],
  attachmentLinks: {},
  linksExpireAt: "2026-10-24T14:03:00.000Z",
  skipped: [],
};

const moments: ExportMoments = {
  settings: { visible_range: "one_month", cover_path: "u-1/cover-1.jpg" },
  friendPrefs: [{
    friend: person("u-2", "Bart"),
    hide_mine: true,
    hide_theirs: false,
  }],
  posts: [{
    id: "p-1",
    body: "Sunset <b>walk</b>",
    kind: "photos",
    created_at: "2026-10-05T18:00:00.000Z",
    location: "Rome",
    visibility: "only",
    audience_friends: [person("u-2", "Bart")],
    audience_tags: [{ id: "t-1", name: "Family" }],
    photos: [
      { path: "u-1/p-1-0.jpg", w: 10, h: 10 },
      { path: "u-1/p-1-1.jpg", w: 10, h: 10 },
    ],
    // A column of a later migration: it must flow through.
    video: { path: "u-1/p-1-v.mp4", poster: "u-1/p-1-vp.jpg", size: 2048 },
  }, {
    id: "p-2",
    body: "A link",
    kind: "link",
    created_at: "2026-10-04T18:00:00.000Z",
    link_url: "https://example.com/?a=1&b=2",
    link_title: "Example",
    visibility: "friends",
    photos: [],
    audience_friends: [],
    audience_tags: [],
  }],
  comments: [{
    id: "cm-1",
    post_id: "p-9",
    post_author: person("u-2", "Bart"),
    post_text: null,
    reply_to: null,
    text: "Nice one",
    created_at: "2026-10-06T08:00:00.000Z",
  }, {
    id: "cm-2",
    post_id: "p-1",
    post_author: person("u-1", "Ada"),
    post_text: "Sunset <b>walk</b>",
    reply_to: person("u-2", "Bart"),
    text: "thanks!",
    created_at: "2026-10-06T09:00:00.000Z",
  }],
  likes: [{ post_id: "p-9", created_at: "2026-10-06T07:00:00.000Z" }],
  tags: [{ id: "t-1", name: "Family", friends: [person("u-2", "Bart")] }],
  stars: [{
    friend: person("u-2", "Bart"),
    starred_at: "2026-09-01T00:00:00.000Z",
  }],
};

const extras: ExportExtras = {
  chains: [{
    id: "ch-1",
    conversation_id: "c-2",
    title: "Friday dinner",
    created_by_me: false,
    creator: person("u-2", "Bart"),
    created_at: "2026-10-02T10:00:00.000Z",
    my_entry: { text: "me +1", joined_at: "2026-10-02T11:00:00.000Z" },
  }],
  notes: [{
    id: "n-1",
    conversation_id: "c-gone",
    title: "Packing",
    icon: "📝",
    created_by_me: true,
    updated_at: "2026-10-03T10:00:00.000Z",
    blocks: [{ kind: "paragraph", text: "tent <script>x</script>" }],
  }],
  taskLists: [{
    id: "l-1",
    conversation_id: "c-1",
    title: "Trip",
    icon: "✅",
    created_by_me: false,
    created_at: "2026-10-03T10:00:00.000Z",
    items: [{
      title: "Book hut",
      completed_at: "2026-10-04T00:00:00.000Z",
      assigned_to: [person("u-2", "Bart")],
    }],
  }],
  savedMessages: [
    {
      id: "s-1",
      conversation_id: "c-1",
      saved_at: "2026-10-05T00:00:00.000Z",
      from_you: true,
      text: "my own words",
    },
    {
      id: "s-2",
      conversation_id: "c-1",
      saved_at: "2026-10-05T01:00:00.000Z",
      from_you: false,
      text: null,
    },
  ],
  reminders: [{
    id: "r-1",
    conversation_id: "c-1",
    remind_at: "2026-11-01T00:00:00.000Z",
    from_you: false,
    text: null,
  }],
  scheduledMessages: [{
    id: "sc-1",
    conversation_id: "c-2",
    text: "happy birthday",
    send_at: "2026-12-01T00:00:00.000Z",
    status: "pending",
  }],
  wallpapers: [
    {
      conversation_id: null,
      kind: "photo",
      photo_path: "u-1/w-1.jpg",
      dim: 0.4,
      blur: false,
    },
    {
      conversation_id: "c-1",
      kind: "preset",
      preset_id: "aurora",
      dim: 0.2,
      blur: true,
    },
  ],
};

const full: ExportData = {
  ...base,
  moments,
  extras,
  files: [
    {
      key: "moments/u-1/cover-1.jpg",
      zipPath: "files/moments/cover-1.jpg",
      bytes: new Uint8Array([1, 2, 3]),
    },
    {
      key: "moments/u-1/p-1-0.jpg",
      zipPath: "files/moments/p-1-0.jpg",
      bytes: new Uint8Array([4, 5]),
    },
  ],
  attachmentLinks: {
    "moments/u-1/p-1-v.mp4": "https://files.example/video?t=1&u=2",
  },
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("the new sections add pages, JSON files and the files themselves", () => {
  const unzipped = unzipSync(buildExportZip(full));
  const names = Object.keys(unzipped);
  for (
    const expected of [
      "pages/moments.html",
      "pages/chains.html",
      "pages/notes.html",
      "pages/saved.html",
      "pages/wallpapers.html",
      "data/moments.json",
      "data/friend_tags.json",
      "data/chains.json",
      "data/notes.json",
      "data/task_lists.json",
      "data/saved_messages.json",
      "data/reminders.json",
      "data/scheduled_messages.json",
      "data/wallpapers.json",
      "files/moments/cover-1.jpg",
      "files/moments/p-1-0.jpg",
    ]
  ) {
    assert(names.includes(expected), `missing ${expected}`);
  }
  assertEquals([...unzipped["files/moments/p-1-0.jpg"]], [4, 5]);
  assert(names.includes("data/messages.json") && names.includes("index.html"));
});

Deno.test("a part that could not be read adds nothing to the archive", () => {
  const names = Object.keys(unzipSync(buildExportZip({
    ...full,
    moments: null,
    files: [],
    skipped: ["moments"],
  })));
  assert(!names.some((n) => n.includes("moments") || n.startsWith("files/")));
  assert(names.includes("pages/chains.html"));
  assertStringIncludes(
    texts({ ...full, moments: null, skipped: ["moments"] })["index.html"],
    "moments could not be read",
  );
  assertEquals(
    Object.keys(unzipSync(buildExportZip(base))).filter((n) =>
      n.startsWith("pages/") || n.startsWith("files/")
    ),
    [],
  );
});

Deno.test("moments.json keeps every column and resolves my files", () => {
  const files = texts(full);
  const json = JSON.parse(files["data/moments.json"]);
  assertEquals(json.settings.visible_range, "one_month");
  assertEquals(json.settings.cover.file, "files/moments/cover-1.jpg");
  const post = json.posts[0];
  assertEquals(post.location, "Rome");
  assertEquals(post.audience_friends[0].display_name, "Bart");
  assertEquals(post.audience_tags[0].name, "Family");
  assertEquals(post.photos[0].file, "files/moments/p-1-0.jpg");
  // Not in the ZIP and not linked: nothing to point at.
  assertEquals(post.photos[1].file, null);
  assertEquals(post.photos[1].download_url, null);
  assertEquals(post.video.size, 2048);
  assertEquals(post.video.download_url, "https://files.example/video?t=1&u=2");
  assertEquals(post.video.download_url_expires_at, full.linksExpireAt);
  assertEquals(json.comments_you_wrote.length, 2);
  assertEquals(json.posts_you_liked[0].post_id, "p-9");
  assertEquals(json.friend_choices[0].hide_mine, true);
  const tags = JSON.parse(files["data/friend_tags.json"]);
  assertEquals(tags.tags[0].friends[0].username, "bart");
  assertEquals(tags.starred_friends.length, 1);
  const wallpapers = JSON.parse(files["data/wallpapers.json"]);
  assertEquals(wallpapers[0].photo.download_url, null);
  assertEquals(wallpapers[1].preset_id, "aurora");
});

Deno.test("a post without a video column has no video in the JSON", () => {
  const post = JSON.parse(texts(full)["data/moments.json"]).posts[1];
  assertEquals("video" in post, false);
});

Deno.test("section pages are escaped, link files and say what they leave out", () => {
  const files = texts(full);
  const index = files["index.html"];
  assertStringIncludes(index, 'href="pages/moments.html"');
  assertStringIncludes(index, "2 posts · 2 comments · 1 like");
  assertStringIncludes(index, 'href="pages/chains.html"');

  const page = files["pages/moments.html"];
  assert(!page.includes("<b>walk</b>"));
  assertStringIncludes(page, "Sunset &lt;b&gt;walk&lt;/b&gt;");
  assertStringIncludes(page, 'src="../files/moments/p-1-0.jpg"');
  assertStringIncludes(page, 'href="https://files.example/video?t=1&amp;u=2"');
  assertStringIncludes(page, "Only some friends");
  assertStringIncludes(page, "On a post by Bart");
  assertStringIncludes(page, "replying to Bart");
  assertStringIncludes(page, "Last month");
  assertStringIncludes(page, 'href="https://example.com/?a=1&amp;b=2"');

  const chains = files["pages/chains.html"];
  assertStringIncludes(chains, "Friday dinner");
  assertStringIncludes(chains, "started by Bart");
  assertStringIncludes(chains, "me +1");
  assertStringIncludes(chains, "in Climbing crew");

  const notes = files["pages/notes.html"];
  assertStringIncludes(notes, "tent &lt;script&gt;x&lt;/script&gt;");
  assertStringIncludes(notes, "A conversation you left");
  assertStringIncludes(notes, "☑ Book hut");
  assertStringIncludes(notes, "for Bart");

  const saved = files["pages/saved.html"];
  assertStringIncludes(saved, "my own words");
  assertStringIncludes(saved, "A message from someone else (not included).");
  assertStringIncludes(
    saved,
    "About a message from someone else (not included).",
  );
  assertStringIncludes(saved, "happy birthday");

  const wallpapers = files["pages/wallpapers.html"];
  assertStringIncludes(wallpapers, "All chats (default)");
  assertStringIncludes(wallpapers, "Preset “aurora”");
});

Deno.test("only files in my own folder are ever fetched", () => {
  const evil: ExportMoments = {
    ...moments,
    settings: { cover_path: "u-2/cover-9.jpg" },
    posts: [{
      photos: [
        { path: "u-2/p-9-0.jpg" },
        { path: "u-1/../u-2/x.jpg" },
        { path: "u-1/ok.jpg" },
      ],
      video: { path: "u-1/v.mp4", poster: "u-3/poster.jpg", size: 99 },
    }],
  };
  const wallpapers: ExportExtras = {
    ...extras,
    wallpapers: [{ photo_path: "u-2/w.jpg" }, { photo_path: "u-1/w.jpg" }],
  };
  assertEquals(
    ownedFiles("u-1", evil, wallpapers).map((f) =>
      `${f.bucket}/${f.path}:${f.size}`
    ),
    [
      "wallpapers/u-1/w.jpg:null",
      "moments/u-1/ok.jpg:null",
      "moments/u-1/v.mp4:99",
    ],
  );
  assertEquals(ownedFiles("u-1", null, null), []);
  assertEquals(
    exportFileZipPath("moments", "u-1/p-1-0.jpg"),
    "files/moments/p-1-0.jpg",
  );
  assertEquals(
    exportFileZipPath("wallpapers", "u-1/a b.jpg"),
    "files/wallpapers/a_b.jpg",
  );
});
