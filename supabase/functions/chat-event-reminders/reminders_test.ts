import { assertEquals } from "jsr:@std/assert@1";
import {
  isSchedulerToken,
  reminderPath,
  reminderPayload,
  type ReminderTarget,
} from "./reminders.ts";

const target: ReminderTarget = {
  reminder_id: "r-1",
  subscription_id: "s-1",
  endpoint: "https://push.example/abc",
  p256dh: "p",
  auth: "a",
  conversation_id: "c-1",
  event_id: "e-1",
  title: "Bouldering night",
  body: "Starts in 15 minutes",
};

Deno.test("the push names the event and opens its chat", () => {
  assertEquals(reminderPath(target), "/#/chats/c-1");
  assertEquals(reminderPayload(target), {
    title: "📅 Bouldering night",
    body: "Starts in 15 minutes",
    tag: "event-e-1",
    url: "/#/chats/c-1",
  });
});

Deno.test("reminders for one event share a tag so the newer replaces the older", () => {
  const hour = reminderPayload({ ...target, reminder_id: "r-0", body: "Starts in about 1 hour" });
  assertEquals(hour.tag, reminderPayload(target).tag);
});

Deno.test("only the service role key may call it", () => {
  assertEquals(isSchedulerToken("Bearer secret", "secret"), true);
  assertEquals(isSchedulerToken("bearer secret", "secret"), true);
  assertEquals(isSchedulerToken("Bearer other", "secret"), false);
  assertEquals(isSchedulerToken("secret", "secret"), false);
  assertEquals(isSchedulerToken(null, "secret"), false);
  assertEquals(isSchedulerToken("Bearer secret", undefined), false);
  assertEquals(isSchedulerToken("Bearer ", ""), false);
});
