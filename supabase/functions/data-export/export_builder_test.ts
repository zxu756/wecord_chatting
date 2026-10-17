import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "jsr:@std/assert@1";
import { strFromU8, unzipSync } from "npm:fflate@0.8.2";
import {
  attachmentOf,
  attachmentsToSign,
  buildExportFiles,
  buildExportZip,
  escapeHtml,
  type ExportData,
  exportExpiresAt,
  exportObjectPath,
  rateLimit,
  readableTime,
  slugify,
  stageProgress,
} from "./export_builder.ts";

const data: ExportData = {
  generatedAt: "2026-10-17T14:03:00.000Z",
  user: {
    id: "u-1",
    email: "ada@example.com",
    createdAt: "2026-01-02T03:04:05.000Z",
    lastSignInAt: "2026-10-16T08:00:00.000Z",
  },
  profile: { id: "u-1", username: "ada", display_name: "Ada <b>L</b>", bio: "Hi" },
  settings: { privacy: { show_online_status: true } },
  friends: [
    {
      id: "u-2",
      username: "bart",
      displayName: "Bart",
      remark: "Bart from work",
      since: "2026-03-01T00:00:00.000Z",
    },
  ],
  friendRequests: [{ status: "pending", direction: "sent" }],
  blocked: [{ person: { username: "spammer" } }],
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
    {
      id: "c-3",
      kind: "group",
      name: "Climbing crew",
      circleName: null,
      joinedAt: null,
      role: "member",
      createdAt: null,
    },
    {
      id: "c-4",
      kind: "channel",
      name: "#general",
      circleName: "Hikers",
      joinedAt: null,
      role: null,
      createdAt: null,
    },
  ],
  messages: [
    {
      id: "m-2",
      conversationId: "c-1",
      type: "file",
      body: "the plan",
      attachment: {
        kind: "file",
        bucket: "chat-files",
        path: "c-1/plan.pdf",
        name: "plan.pdf",
        size: 1234,
      },
      createdAt: "2026-10-02T10:00:00.000Z",
      editedAt: null,
      recalledAt: null,
    },
    {
      id: "m-1",
      conversationId: "c-1",
      type: "text",
      body: "hello <script>alert(1)</script> & 你好",
      attachment: null,
      createdAt: "2026-10-01T09:30:00.000Z",
      editedAt: "2026-10-01T09:31:00.000Z",
      recalledAt: null,
    },
    {
      id: "m-3",
      conversationId: "c-2",
      type: "text",
      body: "see you at 8",
      attachment: null,
      createdAt: "2026-10-03T09:30:00.000Z",
      editedAt: null,
      recalledAt: null,
    },
    {
      id: "m-4",
      conversationId: "c-gone",
      type: "text",
      body: "from a chat I left",
      attachment: null,
      createdAt: "2026-09-03T09:30:00.000Z",
      editedAt: null,
      recalledAt: null,
    },
  ],
  circles: [
    {
      id: "k-1",
      name: "Hikers",
      joinedAt: "2026-05-01T00:00:00.000Z",
      nickname: "Trail Ada",
      notificationLevel: "mentions",
    },
  ],
  attachmentLinks: { "chat-files/c-1/plan.pdf": "https://files.example/plan?token=abc&x=1" },
  linksExpireAt: "2026-10-24T14:03:00.000Z",
  skipped: [],
};

function archive(input: ExportData = data) {
  const unzipped = unzipSync(buildExportZip(input));
  return Object.fromEntries(
    Object.entries(unzipped).map(([name, bytes]) => [name, strFromU8(bytes)]),
  );
}

Deno.test("the archive holds the JSON files, an HTML index and a page per chat", () => {
  const files = archive();
  assertEquals(
    Object.keys(files).sort(),
    [
      "README.txt",
      "data/circles.json",
      "data/conversations.json",
      "data/friends.json",
      "data/messages.json",
      "data/profile.json",
      "data/settings.json",
      "index.html",
      "messages/a-conversation-you-left.html",
      "messages/climbing-crew.html",
      "messages/bart.html",
    ].sort(),
  );
});

Deno.test("messages.json has text, times and attachment links", () => {
  const messages = JSON.parse(archive()["data/messages.json"]);
  assertEquals(messages.length, 4);
  const withFile = messages.find((m: { id: string }) => m.id === "m-2");
  assertEquals(withFile.text, "the plan");
  assertEquals(withFile.attachment.name, "plan.pdf");
  assertEquals(withFile.attachment.size, 1234);
  assertEquals(
    withFile.attachment.download_url,
    "https://files.example/plan?token=abc&x=1",
  );
  assertEquals(withFile.attachment.download_url_expires_at, data.linksExpireAt);
  const plain = messages.find((m: { id: string }) => m.id === "m-1");
  assertEquals(plain.attachment, null);
  assertEquals(plain.sent_at, "2026-10-01T09:30:00.000Z");
  assertEquals(plain.edited_at, "2026-10-01T09:31:00.000Z");
});

