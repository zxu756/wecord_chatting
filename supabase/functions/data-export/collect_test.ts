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

function fakeClient(tables: Record<string, Row[] | Error>) {
  const calls: string[] = [];
  const signed: { bucket: string; paths: string[] }[] = [];
  const client = {
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
  return { client: client as unknown as SupabaseClient, calls, signed };
}

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
    { user_low_id: "u-2", user_high_id: "u-3", created_at: "2026-03-02T00:00:00Z" },
  ],
  friend_requests: [
    { requester_id: me, receiver_id: "u-3", status: "pending", created_at: "x" },
    { requester_id: "u-2", receiver_id: "u-3", status: "pending", created_at: "x" },
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
  circle_channels: [{ conversation_id: "c-3", name: "general", circle_id: "k-1" }],
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
      attachment: { kind: "file", bucket: "chat-files", path: "c-1/plan.pdf", name: "plan.pdf" },
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
  assertEquals(data.settings["privacy"], { user_id: me, show_online_status: false });

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
  assert(calls.some((call) => call.startsWith("friendships.or(user_low_id.eq.u-1")));
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
