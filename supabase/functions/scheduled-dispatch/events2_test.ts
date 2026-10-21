import { assertEquals } from "jsr:@std/assert@1";
import { maskLockedPushes } from "../push/locked_chats.ts";
import { dropQuietPushes, type RpcClient } from "../push/quiet_hours.ts";
import { writeTimesForTargets } from "../push/time_tokens.ts";
import { targetPath } from "./logic.ts";
import { eventNoticeTarget } from "./events2.ts";

const chatRow = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  conversation_id: "conv-1",
  circle_id: null,
  title: "你已报名成功",
  body:
    "有人退出了，你已从候补转为报名成功：「读书会」，<t:1790000000:f> 开始。",
  tag: "event-seat-n1",
  url: "/#/chats/conv-1",
};

Deno.test("a seat push opens the chat of the event, one tag per notice", () => {
  const target = eventNoticeTarget(chatRow);
  assertEquals(targetPath(target), "/#/chats/conv-1");
  assertEquals(target.tag, "event-seat-n1");
  assertEquals(target.conversation_id, "conv-1");
  assertEquals(target.circle_id, null);
});

Deno.test("a circle event's push opens the event in its circle", () => {
  const target = eventNoticeTarget({
    ...chatRow,
    conversation_id: null,
    url: "/#/circles/c1/events?event=e1",
  });
  assertEquals(targetPath(target), "/#/circles/c1/events?event=e1");
  assertEquals(target.conversation_id, null);
});

Deno.test("the push carries the subscription it was claimed for and its words", () => {
  const target = eventNoticeTarget(chatRow);
  assertEquals(target.subscription_id, "s1");
  assertEquals(target.endpoint, "https://push.example.com/x");
  assertEquals(target.p256dh, "k");
  assertEquals(target.auth, "a");
  assertEquals(target.title, "你已报名成功");
});

Deno.test("a locked chat is told without the event's name (G2)", async () => {
  const admin: RpcClient = {
    rpc(name) {
      assertEquals(name, "locked_chat_push_text");
      return Promise.resolve({
        data: [{
          subscription_id: "s1",
          conversation_id: "conv-1",
          title: "WeCord",
          body: "你收到一条新消息",
        }],
        error: null,
      });
    },
  };
  const [masked] = await maskLockedPushes(admin, [eventNoticeTarget(chatRow)]);
  assertEquals(masked.title, "WeCord");
  assertEquals(masked.body, "你收到一条新消息");
  // Tapping still opens the chat.
  assertEquals(targetPath(masked), "/#/chats/conv-1");
});

Deno.test("quiet hours hold the push back, like the other pushes (A4)", async () => {
  // 1790000000 is 2026-09-21 12:53 UTC; the window is 00:00 to 23:59 on that
  // Monday in UTC.
  const admin: RpcClient = {
    rpc(name) {
      assertEquals(name, "quiet_hours_recipients");
      return Promise.resolve({
        data: [{
          subscription_id: "s1",
          user_id: "u1",
          time_zone: "UTC",
          quiet_days: [1, 2, 3, 4, 5, 6, 7],
          quiet_start: "00:00",
          quiet_end: "23:59",
          breaks_through: false,
        }],
        error: null,
      });
    },
  };
  const kept = await dropQuietPushes(
    admin,
    [eventNoticeTarget(chatRow)],
    1790000000,
  );
  assertEquals(kept.length, 0);
});

Deno.test("the start is written in the subscription's own zone and language", async () => {
  const admin = {
    from: (_table: string) => ({
      select: (_columns: string) => ({
        in: (_column: string, _values: string[]) =>
          Promise.resolve({
            data: [{ id: "s1", time_zone: "Pacific/Auckland", language: "zh" }],
            error: null,
          }),
      }),
    }),
  };
  const [ready] = await writeTimesForTargets(
    admin,
    [eventNoticeTarget(chatRow)],
    1789000000,
  );
  assertEquals(ready.body.includes("<t:"), false);
  assertEquals(ready.body.includes("「读书会」"), true);
});
