import { assertEquals } from "jsr:@std/assert@1";
import { targetPath } from "./logic.ts";
import { digestPushTarget } from "./digest.ts";

const row = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  title: "Your daily digest is ready",
  body: "2 chats have news. Open WeCord to catch up.",
  tag: "ai-digest-1",
  url: "/#/notifications",
};

Deno.test("the digest push opens Notifications and has no chat attached", () => {
  const target = digestPushTarget(row);
  assertEquals(targetPath(target), "/#/notifications");
  assertEquals(target.tag, "ai-digest-1");
  assertEquals(target.conversation_id, null);
  assertEquals(target.circle_id, null);
  assertEquals(target.title, "Your daily digest is ready");
  assertEquals(target.body, "2 chats have news. Open WeCord to catch up.");
});
