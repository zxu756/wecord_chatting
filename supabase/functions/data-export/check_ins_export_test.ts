// Group check-in (D3) and chat tabs (D8): my days, my runs, the check-ins I
// made and the tabs I added are in the archive - names escaped, nobody else's
// notes.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  buildExportFiles,
  checkInFilesToSign,
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

const checkIns = {
  check_ins: [
    {
      check_in: "Read <20> pages",
      chat: "Book <club>",
      day: "2026-10-27",
      note: "chapter 3",
      checked_in_at: "2026-10-27T09:10:00Z",
      photo: { bucket: "chat-images", path: "conv-1/check-ins/b-1/p1.jpg" },
    },
    {
      check_in: "Read <20> pages",
      chat: null,
      day: "2026-10-26",
      note: "",
      checked_in_at: "2026-10-26T09:10:00Z",
      photo: null,
    },
  ],
  streaks: [{
    check_in: "Read <20> pages",
    current_streak: 7,
    best_streak: 12,
    total_days: 40,
    last_day: "2026-10-27",
  }],
  boards_made: [{
    title: "Run 3 km",
    description: "Every <morning>",
    time_zone: "Pacific/Auckland",
    reminder_minute: 480,
    last_day: null,
    closed: true,
    created_at: "2026-10-01T00:00:00Z",
  }],
};

const groupTabs = {
  tabs_added: [{
    kind: "link",
    title: "Rules <doc>",
    link: "https://example.com/rules?a=1&b=2",
    chat: "Book <club>",
    added_at: "2026-10-20T00:00:00Z",
  }],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("check-ins add a page and a JSON file", () => {
  const files = texts({
    ...base,
    checkIns,
    attachmentLinks: {
      "chat-images/conv-1/check-ins/b-1/p1.jpg":
        "https://files.example.com/p1.jpg",
    },
  });
  assert("pages/check_ins.html" in files);
  assert("data/check_ins.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/check_ins.html"');
  assertStringIncludes(files["index.html"], "2 days · 1 made");
  assertStringIncludes(files["README.txt"], "data/check_ins.json");

  const page = files["pages/check_ins.html"];
  assertStringIncludes(page, "Read &lt;20&gt; pages");
  assertStringIncludes(page, "Book &lt;club&gt;");
  assertStringIncludes(page, "chapter 3");
  assertStringIncludes(page, "streak 7 days, best 12, 40 days in all");
  assertStringIncludes(page, "https://files.example.com/p1.jpg");
  assertStringIncludes(page, "Every &lt;morning&gt;");
  assert(!page.includes("<20>"));
  assert(!page.includes("<club>"));
  assert(!page.includes("<morning>"));

  const json = JSON.parse(files["data/check_ins.json"]);
  assertEquals(json.check_ins.length, 2);
  assertEquals(
    json.check_ins[0].photo.download_url,
    "https://files.example.com/p1.jpg",
  );
  assertEquals(json.check_ins[1].photo, null);
  assertEquals(json.streaks[0].best_streak, 12);
  assertEquals(json.boards_made[0].time_zone, "Pacific/Auckland");
});

Deno.test("chat tabs add a page and a JSON file", () => {
  const files = texts({ ...base, groupTabs });
  assert("pages/group_tabs.html" in files);
  assert("data/group_tabs.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/group_tabs.html"');
  assertStringIncludes(files["index.html"], "1 tab");
  const page = files["pages/group_tabs.html"];
  assertStringIncludes(page, "Rules &lt;doc&gt;");
  assertStringIncludes(page, "https://example.com/rules?a=1&amp;b=2");
  assert(!page.includes("<doc>"));
  assertEquals(
    JSON.parse(files["data/group_tabs.json"]).tabs_added[0].kind,
    "link",
  );
});

Deno.test("an export without the parts has no page; an empty one says so", () => {
  const without = texts(base);
  assert(!("pages/check_ins.html" in without));
  assert(!("data/check_ins.json" in without));
  assert(!("pages/group_tabs.html" in without));

  const empty = texts({
    ...base,
    checkIns: { check_ins: [], streaks: [], boards_made: [] },
    groupTabs: { tabs_added: [] },
  });
  assertStringIncludes(empty["pages/check_ins.html"], "None.");
  assertStringIncludes(empty["index.html"], "0 days · 0 made");
  assertStringIncludes(empty["pages/group_tabs.html"], "None.");
});

Deno.test("the pictures of my check-ins are the files to sign", () => {
  assertEquals(checkInFilesToSign(checkIns), [
    { bucket: "chat-images", path: "conv-1/check-ins/b-1/p1.jpg" },
  ]);
  assertEquals(checkInFilesToSign(null), []);
  assertEquals(
    checkInFilesToSign({
      check_ins: [{ photo: { bucket: "chat-images" } }, { photo: null }, {}],
    }),
    [],
  );
});
