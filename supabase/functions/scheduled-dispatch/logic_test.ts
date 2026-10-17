import { assert, assertEquals } from "jsr:@std/assert@1";
import { eventTarget, isAuthorized, targetPath, taskTarget } from "./logic.ts";

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

Deno.test("event and task reminders become pushes with their own tags", () => {
  const event = eventTarget({
    reminder_id: "r1",
    subscription_id: "s",
    endpoint: "https://push.example.com/x",
    p256dh: "k",
    auth: "a",
    conversation_id: "c1",
    event_id: "e1",
    title: "Picnic",
    body: "Starts in 15 minutes",
  });
  assertEquals(event.title, "📅 Picnic");
  assertEquals(event.tag, "event-e1");
  assertEquals(targetPath(event), "/#/chats/c1");

  const task = taskTarget({
    notification_id: "n1",
    user_id: "u1",
    subscription_id: "s",
    endpoint: "https://push.example.com/x",
    p256dh: "k",
    auth: "a",
    conversation_id: "c2",
    circle_id: "o1",
    title: "Task due soon",
    body: "Book the tent",
  });
  assertEquals(task.tag, "task-n1");
  assertEquals(task.body, "Book the tent");
  assertEquals(targetPath(task), "/#/circles/o1?c=c2");
});
