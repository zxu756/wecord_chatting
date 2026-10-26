// Group space (B6): the albums and folders I made and what I added to them, in
// the archive - names escaped, with links to the files, never what other
// people put in.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  buildExportFiles,
  type ExportData,
  groupSpaceFilesToSign,
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

const groupSpace = {
  albums: [
    {
      name: "Trip <2026>",
      group: "Hike & crew",
      created_at: "2026-10-20T01:00:00Z",
    },
  ],
  items: [
    {
      album: "Trip <2026>",
      group: "Hike & crew",
      kind: "image",
      name: "hut.jpg",
      bucket: "chat-images",
      path: "conv-1/space/a1.jpg",
      size: 1200,
      description: "A <hut> in the snow",
      added_at: "2026-10-20T01:05:00Z",
    },
  ],
  folders: [
    { name: "Handouts", group: null, created_at: "2026-10-21T01:00:00Z" },
  ],
  files: [
    {
      folder: "Handouts",
      kind: "file",
      name: "plan.pdf",
      bucket: "chat-files",
      path: "conv-1/space/f1.pdf",
      size: 90000,
      added_at: "2026-10-21T01:05:00Z",
    },
  ],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("the group space adds a page and a JSON file", () => {
  const files = texts({
    ...base,
    groupSpace,
    attachmentLinks: {
      "chat-images/conv-1/space/a1.jpg": "https://files.example.com/a1.jpg",
      "chat-files/conv-1/space/f1.pdf": "https://files.example.com/f1.pdf",
    },
  });
  assert("pages/group_space.html" in files);
  assert("data/group_space.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/group_space.html"');
  assertStringIncludes(files["index.html"], "1 albums · 1 folders");
  assertStringIncludes(files["README.txt"], "data/group_space.json");

  const page = files["pages/group_space.html"];
  assertStringIncludes(page, "Trip &lt;2026&gt;");
  assertStringIncludes(page, "Hike &amp; crew");
  assertStringIncludes(page, "A &lt;hut&gt; in the snow");
  assertStringIncludes(page, "https://files.example.com/a1.jpg");
  assertStringIncludes(page, "https://files.example.com/f1.pdf");
  assert(!page.includes("<2026>"));
  assert(!page.includes("<hut>"));

  const json = JSON.parse(files["data/group_space.json"]);
  assertEquals(json.albums.length, 1);
  assertEquals(
    json.items[0].file.download_url,
    "https://files.example.com/a1.jpg",
  );
  assertEquals(json.items[0].description, "A <hut> in the snow");
  assertEquals(json.files[0].name, "plan.pdf");
  // The storage path is in the file reference, not repeated beside it.
  assert(!("path" in json.items[0]));
});

Deno.test("an export without the part has no page; an empty one says so", () => {
  const without = texts(base);
  assert(!("pages/group_space.html" in without));
  assert(!("data/group_space.json" in without));

  const empty = texts({
    ...base,
    groupSpace: { albums: [], items: [], folders: [], files: [] },
  });
  assertStringIncludes(empty["pages/group_space.html"], "None.");
  assertStringIncludes(empty["index.html"], "0 albums · 0 folders");
});

Deno.test("my pictures and files are the files to sign", () => {
  assertEquals(groupSpaceFilesToSign(groupSpace), [
    { bucket: "chat-images", path: "conv-1/space/a1.jpg" },
    { bucket: "chat-files", path: "conv-1/space/f1.pdf" },
  ]);
  assertEquals(groupSpaceFilesToSign(null), []);
  assertEquals(
    groupSpaceFilesToSign({
      items: [{ bucket: "chat-images" }],
      files: [{ path: "x" }],
    }),
    [],
  );
});
