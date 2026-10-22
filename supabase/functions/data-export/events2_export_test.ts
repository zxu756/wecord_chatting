// Events 2.0 (C10): what I signed up to (with my answers), waited for, checked
// in to, the pictures I added and the events I made, in the archive - names
// escaped, nobody else's answers.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  buildExportFiles,
  eventFilesToSign,
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

const events2 = {
  signed_up: [
    {
      kind: "circle",
      circle_name: "Hike <Club>",
      title: "Summit picnic",
      starts_at: "2026-11-01T01:00:00Z",
      cancelled: false,
      answer: "going",
      signed_up_at: "2026-10-27T09:00:00Z",
      answers: { size: "M" },
      checked_in_at: "2026-11-01T01:02:00Z",
      questions: [{ id: "size", label: "T-shirt size", type: "text" }],
    },
  ],
  waiting: [{
    kind: "chat",
    title: "Tiny <dinner>",
    starts_at: "2026-11-02T01:00:00Z",
    joined_at: "2026-10-27T10:00:00Z",
    answers: {},
  }],
  check_ins: [{
    kind: "circle",
    title: "Summit picnic",
    starts_at: "2026-11-01T01:00:00Z",
    checked_in_at: "2026-11-01T01:02:00Z",
  }],
  photos: [{
    kind: "circle",
    title: "Summit picnic",
    bucket: "chat-media",
    path: "c-1/events/p1.jpg",
    added_at: "2026-11-01T03:00:00Z",
  }],
  calls_made: [{
    title: "Thursday sync",
    starts_at: "2026-10-22T18:00:00Z",
    ends_at: "2026-10-22T19:00:00Z",
    cancelled: false,
    repeats: "weekly",
    link_works_until: "2026-10-22T20:00:00Z",
    link_turned_off: false,
  }],
  events_made: [{
    kind: "chat",
    title: "Saturday hike",
    starts_at: "2026-11-07T21:00:00Z",
    repeats: "weekly",
    time_zone: "Pacific/Auckland",
    capacity: 12,
    questions: [{ id: "q1", label: "Meals?", type: "text" }],
    cover: { bucket: "chat-images", path: "conv-1/events/cover.jpg" },
  }],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("events add a page and a JSON file", () => {
  const files = texts({
    ...base,
    events2,
    attachmentLinks: {
      "chat-media/c-1/events/p1.jpg": "https://files.example.com/p1.jpg",
      "chat-images/conv-1/events/cover.jpg":
        "https://files.example.com/cover.jpg",
    },
  });
  assert("pages/events.html" in files);
  assert("data/events.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/events.html"');
  assertStringIncludes(files["index.html"], "1 signed up · 1 made");
  assertStringIncludes(files["README.txt"], "data/events.json");

  const page = files["pages/events.html"];
  assertStringIncludes(page, "Summit picnic");
  assertStringIncludes(page, "Hike &lt;Club&gt;");
  assertStringIncludes(page, "Tiny &lt;dinner&gt;");
  assertStringIncludes(page, "T-shirt size: M");
  assertStringIncludes(page, "checked in");
  assertStringIncludes(page, "https://files.example.com/p1.jpg");
  assertStringIncludes(page, "repeats weekly");
  assertStringIncludes(page, "capacity 12");
  assert(!page.includes("<Club>"));
  assert(!page.includes("<dinner>"));

  const json = JSON.parse(files["data/events.json"]);
  assertEquals(json.signed_up[0].answers, { size: "M" });
  assertEquals(json.waiting.length, 1);
  assertEquals(json.check_ins.length, 1);
  assertEquals(
    json.photos[0].file.download_url,
    "https://files.example.com/p1.jpg",
  );
  assertEquals(json.events_made[0].time_zone, "Pacific/Auckland");
  assertEquals(json.calls_made[0].title, "Thursday sync");
  assertEquals(json.calls_made[0].repeats, "weekly");
  assertStringIncludes(page, "Calls you scheduled");
  assertStringIncludes(page, "Thursday sync");
  assert(!("code" in json.calls_made[0]));
  assertEquals(
    json.events_made[0].cover.download_url,
    "https://files.example.com/cover.jpg",
  );
});

Deno.test("an export without the part has no page; an empty one says so", () => {
  const without = texts(base);
  assert(!("pages/events.html" in without));
  assert(!("data/events.json" in without));

  const empty = texts({
    ...base,
    events2: {
      signed_up: [],
      waiting: [],
      check_ins: [],
      photos: [],
      events_made: [],
    },
  });
  assertStringIncludes(empty["pages/events.html"], "None.");
  assertStringIncludes(empty["index.html"], "0 signed up · 0 made");
});

Deno.test("my pictures and the covers of my events are the files to sign", () => {
  assertEquals(eventFilesToSign(events2), [
    { bucket: "chat-media", path: "c-1/events/p1.jpg" },
    { bucket: "chat-images", path: "conv-1/events/cover.jpg" },
  ]);
  assertEquals(eventFilesToSign(null), []);
  assertEquals(
    eventFilesToSign({
      photos: [{ bucket: "chat-media" }, { path: "x" }],
      events_made: [{ cover: null }],
    }),
    [],
  );
});
