import { assertEquals } from "jsr:@std/assert@1";
import { targetPath } from "./logic.ts";
import { titleTarget } from "./titles.ts";

const row = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  title: "你有新头衔了",
  body: "「Hikers」给你设了头衔「Scout」。",
  tag: "title-n1",
  url: "/#/circles/c1",
};

Deno.test("a title push opens the circle, with one tag per notice", () => {
  const target = titleTarget(row);
  assertEquals(targetPath(target), "/#/circles/c1");
  assertEquals(target.tag, "title-n1");
  assertEquals(target.conversation_id, null);
  assertEquals(target.circle_id, null);
});

Deno.test("the push carries the subscription it was claimed for and its words", () => {
  const target = titleTarget(row);
  assertEquals(target.subscription_id, "s1");
  assertEquals(target.endpoint, "https://push.example.com/x");
  assertEquals(target.p256dh, "k");
  assertEquals(target.auth, "a");
  assertEquals(target.title, "你有新头衔了");
  assertEquals(target.body, "「Hikers」给你设了头衔「Scout」。");
});
