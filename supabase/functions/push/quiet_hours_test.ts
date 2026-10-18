import { assertEquals } from "jsr:@std/assert@1";
import {
  clockSeconds,
  dropQuietPushes,
  isHeldBack,
  type QuietRecipient,
  quietWindowContains,
  type RpcClient,
} from "./quiet_hours.ts";

const everyDay = [1, 2, 3, 4, 5, 6, 7];
const unix = (utc: string) => Date.parse(utc.replace(" ", "T") + "Z") / 1000;

// The same cases are in test/supabase/quiet_hours_behaviour.sql (the SQL rule)
// and test/features/notifications/quiet_hours_test.dart (the app's moon).
const vectors: [
  label: string,
  zone: string | null,
  days: number[],
  start: string,
  end: string,
  at: string,
  expected: boolean,
][] = [
  // Shanghai (+8, no daylight saving), every day 23:00-07:00.
  [
    "across midnight: start is in",
    "Asia/Shanghai",
    everyDay,
    "23:00",
    "07:00",
    "2026-10-20 15:00:00",
    true,
  ],
  [
    "across midnight: a minute before",
    "Asia/Shanghai",
    everyDay,
    "23:00",
    "07:00",
    "2026-10-20 14:59:00",
    false,
  ],
  [
    "across midnight: after midnight",
    "Asia/Shanghai",
    everyDay,
    "23:00",
    "07:00",
    "2026-10-20 18:00:00",
    true,
  ],
  [
    "across midnight: last minute",
    "Asia/Shanghai",
    everyDay,
    "23:00",
    "07:00",
    "2026-10-20 22:59:00",
    true,
  ],
  [
    "across midnight: end is out",
    "Asia/Shanghai",
    everyDay,
    "23:00",
    "07:00",
    "2026-10-20 23:00:00",
    false,
  ],
  // Weekdays are the days a window starts: Monday only.
  [
    "monday night",
    "Asia/Shanghai",
    [1],
    "23:00",
    "07:00",
    "2026-10-19 15:30:00",
    true,
  ],
  [
    "tuesday early morning belongs to monday",
    "Asia/Shanghai",
    [1],
    "23:00",
    "07:00",
    "2026-10-19 19:00:00",
    true,
  ],
  [
    "monday early morning belongs to sunday",
    "Asia/Shanghai",
    [1],
    "23:00",
    "07:00",
    "2026-10-18 19:00:00",
    false,
  ],
  [
    "tuesday night is not picked",
    "Asia/Shanghai",
    [1],
    "23:00",
    "07:00",
    "2026-10-20 15:30:00",
    false,
  ],
  [
    "sunday night runs into monday",
    "Asia/Shanghai",
    [7],
    "23:00",
    "07:00",
    "2026-10-18 19:00:00",
    true,
  ],
  // Same-day window on weekdays in New York.
  [
    "workday morning",
    "America/New_York",
    [1, 2, 3, 4, 5],
    "09:00",
    "17:00",
    "2026-10-23 14:00:00",
    true,
  ],
  [
    "workday evening",
    "America/New_York",
    [1, 2, 3, 4, 5],
    "09:00",
    "17:00",
    "2026-10-23 21:00:00",
    false,
  ],
  [
    "saturday",
    "America/New_York",
    [1, 2, 3, 4, 5],
    "09:00",
    "17:00",
    "2026-10-24 14:00:00",
    false,
  ],
  // Daylight saving: the clocks go back in New York on 2026-11-01 at 02:00.
  [
    "fall back: 06:30 EST is still quiet",
    "America/New_York",
    everyDay,
    "23:00",
    "07:00",
    "2026-11-01 11:30:00",
    true,
  ],
  [
    "fall back: 07:00 EST is over",
    "America/New_York",
    everyDay,
    "23:00",
    "07:00",
    "2026-11-01 12:00:00",
    false,
  ],
  [
    "fall back: 06:30 EDT the day before",
    "America/New_York",
    everyDay,
    "23:00",
    "07:00",
    "2026-10-31 10:30:00",
    true,
  ],
  [
    "fall back: 07:00 EDT the day before",
    "America/New_York",
    everyDay,
    "23:00",
    "07:00",
    "2026-10-31 11:00:00",
    false,
  ],
  // Spring forward: 02:00 EST becomes 03:00 EDT on 2026-03-08.
  [
    "spring forward: 01:59 EST",
    "America/New_York",
    everyDay,
    "02:30",
    "03:30",
    "2026-03-08 06:59:00",
    false,
  ],
  [
    "spring forward: 03:00 EDT is inside",
    "America/New_York",
    everyDay,
    "02:30",
    "03:30",
    "2026-03-08 07:00:00",
    true,
  ],
  [
    "spring forward: 03:30 EDT is out",
    "America/New_York",
    everyDay,
    "02:30",
    "03:30",
    "2026-03-08 07:30:00",
    false,
  ],
  // London in summer (BST, +1) and a half-hour zone (Kolkata, +5:30).
  [
    "BST: 23:00",
    "Europe/London",
    everyDay,
    "23:00",
    "07:00",
    "2026-07-01 22:00:00",
    true,
  ],
  [
    "BST: 22:59",
    "Europe/London",
    everyDay,
    "23:00",
    "07:00",
    "2026-07-01 21:59:00",
    false,
  ],
  [
    "Kolkata: 22:00",
    "Asia/Kolkata",
    everyDay,
    "22:00",
    "07:00",
    "2026-10-20 16:30:00",
    true,
  ],
  [
    "Kolkata: 21:59",
    "Asia/Kolkata",
    everyDay,
    "22:00",
    "07:00",
    "2026-10-20 16:29:00",
    false,
  ],
  // Odd settings.
  [
    "equal start and end is empty",
    "UTC",
    everyDay,
    "08:00",
    "08:00",
    "2026-10-20 08:00:00",
    false,
  ],
  [
    "no days is never quiet",
    "UTC",
    [],
    "22:00",
    "07:00",
    "2026-10-20 23:00:00",
    false,
  ],
  [
    "unknown zone counts as UTC",
    "Mars/Base",
    everyDay,
    "22:00",
    "07:00",
    "2026-10-20 23:00:00",
    true,
  ],
  [
    "missing zone counts as UTC",
    null,
    everyDay,
    "22:00",
    "07:00",
    "2026-10-20 12:00:00",
    false,
  ],
  [
    "midnight start",
    "UTC",
    everyDay,
    "00:00",
    "06:00",
    "2026-10-20 00:00:00",
    true,
  ],
  [
    "ends at midnight",
    "UTC",
    everyDay,
    "18:00",
    "00:00",
    "2026-10-20 23:59:00",
    true,
  ],
  [
    "ends at midnight: midnight is out",
    "UTC",
    everyDay,
    "18:00",
    "00:00",
    "2026-10-21 00:00:00",
    false,
  ],
];

