import { assertEquals } from "jsr:@std/assert@1";
import { targetPath } from "./logic.ts";
import { birthdayTarget } from "./birthdays.ts";

const row = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  title: "🎂 It's Ada's birthday today",
  body: "Open WeCord and send a birthday wish.",
  tag: "birthday-f1-2026",
  url: "/#/notifications",
};

Deno.test("a birthday push opens Notifications and has one tag a year", () => {
  const target = birthdayTarget(row);
  assertEquals(targetPath(target), "/#/notifications");
  assertEquals(target.tag, "birthday-f1-2026");
  assertEquals(target.conversation_id, null);
  assertEquals(target.circle_id, null);
  assertEquals(target.title, row.title);
  assertEquals(target.body, row.body);
});

Deno.test("the subscription's own keys are kept", () => {
  const target = birthdayTarget(row);
  assertEquals(target.subscription_id, "s1");
  assertEquals(target.endpoint, "https://push.example.com/x");
  assertEquals(target.p256dh, "k");
  assertEquals(target.auth, "a");
});
