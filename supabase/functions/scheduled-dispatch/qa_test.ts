import { assertEquals } from "jsr:@std/assert@1";
import { targetPath } from "./logic.ts";
import { qaTarget } from "./qa.ts";

const row = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  title: "你的回答被采纳了",
  body: "「摄影圈」的问题「怎么对焦」采纳了你的回答。",
  tag: "qa-n1",
  url: "/#/circles/c1/channels/t1",
};

Deno.test("a Q&A push opens the post, with one tag per notice", () => {
  const target = qaTarget(row);
  assertEquals(targetPath(target), "/#/circles/c1/channels/t1");
  assertEquals(target.tag, "qa-n1");
  assertEquals(target.conversation_id, null);
  assertEquals(target.circle_id, null);
});

Deno.test("the push carries the subscription it was claimed for and its words", () => {
  const target = qaTarget(row);
  assertEquals(target.subscription_id, "s1");
  assertEquals(target.endpoint, "https://push.example.com/x");
  assertEquals(target.p256dh, "k");
  assertEquals(target.auth, "a");
  assertEquals(target.title, "你的回答被采纳了");
  assertEquals(target.body, "「摄影圈」的问题「怎么对焦」采纳了你的回答。");
});
