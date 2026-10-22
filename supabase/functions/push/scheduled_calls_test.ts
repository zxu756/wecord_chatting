// Scheduled calls (roadmap E2): the reminder of an event with a call opens the
// call, through both senders (scheduled-dispatch and chat-event-reminders),
// except in a chat the person locked (G2). The calendar feed writes the call
// link only for a person who asked for details.
//
//   deno test --allow-read supabase/functions/push/scheduled_calls_test.ts
import {
  assert,
  assertEquals,
  assertFalse,
  assertStringIncludes,
} from "jsr:@std/assert@1";
import { buildFeed, type FeedItem } from "../calendar-feed/feed.ts";
import {
  reminderPath,
  reminderPayload,
  type ReminderTarget,
} from "../chat-event-reminders/reminders.ts";
import { eventTarget, targetPath } from "../scheduled-dispatch/logic.ts";
import { callPath, isCallPath } from "./call_path.ts";
import { maskLockedPushes } from "./locked_chats.ts";
import type { RpcClient } from "./quiet_hours.ts";

const code = "abcdefghjk23";

const row = {
  reminder_id: "r-1",
  subscription_id: "s-1",
  endpoint: "https://push.example/abc",
  p256dh: "p",
  auth: "a",
  conversation_id: "c-1",
  event_id: "e-1",
  title: "Thursday sync",
  body: "Starts in 10 minutes · Tap to join the call",
};

Deno.test("a call link code becomes the path the app opens", () => {
  assertEquals(callPath(code), "/#/call/abcdefghjk23");
  assert(isCallPath("/#/call/abcdefghjk23"));
  assertFalse(isCallPath("/#/chats/c-1"));
  assertFalse(isCallPath(undefined));
});

Deno.test("a code that is not a call link code makes no path", () => {
  assertEquals(callPath(null), null);
  assertEquals(callPath(undefined), null);
  assertEquals(callPath(""), null);
  assertEquals(callPath("short"), null);
  assertEquals(callPath("ABCDEFGHJK23"), null);
  assertEquals(callPath("abcdefghjk2/"), null);
  assertEquals(callPath("../../admin12"), null);
});

Deno.test("scheduled-dispatch: the reminder of an event with a call opens it", () => {
  const withCall = eventTarget({ ...row, call_link_code: code });
  assertEquals(targetPath(withCall), "/#/call/abcdefghjk23");
  assertEquals(withCall.title, "📅 Thursday sync");
  assertEquals(withCall.tag, "event-e-1");
  // The chat is still on the target, so a locked chat can be masked.
  assertEquals(withCall.conversation_id, "c-1");
});

Deno.test("scheduled-dispatch: without a call, or an early reminder, it opens the chat", () => {
  assertEquals(
    targetPath(eventTarget({ ...row, call_link_code: null })),
    "/#/chats/c-1",
  );
  assertEquals(targetPath(eventTarget(row)), "/#/chats/c-1");
  assertEquals(
    targetPath(eventTarget({ ...row, call_link_code: "nonsense" })),
    "/#/chats/c-1",
  );
});

Deno.test("chat-event-reminders: the same", () => {
  const withCall: ReminderTarget = { ...row, call_link_code: code };
  assertEquals(reminderPath(withCall), "/#/call/abcdefghjk23");
  assertEquals(reminderPayload(withCall).url, "/#/call/abcdefghjk23");
  assertEquals(reminderPayload(withCall).tag, "event-e-1");
  assertEquals(reminderPath(row), "/#/chats/c-1");
  assertEquals(reminderPath({ ...row, call_link_code: null }), "/#/chats/c-1");
});

function lockedClient(): RpcClient {
  return {
    rpc: () =>
      Promise.resolve({
        data: [{
          subscription_id: "s-1",
          conversation_id: "c-1",
          title: "WeCord",
          body: "You have a new message",
        }],
        error: null,
      }),
  };
}

