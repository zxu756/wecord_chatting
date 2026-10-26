import { assertEquals } from "jsr:@std/assert@1";
import { targetPath } from "./logic.ts";
import { featuredPostTarget } from "./featured_posts.ts";

const row = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  title: "你的帖子被设为精华",
  body: "「摄影圈」的版主把你的帖子「湖边旅行」设为了精华。",
  tag: "featured-p1",
  url: "/#/circles/c1/posts/p1",
};

Deno.test("a featured post push opens the post, with one tag per post", () => {
  const target = featuredPostTarget(row);
  assertEquals(targetPath(target), "/#/circles/c1/posts/p1");
  assertEquals(target.tag, "featured-p1");
});

Deno.test("it belongs to no chat, so there is nothing to lock", () => {
  const target = featuredPostTarget(row);
  assertEquals(target.conversation_id, null);
  assertEquals(target.circle_id, null);
});

Deno.test("the push carries the subscription it was claimed for and its words", () => {
  const target = featuredPostTarget(row);
  assertEquals(target.subscription_id, "s1");
  assertEquals(target.endpoint, "https://push.example.com/x");
  assertEquals(target.p256dh, "k");
  assertEquals(target.auth, "a");
  assertEquals(target.title, "你的帖子被设为精华");
  assertEquals(
    target.body,
    "「摄影圈」的版主把你的帖子「湖边旅行」设为了精华。",
  );
});