for (const [label, zone, days, start, end, at, expected] of vectors) {
  Deno.test(`window: ${label}`, () => {
    assertEquals(
      quietWindowContains(zone, days, start, end, unix(at)),
      expected,
    );
  });
}

Deno.test("window: Postgres time text with seconds works", () => {
  assertEquals(
    quietWindowContains(
      "UTC",
      everyDay,
      "22:00:00",
      "07:00:00",
      unix("2026-10-20 23:00:00"),
    ),
    true,
  );
});

Deno.test("window: a garbage time is never quiet", () => {
  assertEquals(
    quietWindowContains(
      "UTC",
      everyDay,
      "late",
      "07:00",
      unix("2026-10-20 23:00:00"),
    ),
    false,
  );
});

Deno.test("clockSeconds reads HH:MM and HH:MM:SS", () => {
  assertEquals(clockSeconds("07:30"), 7 * 3600 + 30 * 60);
  assertEquals(clockSeconds("23:59:58"), 23 * 3600 + 59 * 60 + 58);
  assertEquals(clockSeconds("24:00"), 0);
  assertEquals(clockSeconds("25:00"), null);
  assertEquals(clockSeconds(""), null);
});

// ----------------------------------------------------------- the filter
const night = unix("2026-10-20 16:00:00"); // 00:00 Wednesday in Shanghai.
const noon = unix("2026-10-20 04:00:00"); // 12:00 Tuesday in Shanghai.

function recipient(
  subscription: string,
  user: string,
  breaksThrough: boolean,
): QuietRecipient {
  return {
    subscription_id: subscription,
    user_id: user,
    time_zone: "Asia/Shanghai",
    quiet_days: everyDay,
    quiet_start: "23:00:00",
    quiet_end: "07:00:00",
    breaks_through: breaksThrough,
  };
}

