// Favorites 2.0 (B3): the folders and what I kept, in the archive.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  buildExportFiles,
  type ExportData,
  favoriteFilesToSign,
} from "./export_builder.ts";

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

const favorites = {
  folders: [{
    id: "f-1",
    name: "Trips <3",
    created_at: "2026-10-20T08:00:00Z",
  }],
  items: [
    {
      id: "i-1",
      kind: "note",
      title: "Packing <list>",
      body: "tent, stove",
      folder: "Trips <3",
      tags: ["trip", "gear"],
      remark: "before June",
      saved_at: "2026-10-24T09:00:00Z",
      images: [
        { bucket: "saved-notes", path: "u-1/i-1-0.jpg" },
        { bucket: "saved-notes", path: "u-1/i-1-1.jpg" },
      ],
    },
    {
      id: "i-2",
      kind: "link",
      title: "Trail map",
      url: "https://example.com/trails",
      tags: [],
      saved_at: "2026-10-24T08:00:00Z",
    },
    {
      id: "i-3",
      kind: "message",
      folder: "Trips <3",
      tags: [],
      from_you: false,
      saved_at: "2026-10-23T08:00:00Z",
      done_at: "2026-10-24T08:00:00Z",
    },
    {
      id: "i-4",
      kind: "moment",
      tags: [],
      from_you: true,
      text: "My <b>own</b> Moment",
      saved_at: "2026-10-22T08:00:00Z",
    },
  ],
};

const links = {
  "saved-notes/u-1/i-1-0.jpg": "https://files.example/n0?t=1",
  "saved-notes/u-1/i-1-1.jpg": "https://files.example/n1?t=1",
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("every picture of every note is linked, once", () => {
  const files = favoriteFilesToSign(favorites);
  assertEquals(files.length, 2);
  assert(files.every((file) => file.bucket === "saved-notes"));
  assertEquals(favoriteFilesToSign(null), []);
  assertEquals(favoriteFilesToSign({ items: [] }), []);
  assertEquals(
    favoriteFilesToSign({
      items: [favorites.items[0], favorites.items[0]],
    }).length,
    2,
  );
});

Deno.test("the archive has the folders and the items with links to pictures", () => {
  const files = texts({ ...base, favorites, attachmentLinks: links });
  const value = JSON.parse(files["data/favorites.json"]);
  assertEquals(value.folders.length, 1);
  assertEquals(value.items.length, 4);
  const note = value.items[0];
  assertEquals(note.images.length, 2);
  assertEquals(
    note.images[0].file.download_url,
    "https://files.example/n0?t=1",
  );
  assert(!("path" in note.images[0]) && !("bucket" in note.images[0]));
  assertEquals(note.folder, "Trips <3");
  assertEquals(value.items[1].url, "https://example.com/trails");
  assert(!("images" in value.items[1]));
});

Deno.test("the page escapes the words and does not copy other people's", () => {
  const files = texts({ ...base, favorites, attachmentLinks: links });
  const html = files["pages/favorites.html"];
  assertStringIncludes(html, "Packing &lt;list&gt;");
  assert(!html.includes("<list>"));
  assertStringIncludes(html, "Trips &lt;3");
  assertStringIncludes(html, "before June");
  assertStringIncludes(html, "https://files.example/n0?t=1");
  assertStringIncludes(html, 'href="https://example.com/trails"');
  assertStringIncludes(html, "Written by someone else: not included.");
  assertStringIncludes(html, "My &lt;b&gt;own&lt;/b&gt; Moment");
  assertStringIncludes(html, "done");
  assertStringIncludes(files["index.html"], 'href="pages/favorites.html"');
  assertStringIncludes(files["README.txt"], "data/favorites.json");
});

Deno.test("an export without the part leaves it out", () => {
  const files = texts({ ...base, favorites: null });
  assert(!("data/favorites.json" in files));
  assert(!("pages/favorites.html" in files));
});

Deno.test("nothing kept says so", () => {
  const files = texts({ ...base, favorites: { folders: [], items: [] } });
  assertStringIncludes(files["pages/favorites.html"], "Nothing kept.");
  assertStringIncludes(files["pages/favorites.html"], "No folders.");
});