Deno.test("a locked chat's reminder opens the chat, not the call, and says nothing of it", async () => {
  const [dispatch] = await maskLockedPushes(lockedClient(), [
    eventTarget({ ...row, call_link_code: code }),
  ]);
  assertEquals(dispatch.title, "WeCord");
  assertEquals(dispatch.body, "You have a new message");
  assertEquals(targetPath(dispatch), "/#/chats/c-1");

  const [single] = await maskLockedPushes(lockedClient(), [
    { ...row, call_link_code: code } as ReminderTarget,
  ]);
  assertEquals(reminderPath(single), "/#/chats/c-1");
  assertEquals(single.call_link_code, null);
  assertFalse(JSON.stringify(single).includes(code));
});

Deno.test("when the lock lookup fails, the call link is still not given away", async () => {
  const failing: RpcClient = {
    rpc: () => Promise.resolve({ data: null, error: { message: "down" } }),
  };
  const [out] = await maskLockedPushes(failing, [
    eventTarget({ ...row, call_link_code: code }),
  ]);
  assertEquals(targetPath(out), "/#/chats/c-1");
  assertFalse(out.body.includes("Thursday"));
});

Deno.test("an unlocked chat's reminder keeps the call", async () => {
  const unlocked: RpcClient = {
    rpc: () => Promise.resolve({ data: [], error: null }),
  };
  const [out] = await maskLockedPushes(unlocked, [
    eventTarget({ ...row, call_link_code: code }),
  ]);
  assertEquals(targetPath(out), "/#/call/abcdefghjk23");
});

// ----------------------------------------------------- the calendar feed

const now = new Date("2026-10-20T08:00:00Z");

function feedItem(partial: Partial<FeedItem>): FeedItem {
  return {
    kind: "chat_event",
    title: "Thursday sync",
    starts_at: "2026-10-22T18:00:00+00:00",
    ends_at: "2026-10-22T19:00:00+00:00",
    all_day: false,
    conversation_id: "c-1",
    circle_id: null,
    target_id: "e-1",
    place_name: "Hike crew",
    subtitle: null,
    meta: { call_link_code: code },
    ...partial,
  };
}

function feedOf(
  items: FeedItem[],
  includeContent: boolean,
  site?: string,
): string {
  return buildFeed(
    {
      status: "ok",
      include_content: includeContent,
      utc_offset_minutes: 0,
      language: "en",
      items,
    },
    now,
    site,
  );
}

Deno.test("the calendar entry of a call has its link when details are on", () => {
  // Long lines are folded in the file; a calendar app reads them unfolded.
  const feed = feedOf([feedItem({})], true).replaceAll("\r\n ", "");
  assertStringIncludes(
    feed,
    "URL:https://wecord.jokebear.fyi/call/abcdefghjk23",
  );
  assertStringIncludes(
    feed,
    "DESCRIPTION:Hike crew\\nJoin the call: https://wecord.jokebear.fyi/call/abcdefghjk23",
  );
});

Deno.test("in Chinese the line says so", () => {
  const feed = buildFeed(
    {
      status: "ok",
      include_content: true,
      utc_offset_minutes: 0,
      language: "zh",
      items: [feedItem({})],
    },
    now,
  );
  assertStringIncludes(feed, "加入通话: https://wecord.jokebear.fyi/call/");
});

Deno.test("the site of the link is the one the function is told", () => {
  const feed = feedOf([feedItem({})], true, "https://staging.example.com");
  assertStringIncludes(
    feed,
    "URL:https://staging.example.com/call/abcdefghjk23",
  );
});

Deno.test("without details the feed says nothing of the call", () => {
  const feed = feedOf([feedItem({})], false);
  assertFalse(feed.includes(code));
  assertFalse(feed.includes("URL:"));
  assertFalse(feed.includes("call/"));
  assertFalse(feed.includes("Thursday"));
});

Deno.test("an entry without a call, or with a bad code, has no link", () => {
  for (
    const meta of [
      undefined,
      null,
      {},
      { call_link_code: null },
      { call_link_code: "../x" },
      { call_link_code: "ABCDEFGHJK23" },
    ]
  ) {
    const feed = feedOf([feedItem({ meta })], true);
    assertFalse(feed.includes("URL:"), JSON.stringify(meta));
    assertFalse(feed.includes("Join the call"), JSON.stringify(meta));
  }
});

Deno.test("a task never gets a call link", () => {
  const feed = feedOf([feedItem({ kind: "task" })], true);
  assertFalse(feed.includes("URL:"));
});