/// A fake admin client: answers quiet_hours_recipients from [rows] (by
/// message) and records what it was asked.
function fakeAdmin(
  rows: Record<string, QuietRecipient[]>,
  calls: { subscriptions: string[]; message: string | null }[] = [],
  failWith: unknown = null,
): RpcClient {
  return {
    rpc(name, args) {
      if (name !== "quiet_hours_recipients") {
        throw new Error(`unexpected rpc ${name}`);
      }
      const message = (args.target_message_id as string | null) ?? null;
      const subscriptions = args.target_subscription_ids as string[];
      calls.push({ subscriptions, message });
      if (failWith) {
        return Promise.resolve({ data: null, error: failWith });
      }
      const answer = (rows[message ?? ""] ?? []).filter((row) =>
        subscriptions.includes(row.subscription_id)
      );
      return Promise.resolve({ data: answer, error: null });
    },
  };
}

Deno.test("a recipient in quiet hours is dropped, others stay", async () => {
  const admin = fakeAdmin({
    m1: [recipient("s-ada", "ada", false)],
  });
  const kept = await dropQuietPushes(
    admin,
    [{ subscription_id: "s-ada" }, { subscription_id: "s-bob" }],
    night,
    "m1",
  );
  assertEquals(kept.map((t) => t.subscription_id), ["s-bob"]);
});

Deno.test("outside the window nothing is dropped", async () => {
  const admin = fakeAdmin({ m1: [recipient("s-ada", "ada", false)] });
  const kept = await dropQuietPushes(
    admin,
    [{ subscription_id: "s-ada" }],
    noon,
    "m1",
  );
  assertEquals(kept.length, 1);
});

Deno.test("a message that breaks through is kept in quiet hours", async () => {
  const admin = fakeAdmin({ m1: [recipient("s-ada", "ada", true)] });
  const kept = await dropQuietPushes(
    admin,
    [{ subscription_id: "s-ada" }],
    night,
    "m1",
  );
  assertEquals(kept.length, 1);
});

Deno.test("pushes without a message are all held in quiet hours", async () => {
  const calls: { subscriptions: string[]; message: string | null }[] = [];
  const admin = fakeAdmin({ "": [recipient("s-ada", "ada", false)] }, calls);
  const kept = await dropQuietPushes(
    admin,
    [{ subscription_id: "s-ada" }],
    night,
  );
  assertEquals(kept.length, 0);
  assertEquals(calls[0].message, null);
});

Deno.test("each message decides for its own pushes in one tick", async () => {
  // Ada's one subscription gets a plain message and a call in the same
  // tick: the call is pushed, the plain one is not.
  const admin = fakeAdmin({
    plain: [recipient("s-ada", "ada", false)],
    call: [recipient("s-ada", "ada", true)],
  });
  const kept = await dropQuietPushes(
    admin,
    [
      { subscription_id: "s-ada", message_id: "plain" },
      { subscription_id: "s-ada", message_id: "call" },
    ],
    night,
  );
  assertEquals(kept.map((t) => t.message_id), ["call"]);
});

Deno.test("one lookup per message, with only its subscriptions", async () => {
  const calls: { subscriptions: string[]; message: string | null }[] = [];
  const admin = fakeAdmin({}, calls);
  await dropQuietPushes(
    admin,
    [
      { subscription_id: "a", message_id: "m1" },
      { subscription_id: "b", message_id: "m1" },
      { subscription_id: "c", message_id: "m2" },
      { subscription_id: "d" },
    ],
    night,
  );
  assertEquals(calls.length, 3);
  assertEquals(calls[0], { subscriptions: ["a", "b"], message: "m1" });
  assertEquals(calls[1], { subscriptions: ["c"], message: "m2" });
  assertEquals(calls[2], { subscriptions: ["d"], message: null });
});

Deno.test("a failed lookup lets the pushes go out", async () => {
  const admin = fakeAdmin({}, [], { message: "boom" });
  const kept = await dropQuietPushes(
    admin,
    [{ subscription_id: "s-ada" }],
    night,
    "m1",
  );
  assertEquals(kept.length, 1);
});

Deno.test("a lookup that throws lets the pushes go out", async () => {
  const admin: RpcClient = {
    rpc() {
      throw new Error("network");
    },
  };
  const kept = await dropQuietPushes(
    admin,
    [{ subscription_id: "s-ada" }],
    night,
    "m1",
  );
  assertEquals(kept.length, 1);
});

Deno.test("nothing to push means no lookup", async () => {
  const calls: { subscriptions: string[]; message: string | null }[] = [];
  const kept = await dropQuietPushes(fakeAdmin({}, calls), [], night);
  assertEquals(kept, []);
  assertEquals(calls.length, 0);
});

Deno.test("isHeldBack follows the window and the exception", () => {
  assertEquals(isHeldBack(recipient("s", "u", false), night), true);
  assertEquals(isHeldBack(recipient("s", "u", true), night), false);
  assertEquals(isHeldBack(recipient("s", "u", false), noon), false);
});