Deno.test("other JSON files carry the profile, friends and settings", () => {
  const files = archive();
  const profile = JSON.parse(files["data/profile.json"]);
  assertEquals(profile.account.email, "ada@example.com");
  assertEquals(profile.profile.username, "ada");
  assertEquals(
    JSON.parse(files["data/settings.json"]).privacy.show_online_status,
    true,
  );
  const friends = JSON.parse(files["data/friends.json"]);
  assertEquals(friends.friends[0].remark, "Bart from work");
  assertEquals(friends.blocked.length, 1);
  const conversations = JSON.parse(files["data/conversations.json"]);
  assertEquals(
    conversations.find((c: { id: string }) => c.id === "c-1").messages_from_you,
    2,
  );
  assertEquals(JSON.parse(files["data/circles.json"])[0].nickname, "Trail Ada");
});

Deno.test("HTML is escaped and conversation pages link attachments", () => {
  const files = archive();
  const index = files["index.html"];
  assertStringIncludes(index, "Ada &lt;b&gt;L&lt;/b&gt;");
  assert(!index.includes("<b>L</b>"));
  assertStringIncludes(index, 'href="messages/bart.html"');
  assertStringIncludes(index, "in Hikers");
  assertStringIncludes(index, "2 messages from you");

  const page = files["messages/bart.html"];
  assert(!page.includes("<script>"));
  assertStringIncludes(page, "hello &lt;script&gt;alert(1)&lt;/script&gt; &amp; 你好");
  assertStringIncludes(
    page,
    '<a href="https://files.example/plan?token=abc&amp;x=1">plan.pdf</a>',
  );
  assertStringIncludes(page, "edited 2026-10-01 09:31 UTC");
  // Oldest first.
  assert(page.indexOf("hello") < page.indexOf("the plan"));
});

Deno.test("two chats with one name get two pages", () => {
  const files = archive({
    ...data,
    messages: [
      ...data.messages,
      {
        id: "m-9",
        conversationId: "c-3",
        type: "text",
        body: "other crew",
        attachment: null,
        createdAt: "2026-10-04T00:00:00.000Z",
        editedAt: null,
        recalledAt: null,
      },
    ],
  });
  assertStringIncludes(files["messages/climbing-crew.html"], "see you at 8");
  assertStringIncludes(files["messages/climbing-crew-2.html"], "other crew");
});

Deno.test("an account without data still makes a valid archive", () => {
  const files = archive({
    ...data,
    profile: null,
    settings: {},
    friends: [],
    friendRequests: [],
    blocked: [],
    conversations: [],
    messages: [],
    circles: [],
    attachmentLinks: {},
    skipped: ["circles"],
  });
  assertStringIncludes(files["index.html"], "No friends yet.");
  assertStringIncludes(files["index.html"], "circles could not be read");
  assertEquals(JSON.parse(files["data/messages.json"]), []);
  assertEquals(
    Object.keys(files).filter((name) => name.startsWith("messages/")).length,
    0,
  );
});

Deno.test("attachments are found in files, images and voice messages", () => {
  assertEquals(
    attachmentOf({
      type: "image",
      attachment: { kind: "image", bucket: "chat-images", path: "c/a/b.jpg" },
    }),
    {
      kind: "image",
      bucket: "chat-images",
      path: "c/a/b.jpg",
      name: "b.jpg",
      size: null,
    },
  );
  assertEquals(attachmentOf({ type: "text", attachment: null }), null);
  assertEquals(attachmentOf({ type: "system", attachment: { kind: "pin" } }), null);
  const messages = data.messages.concat(data.messages);
  assertEquals(attachmentsToSign(messages), [
    { bucket: "chat-files", path: "c-1/plan.pdf" },
  ]);
});

Deno.test("helpers", () => {
  assertEquals(escapeHtml(`<a href="x">'&'</a>`), "&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;");
  assertEquals(readableTime("2026-10-17T14:03:59.000Z"), "2026-10-17 14:03 UTC");
  assertEquals(readableTime(null), "");
  assertEquals(readableTime("soon"), "soon");
  assertEquals(slugify("Climbing Crew!!"), "climbing-crew");
  assertEquals(slugify("周末爬山"), "周末爬山");
  assertEquals(slugify("???"), "chat");
  assertEquals(
    exportObjectPath("u-1", new Date("2026-10-17T14:03:09.123Z")),
    "u-1/20261017T140309Z.zip",
  );
  assertEquals(
    exportExpiresAt(new Date("2026-10-17T14:03:09.000Z")).toISOString(),
    "2026-10-24T14:03:09.000Z",
  );
  assertEquals(stageProgress("messages") < stageProgress("circles"), true);
  assertEquals(stageProgress("ready"), 100);
  assertEquals(stageProgress("nonsense"), 0);
});

Deno.test("one export per 24 hours", () => {
  const now = new Date("2026-10-17T12:00:00.000Z");
  assertEquals(rateLimit(null, now), { allowed: true, retryAfterSeconds: 0 });
  assertEquals(
    rateLimit(new Date("2026-10-16T11:59:59.000Z"), now).allowed,
    true,
  );
  assertEquals(rateLimit(new Date("2026-10-16T12:00:00.000Z"), now).allowed, true);
  assertEquals(rateLimit(new Date("2026-10-17T11:00:00.000Z"), now), {
    allowed: false,
    retryAfterSeconds: 23 * 3600,
  });
  assertEquals(
    rateLimit(new Date("2026-10-17T12:00:00.000Z"), now).retryAfterSeconds,
    24 * 3600,
  );
});
