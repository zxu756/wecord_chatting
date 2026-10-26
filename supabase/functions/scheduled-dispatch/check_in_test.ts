import { assertEquals } from "jsr:@std/assert@1";
import { maskLockedPushes } from "../push/locked_chats.ts";
import { dropQuietPushes, type RpcClient } from "../push/quiet_hours.ts";
import { targetPath } from "./logic.ts";
import { checkInTarget } from "./check_in.ts";

const row = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  conversation_id: "conv-1",
  circle_id: null,
  title: "今天还没打卡",
  body: "「每天读书」今天还没打卡，已连续 7 天，别断了。",
  tag: "check-in-n1",
  url: "/#/chats/conv-1",
};

Deno.test("a check-in reminder opens the chat, one tag per notice", () => {
  const target = checkInTarget(row);
  assertEquals(targetPath(target), "/#/chats/conv-1");
  assertEquals(target.tag, "check-in-n1");
  assertEquals(target.conversation_id, "conv-1");
  assertEquals(target.circle_id, null);
});

Deno.test("a channel's reminder carries its circle for the mute settings", () => {
  const target = checkInTarget({ ...row, circle_id: "circle-1" });
  assertEquals(target.circle_id, "circle-1");
});

Deno.test("the push carries the subscription it was claimed for and its words", () => {
  const target = checkInTarget(row);
  assertEquals(target.subscription_id, "s1");
  assertEquals(target.endpoint, "https://push.example.com/x");
  assertEquals(target.p256dh, "k");
  assertEquals(target.auth, "a");
  assertEquals(target.title, "今天还没打卡");
  assertEquals(target.body.includes("已连续 7 天"), true);
});

Deno.test("a locked chat is told without the check-in's name (G2)", async () => {
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
  const [masked] = await maskLockedPushes(admin, [checkInTarget(row)]);
  assertEquals(masked.title, "WeCord");
  assertEquals(masked.body, "你收到一条新消息");
  // Tapping still opens the chat.
  assertEquals(targetPath(masked), "/#/chats/conv-1");
});

Deno.test("quiet hours hold the reminder back, like the other pushes (A4)", async () => {
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
  const kept = await dropQuietPushes(admin, [checkInTarget(row)], 1790000000);
  assertEquals(kept.length, 0);
});
