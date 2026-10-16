import { assert, assertEquals } from "jsr:@std/assert@1";
import { isAuthorized, targetPath } from "./logic.ts";

const target = {
  subscription_id: "s",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  conversation_id: "c1",
  circle_id: null,
  title: "Ada",
  body: "hi",
};

Deno.test("the shared secret is checked as a bearer token", () => {
  assert(isAuthorized("Bearer s3cret", "s3cret"));
  assert(!isAuthorized("Bearer s3cret!", "s3cret"));
  assert(!isAuthorized("Bearer s3cre", "s3cret"));
  assert(!isAuthorized("s3cret", "s3cret"));
  assert(!isAuthorized(null, "s3cret"));
});

Deno.test("an unset secret never authorizes", () => {
  assert(!isAuthorized("Bearer ", ""));
  assert(!isAuthorized("", ""));
});

Deno.test("notifications open the conversation or the circle channel", () => {
  assertEquals(targetPath(target), "/#/chats/c1");
  assertEquals(
    targetPath({ ...target, circle_id: "k1" }),
    "/#/circles/k1?c=c1",
  );
});
