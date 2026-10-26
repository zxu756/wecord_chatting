import { assert, assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { collectExportData } from "./collect.ts";
import type { ExportStage } from "./export_builder.ts";

type Row = Record<string, unknown>;

/** Just enough of the query builder: filters are applied to in-memory rows. */
class FakeQuery {
  private filters: ((row: Row) => boolean)[] = [];
  private max = Infinity;

  constructor(
    private rows: Row[] | Error,
    readonly calls: string[],
    private table: string,
  ) {}

  select(_columns: string) {
    return this;
  }
  eq(column: string, value: unknown) {
    this.calls.push(`${this.table}.eq(${column})`);
    this.filters.push((row) => row[column] === value);
    return this;
  }
  neq(column: string, value: unknown) {
    this.filters.push((row) => row[column] !== value);
    return this;
  }
  in(column: string, values: unknown[]) {
    this.filters.push((row) => values.includes(row[column]));
    return this;
  }
  or(expression: string) {
    this.calls.push(`${this.table}.or(${expression.slice(0, 40)})`);
    // friendships: "a.eq.X,b.eq.X" style; keyset paging is not simulated.
    const alternatives = expression.split(",").map((part) =>
      /^(\w+)\.eq\.(.+)$/.exec(part)
    ).filter((match): match is RegExpExecArray => match !== null);
    if (alternatives.length > 0 && !expression.includes("and(")) {
      this.filters.push((row) =>
        alternatives.some((match) => row[match[1]] === match[2])
      );
    }
    return this;
  }
  order(_column: string, _options?: unknown) {
    return this;
  }
  limit(count: number) {
    this.max = count;
    return this;
  }
  maybeSingle() {
    return Promise.resolve(this.result(true));
  }
  // deno-lint-ignore no-explicit-any
  then(resolve: (value: any) => unknown) {
    return Promise.resolve(this.result(false)).then(resolve);
  }
  private result(single: boolean) {
    if (this.rows instanceof Error) {
      return { data: null, error: this.rows };
    }
    const found = this.rows.filter((row) => this.filters.every((f) => f(row)))
      .slice(0, this.max);
    return { data: single ? found[0] ?? null : found, error: null };
  }
}

interface FakeWorld {
  /** What export_my_moments / export_my_extras answer (or an error). */
  rpc?: Record<string, unknown>;
  /** Files in Storage by `bucket/path`. */
  objects?: Record<string, Uint8Array>;
}

function fakeClient(
  tables: Record<string, Row[] | Error>,
  extra: FakeWorld = {},
) {
  const calls: string[] = [];
  const signed: { bucket: string; paths: string[] }[] = [];
  const rpcCalls: { name: string; args: Row }[] = [];
  const downloads: string[] = [];
  const rpcAnswers = extra.rpc ?? emptyRpc;
  const client = {
    rpc: (name: string, args: Row) => {
      rpcCalls.push({ name, args });
      const answer = rpcAnswers[name];
      return Promise.resolve(
        answer === undefined || answer instanceof Error
          ? { data: null, error: answer ?? new Error("no such function") }
          : { data: answer, error: null },
      );
    },
    from: (table: string) =>
      new FakeQuery(tables[table] ?? new Error("no such table"), calls, table),
    auth: {
      admin: {
        getUserById: (id: string) =>
          Promise.resolve({
            data: {
              user: {
                id,
                email: "ada@example.com",
                created_at: "2026-01-01T00:00:00Z",
                last_sign_in_at: "2026-10-16T00:00:00Z",
              },
            },
            error: null,
          }),
      },
    },
    storage: {
      from: (bucket: string) => ({
        download: (path: string) => {
          downloads.push(`${bucket}/${path}`);
          const bytes = extra.objects?.[`${bucket}/${path}`];
          return Promise.resolve(
            bytes
              ? { data: new Blob([bytes as BlobPart]), error: null }
              : { data: null, error: new Error("not found") },
          );
        },
        createSignedUrls: (paths: string[], _seconds: number) => {
          signed.push({ bucket, paths });
          return Promise.resolve({
            data: paths.map((path) => ({
              path,
              signedUrl: `https://files.example/${bucket}/${path}?t=1`,
              error: null,
            })),
            error: null,
          });
        },
      }),
    },
  };
  return {
    client: client as unknown as SupabaseClient,
    calls,
    signed,
    rpcCalls,
    downloads,
  };
}

const emptyRpc: Record<string, unknown> = {
  export_my_moments: {
    settings: null,
    friend_prefs: [],
    posts: [],
    comments: [],
    likes: [],
    tags: [],
    stars: [],
  },
  export_my_extras: {
    chains: [],
    notes: [],
    task_lists: [],
    saved_messages: [],
    reminders: [],
    scheduled_messages: [],
    wallpapers: [],
  },
  export_my_forms: [],
  export_my_feedback: [],
  export_my_stories: { stories: [], close_friends: [], reports: [] },
  export_my_saved_items: { folders: [], items: [] },
  export_my_ai_digest: { enabled: false, subscriptions: [] },
  export_my_note_extras: { comments: [], templates: [], published: [] },
  export_my_task_extras: { lists: [] },
  export_my_moments_more: {
    pinned: [],
    reminded: [],
    reminded_by: [],
    comment_pictures: [],
  },
  export_my_knowledge: { pages_made: [], pages_read: [] },
  export_my_honors: { titles: [], honors: [], streaks: [], opted_out: [] },
  export_my_channel_posts: {
    media_posts: [],
    questions: [],
    accepted_answers: [],
  },
  export_my_events2: {
    signed_up: [],
    waiting: [],
    check_ins: [],
    photos: [],
    events_made: [],
  },
  export_my_quick_replies: { quick_replies: [], away: null },
  export_my_check_ins: { check_ins: [], streaks: [], boards_made: [] },
  export_my_group_tabs: { tabs_added: [] },
  export_my_interactions: {
    presses: [],
    private_replies: [],
  },
  export_my_group_space: { albums: [], items: [], folders: [], files: [] },
  export_my_account_security: {
    events: [],
    recovery_codes: { remaining: null, made_at: null },
    passkeys: [],
  },
};

const feedbackAnswer = [{
  id: "fb-1",
  message: "The send button is hidden",
  app_version: "1.4.0",
  platform: "web",
  status: "closed",
  created_at: "2026-10-20T08:00:00Z",
  replied_at: "2026-10-21T08:00:00Z",
  screenshot_bucket: "feedback-screenshots",
  screenshot_path: "u-1/s-1.jpg",
  replies: [{ body: "Fixed in 1.4.1", published_at: "2026-10-21T08:00:00Z" }],
}];

const favoritesAnswer = {
  folders: [{ id: "f-1", name: "Trips", created_at: "2026-10-20T08:00:00Z" }],
  items: [{
    id: "i-1",
    kind: "note",
    title: "Packing",
    body: "tent",
    saved_at: "2026-10-20T08:00:00Z",
    images: [{ bucket: "saved-notes", path: "u-1/i-1-0.jpg" }],
  }],
};

const storiesAnswer = {
  stories: [{
    id: "s-1",
    media_kind: "photo",
    caption: "Sunrise",
    audience: "friends",
    created_at: "2026-10-20T08:00:00Z",
    expires_at: "2026-10-21T08:00:00Z",
    viewer_count: 3,
    bucket: "stories",
    path: "u-1/s-1.jpg",
    poster_path: null,
    thumb_path: "u-1/s-1-t.jpg",
  }],
  close_friends: [{ user_id: "u-2", name: "Bart", username: "bart" }],
  reports: [],
};

const me = "u-1";
const world: Record<string, Row[] | Error> = {
  profiles: [
    { id: me, username: "ada", display_name: "Ada", bio: "hi" },
    { id: "u-2", username: "bart", display_name: "Bart" },
    { id: "u-3", username: "cy", display_name: "Cy" },
  ],
  user_privacy_settings: [{ user_id: me, show_online_status: false }],
  circle_notification_settings: [
    { user_id: me, circle_id: "k-1", level: "mentions" },
    { user_id: "u-2", circle_id: "k-1", level: "all" },
  ],
  friendships: [
    {
      user_low_id: me,
      user_high_id: "u-2",
      user_low_remark: "Bart from work",
      created_at: "2026-03-01T00:00:00Z",
    },
    {
      user_low_id: "u-2",
      user_high_id: "u-3",
      created_at: "2026-03-02T00:00:00Z",
    },
  ],
  friend_requests: [
    {
      requester_id: me,
      receiver_id: "u-3",
      status: "pending",
      created_at: "x",
    },
    {
      requester_id: "u-2",
      receiver_id: "u-3",
      status: "pending",
      created_at: "x",
    },
  ],
  blocks: [{ blocker_id: me, blocked_id: "u-3", created_at: "y" }],
  conversation_members: [
    { conversation_id: "c-1", user_id: me, role: "member", joined_at: "j" },
    { conversation_id: "c-1", user_id: "u-2", role: "member" },
    { conversation_id: "c-2", user_id: me, role: "owner", joined_at: "j" },
    { conversation_id: "c-3", user_id: me, role: "member", joined_at: "j" },
    { conversation_id: "c-9", user_id: "u-2", role: "member" },
  ],
  conversations: [
    { id: "c-1", type: "direct", title: null, created_at: "c" },
    { id: "c-2", type: "group", title: "Climbing crew", created_at: "c" },
    { id: "c-3", type: "channel", title: null, created_at: "c" },
    { id: "c-9", type: "group", title: "Not mine", created_at: "c" },
  ],
  circle_channels: [{
    conversation_id: "c-3",
    name: "general",
    circle_id: "k-1",
  }],
  circles: [{ id: "k-1", name: "Hikers" }],
  circle_members: [
    { circle_id: "k-1", user_id: me, nickname: "Trail Ada", joined_at: "j2" },
    { circle_id: "k-1", user_id: "u-2", nickname: "Bart" },
  ],
  messages: [
    {
      id: "m-1",
      sender_id: me,
      conversation_id: "c-1",
      type: "file",
      body: "plan",
      attachment: {
        kind: "file",
        bucket: "chat-files",
        path: "c-1/plan.pdf",
        name: "plan.pdf",
      },
      created_at: "2026-10-01T10:00:00Z",
      edited_at: null,
      recalled_at: null,
    },
    {
      id: "m-2",
      sender_id: "u-2",
      conversation_id: "c-1",
      type: "text",
      body: "SECRET from Bart",
      attachment: null,
      created_at: "2026-10-01T10:01:00Z",
    },
    {
      id: "m-3",
      sender_id: me,
      conversation_id: "c-2",
      type: "text",
      body: "hello crew",
      attachment: null,
      created_at: "2026-10-02T10:00:00Z",
    },
  ],
};

const now = new Date("2026-10-17T12:00:00Z");

Deno.test("collects only the person's own data, with names for chats", async () => {
  const { client, signed } = fakeClient(world);
  const stages: ExportStage[] = [];
  const data = await collectExportData(client, {
    userId: me,
    now,
    onStage: (stage) => void stages.push(stage),
  });

  assertEquals(data.user.email, "ada@example.com");
  assertEquals(data.profile?.["username"], "ada");
  assertEquals(data.settings["privacy"], {
    user_id: me,
    show_online_status: false,
  });

  assertEquals(data.friends.map((f) => [f.username, f.remark]), [
    ["bart", "Bart from work"],
  ]);
  assertEquals(data.friendRequests.length, 1);
  assertEquals((data.friendRequests[0]["person"] as Row)["username"], "cy");
  assertEquals((data.blocked[0]["person"] as Row)["username"], "cy");

  assertEquals(
    data.conversations.map((c) => [c.id, c.kind, c.name, c.circleName]),
    [
      ["c-1", "direct", "Bart", null],
      ["c-2", "group", "Climbing crew", null],
      ["c-3", "channel", "#general", "Hikers"],
    ],
  );

  // Others' messages never get in.
  assertEquals(data.messages.map((m) => m.id), ["m-1", "m-3"]);
  assert(!JSON.stringify(data).includes("SECRET"));

  assertEquals(data.circles, [
    {
      id: "k-1",
      name: "Hikers",
      joinedAt: "j2",
      nickname: "Trail Ada",
      notificationLevel: "mentions",
    },
  ]);

  // File links are signed once per file and last as long as the export.
  assertEquals(signed, [{ bucket: "chat-files", paths: ["c-1/plan.pdf"] }]);
  assertEquals(
    data.attachmentLinks["chat-files/c-1/plan.pdf"],
    "https://files.example/chat-files/c-1/plan.pdf?t=1",
  );
  assertEquals(data.linksExpireAt, "2026-10-24T12:00:00.000Z");
  assertEquals(data.skipped, []);
  assertEquals(stages, [
    "profile",
    "friends",
    "conversations",
    "messages",
    "circles",
    "moments",
    "more",
    "attachments",
  ]);
});

Deno.test("every query is scoped to the person", async () => {
  const { client, calls } = fakeClient(world);
  await collectExportData(client, { userId: me, now });
  for (
    const expected of [
      "profiles.eq(id)",
      "user_privacy_settings.eq(user_id)",
      "blocks.eq(blocker_id)",
      "conversation_members.eq(user_id)",
      "messages.eq(sender_id)",
      "circle_members.eq(user_id)",
    ]
  ) {
    assert(calls.includes(expected), `missing ${expected}`);
  }
  assert(
    calls.some((call) => call.startsWith("friendships.or(user_low_id.eq.u-1")),
  );
});

Deno.test("a table that cannot be read is skipped, not fatal", async () => {
  const { client } = fakeClient({
    ...world,
    circle_members: new Error("relation does not exist"),
    user_privacy_settings: new Error("nope"),
  });
  const data = await collectExportData(client, { userId: me, now });
  assertEquals(data.circles, []);
  assertEquals(data.settings["privacy"], undefined);
  assertEquals(data.skipped.sort(), ["circles", "privacy settings"]);
  assertEquals(data.messages.length, 2);
});

// ---- Moments, chains, notes and the rest --------------------------------

const momentsAnswer = {
  settings: { visible_range: "all", cover_path: "u-1/cover-1.jpg" },
  friend_prefs: [{ friend: { id: "u-2" }, hide_mine: true }],
  posts: [{
    id: "p-1",
    body: "mine",
    photos: [
      { path: "u-1/p-1-0.jpg" },
      { path: "u-1/p-1-1.jpg" },
      // Never fetched, whatever the database says.
      { path: "u-2/p-9-0.jpg" },
    ],
    video: { path: "u-1/p-1-v.mp4", size: 3 * 1024 * 1024 },
  }],
  comments: [{ id: "cm-1", text: "hi" }],
  likes: [{ post_id: "p-9" }],
  tags: [{ id: "t-1", name: "Family", friends: [] }],
  stars: [{ friend: { id: "u-2" } }],
};
const noteExtrasAnswer = {
  comments: [{ id: "nc-1", body: "looks good" }],
  templates: [],
  published: [],
};

const digestAnswer = {
  enabled: true,
  deliver_at: "08:00",
  language: "zh",
  time_zone: "Asia/Shanghai",
  subscriptions: [{ conversation_id: "c-2", name: "Climbing crew" }],
};

const formsAnswer = [{
  id: "f-1",
  title: "Hike sign-up",
  created_by_me: false,
  questions: [{ id: "photo", type: "image", label: "A photo" }],
  my_responses: [{
    answers: { photo: { bucket: "chat-images", path: "g-1/forms/f-1/a.jpg" } },
  }],
}];
const extrasAnswer = {
  chains: [{ id: "ch-1", title: "Dinner", my_entry: { text: "me" } }],
  notes: [{ id: "n-1", blocks: [] }],
  task_lists: [{ id: "l-1", items: [] }],
  saved_messages: [{ id: "s-1" }],
  reminders: [{ id: "r-1" }],
  scheduled_messages: [{ id: "sc-1" }],
  wallpapers: [{ kind: "photo", photo_path: "u-1/w-1.jpg" }],
};

Deno.test("Moments and the rest come from the database functions, for this person", async () => {
  const { client, rpcCalls } = fakeClient(world, {
    rpc: {
      export_my_moments: momentsAnswer,
      export_my_extras: extrasAnswer,
      export_my_forms: formsAnswer,
      export_my_feedback: feedbackAnswer,
      export_my_stories: storiesAnswer,
      export_my_saved_items: favoritesAnswer,
      export_my_ai_digest: digestAnswer,
      export_my_note_extras: noteExtrasAnswer,
      export_my_task_extras: { lists: [{ id: "l-1", items: [] }] },
      export_my_knowledge: { pages_made: [], pages_read: [] },
      export_my_honors: { titles: [], honors: [], streaks: [], opted_out: [] },
      export_my_channel_posts: {
        media_posts: [],
        questions: [],
        accepted_answers: [],
      },
      export_my_events2: {
        signed_up: [],
        waiting: [],
        check_ins: [],
        photos: [],
        events_made: [],
      },
      export_my_quick_replies: { quick_replies: [], away: null },
      export_my_check_ins: { check_ins: [], streaks: [], boards_made: [] },
      export_my_group_tabs: { tabs_added: [] },
      export_my_interactions: {
        presses: [],
        private_replies: [],
      },
      export_my_group_space: { albums: [], items: [], folders: [], files: [] },
      export_my_account_security: {
        events: [],
        recovery_codes: { remaining: null, made_at: null },
        passkeys: [],
      },
      export_my_moments_more: {
        pinned: [],
        reminded: [],
        reminded_by: [],
        comment_pictures: [{ comment_id: "c-1", path: "u-1/c-c-1.png" }],
      },
    },
    objects: {
      "moments/u-1/cover-1.jpg": new Uint8Array([1]),
      "moments/u-1/p-1-0.jpg": new Uint8Array([2, 2]),
      "moments/u-1/p-1-1.jpg": new Uint8Array([3, 3, 3]),
      "wallpapers/u-1/w-1.jpg": new Uint8Array([4]),
      "moments/u-2/p-9-0.jpg": new Uint8Array([9]),
    },
  });
  const data = await collectExportData(client, { userId: me, now });
  assertEquals(rpcCalls, [
    { name: "export_my_moments", args: { target_user_id: me } },
    { name: "export_my_extras", args: { target_user_id: me } },
    { name: "export_my_forms", args: { target_user_id: me } },
    { name: "export_my_feedback", args: { target_user_id: me } },
    { name: "export_my_ai_digest", args: { target_user_id: me } },
    { name: "export_my_note_extras", args: { target_user_id: me } },
    { name: "export_my_stories", args: { target_user_id: me } },
    { name: "export_my_task_extras", args: { target_user_id: me } },
    { name: "export_my_saved_items", args: { target_user_id: me } },
    { name: "export_my_moments_more", args: { target_user_id: me } },
    { name: "export_my_knowledge", args: { target_user_id: me } },
    { name: "export_my_honors", args: { target_user_id: me } },
    { name: "export_my_channel_posts", args: { target_user_id: me } },
    { name: "export_my_events2", args: { target_user_id: me } },
    { name: "export_my_check_ins", args: { target_user_id: me } },
    { name: "export_my_group_tabs", args: { target_user_id: me } },
    { name: "export_my_interactions", args: { target_user_id: me } },
    { name: "export_my_group_space", args: { target_user_id: me } },
    { name: "export_my_account_security", args: { target_user_id: me } },
    { name: "export_my_quick_replies", args: { target_user_id: me } },
  ]);
  assertEquals((data.favorites?.["items"] as unknown[] | undefined)?.length, 1);
  // The pictures of my notes are linked, never put into the archive.
  assert("saved-notes/u-1/i-1-0.jpg" in data.attachmentLinks);
  assertEquals(data.aiDigest?.["enabled"], true);
  assertEquals((data.noteExtras?.["comments"] as unknown[]).length, 1);
  assertEquals((data.taskExtras?.["lists"] as unknown[]).length, 1);
  assertEquals(data.forms?.length, 1);
  assertEquals(data.feedback?.length, 1);
  assertEquals((data.stories?.["stories"] as unknown[] | undefined)?.length, 1);
  // My dailies are linked, never put into the archive.
  assert("stories/u-1/s-1.jpg" in data.attachmentLinks);
  assert("stories/u-1/s-1-t.jpg" in data.attachmentLinks);
  // The screenshot of my feedback is linked, never put into the archive.
  assert("feedback-screenshots/u-1/s-1.jpg" in data.attachmentLinks);
  // The picture I attached to an answer is linked, not fetched.
  assert("chat-images/g-1/forms/f-1/a.jpg" in data.attachmentLinks);
  assertEquals(data.moments?.posts.length, 1);
  assertEquals(data.moments?.settings?.["cover_path"], "u-1/cover-1.jpg");
  assertEquals(data.moments?.friendPrefs.length, 1);
  assertEquals(data.moments?.stars.length, 1);
  assertEquals(data.extras?.chains.length, 1);
  assertEquals(data.extras?.taskLists.length, 1);
  assertEquals(data.extras?.savedMessages.length, 1);
  assertEquals(data.extras?.wallpapers.length, 1);
  assertEquals(data.skipped, []);
});

Deno.test("my photos go into the ZIP; a video of known size above the cap is linked", async () => {
  const { client, signed, downloads } = fakeClient(world, {
    rpc: {
      export_my_moments: momentsAnswer,
      export_my_extras: extrasAnswer,
      export_my_forms: formsAnswer,
      export_my_feedback: feedbackAnswer,
      export_my_stories: storiesAnswer,
      export_my_saved_items: favoritesAnswer,
      export_my_ai_digest: digestAnswer,
      export_my_note_extras: noteExtrasAnswer,
      export_my_task_extras: { lists: [{ id: "l-1", items: [] }] },
      export_my_knowledge: { pages_made: [], pages_read: [] },
      export_my_honors: { titles: [], honors: [], streaks: [], opted_out: [] },
      export_my_channel_posts: {
        media_posts: [],
        questions: [],
        accepted_answers: [],
      },
      export_my_events2: {
        signed_up: [],
        waiting: [],
        check_ins: [],
        photos: [],
        events_made: [],
      },
      export_my_quick_replies: { quick_replies: [], away: null },
      export_my_check_ins: { check_ins: [], streaks: [], boards_made: [] },
      export_my_group_tabs: { tabs_added: [] },
      export_my_interactions: {
        presses: [],
        private_replies: [],
      },
      export_my_group_space: { albums: [], items: [], folders: [], files: [] },
      export_my_account_security: {
        events: [],
        recovery_codes: { remaining: null, made_at: null },
        passkeys: [],
      },
      export_my_moments_more: {
        pinned: [],
        reminded: [],
        reminded_by: [],
        comment_pictures: [],
      },
    },
    objects: {
      "moments/u-1/cover-1.jpg": new Uint8Array([1]),
      "moments/u-1/p-1-0.jpg": new Uint8Array([2, 2]),
      "moments/u-1/p-1-1.jpg": new Uint8Array([3, 3, 3]),
      "moments/u-1/p-1-v.mp4": new Uint8Array([7, 7, 7]),
      "wallpapers/u-1/w-1.jpg": new Uint8Array([4]),
      "moments/u-2/p-9-0.jpg": new Uint8Array([9]),
    },
  });
  const data = await collectExportData(client, {
    userId: me,
    now,
    fileLimits: { maxFileBytes: 1024 * 1024 },
  });
  assertEquals(
    data.files.map((f) => [f.key, f.zipPath, [...f.bytes]]),
    [
      ["moments/u-1/cover-1.jpg", "files/moments/cover-1.jpg", [1]],
      ["wallpapers/u-1/w-1.jpg", "files/wallpapers/w-1.jpg", [4]],
      ["moments/u-1/p-1-0.jpg", "files/moments/p-1-0.jpg", [2, 2]],
      ["moments/u-1/p-1-1.jpg", "files/moments/p-1-1.jpg", [3, 3, 3]],
    ],
  );
  // Somebody else's folder is never touched.
  assert(!downloads.some((d) => d.includes("u-2")));
  // The video is over the cap, so it was not even downloaded: it is linked.
  assert(!downloads.includes("moments/u-1/p-1-v.mp4"));
  const moments = signed.find((s) => s.bucket === "moments");
  assertEquals(moments?.paths, ["u-1/p-1-v.mp4"]);
  assertEquals(
    data.attachmentLinks["moments/u-1/p-1-v.mp4"],
    "https://files.example/moments/u-1/p-1-v.mp4?t=1",
  );
  assertEquals(data.attachmentLinks["moments/u-1/p-1-0.jpg"], undefined);
});

Deno.test("files past the total or count cap are linked, not dropped", async () => {
  const objects = {
    "moments/u-1/cover-1.jpg": new Uint8Array(6),
    "moments/u-1/p-1-0.jpg": new Uint8Array(6),
    "moments/u-1/p-1-1.jpg": new Uint8Array(2),
    "wallpapers/u-1/w-1.jpg": new Uint8Array(1),
  };
  const run = async (
    limits: Parameters<typeof collectExportData>[1]["fileLimits"],
  ) => {
    const { client } = fakeClient(world, {
      rpc: {
        export_my_moments: momentsAnswer,
        export_my_extras: extrasAnswer,
        export_my_forms: [],
        export_my_feedback: [],
      },
      objects,
    });
    return await collectExportData(client, {
      userId: me,
      now,
      fileLimits: { maxFileBytes: 100, ...limits },
    });
  };
  // 10 bytes in all: the cover (6) and the wallpaper (1) fit, the next 6
  // does not, the 2 after it does again.
  const byTotal = await run({ maxTotalBytes: 10 });
  assertEquals(byTotal.files.map((f) => f.key), [
    "moments/u-1/cover-1.jpg",
    "wallpapers/u-1/w-1.jpg",
    "moments/u-1/p-1-1.jpg",
  ]);
  assert("moments/u-1/p-1-0.jpg" in byTotal.attachmentLinks);
  const byCount = await run({ maxCount: 1 });
  assertEquals(byCount.files.map((f) => f.key), ["moments/u-1/cover-1.jpg"]);
  // (The video is above maxFileBytes in every run, so it is always linked.)
  const own = (links: Record<string, string>) =>
    Object.keys(links).filter((key) => !key.startsWith("chat-files/")).sort();
  assertEquals(own(byCount.attachmentLinks), [
    "moments/u-1/p-1-0.jpg",
    "moments/u-1/p-1-1.jpg",
    "moments/u-1/p-1-v.mp4",
    "wallpapers/u-1/w-1.jpg",
  ]);
  const byTime = await run({ timeBudgetMs: -1 });
  assertEquals(byTime.files, []);
  assertEquals(own(byTime.attachmentLinks).length, 5);
});

Deno.test("a file that cannot be downloaded is linked instead", async () => {
  const { client } = fakeClient(world, {
    rpc: {
      export_my_moments: momentsAnswer,
      export_my_extras: extrasAnswer,
      export_my_forms: formsAnswer,
      export_my_feedback: feedbackAnswer,
      export_my_stories: storiesAnswer,
      export_my_saved_items: favoritesAnswer,
      export_my_ai_digest: digestAnswer,
      export_my_note_extras: noteExtrasAnswer,
      export_my_task_extras: { lists: [{ id: "l-1", items: [] }] },
      export_my_knowledge: { pages_made: [], pages_read: [] },
      export_my_honors: { titles: [], honors: [], streaks: [], opted_out: [] },
      export_my_channel_posts: {
        media_posts: [],
        questions: [],
        accepted_answers: [],
      },
      export_my_events2: {
        signed_up: [],
        waiting: [],
        check_ins: [],
        photos: [],
        events_made: [],
      },
      export_my_quick_replies: { quick_replies: [], away: null },
      export_my_check_ins: { check_ins: [], streaks: [], boards_made: [] },
      export_my_group_tabs: { tabs_added: [] },
      export_my_interactions: {
        presses: [],
        private_replies: [],
      },
      export_my_group_space: { albums: [], items: [], folders: [], files: [] },
      export_my_account_security: {
        events: [],
        recovery_codes: { remaining: null, made_at: null },
        passkeys: [],
      },
      export_my_moments_more: {
        pinned: [],
        reminded: [],
        reminded_by: [],
        comment_pictures: [],
      },
    },
    objects: { "moments/u-1/cover-1.jpg": new Uint8Array([1]) },
  });
  const data = await collectExportData(client, { userId: me, now });
  assertEquals(data.files.map((f) => f.key), ["moments/u-1/cover-1.jpg"]);
  assert("moments/u-1/p-1-0.jpg" in data.attachmentLinks);
  assertEquals(data.skipped, []);
});

Deno.test("a database function that is missing is skipped, not fatal", async () => {
  const { client } = fakeClient(world, {
    rpc: { export_my_extras: new Error("function does not exist") },
  });
  const data = await collectExportData(client, { userId: me, now });
  assertEquals(data.moments, null);
  assertEquals(data.extras, null);
  assertEquals(data.forms, null);
  assertEquals(data.feedback, null);
  assertEquals(data.aiDigest, null);
  assertEquals(data.noteExtras, null);
  assertEquals(data.stories, null);
  assertEquals(data.taskExtras, null);
  assertEquals(data.favorites, null);
  assertEquals(data.momentsMore, null);
  assertEquals(data.knowledge, null);
  assertEquals(data.honors, null);
  assertEquals(data.channelPosts, null);
  assertEquals(data.events2, null);
  assertEquals(data.quickReplies, null);
  assertEquals(data.checkIns, null);
  assertEquals(data.groupTabs, null);
  assertEquals(data.interactions, null);
  assertEquals(data.groupSpace, null);
  assertEquals(data.accountSecurity, null);
  assertEquals(data.skipped.sort(), [
    "account security record",
    "bot buttons and commands",
    "chat tabs",
    "check-ins",
    "circle titles and honors",
    "daily",
    "daily digest",
    "events",
    "favorites",
    "feedback",
    "forms",
    "group space",
    "knowledge base pages",
    "moments",
    "note comments and templates",
    "notes, lists and more",
    "picture posts and questions",
    "pins and reminders",
    "quick replies",
    "task list fields",
  ]);
  assertEquals(data.messages.length, 2);
  assertEquals(data.files, []);
});
