import { assertEquals } from "jsr:@std/assert@1";
import { targetPath } from "./logic.ts";
import { moderationTarget } from "./moderation.ts";

const alert = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  title: "Raid protection is on",
  body: "Chess club had 8 people join or ask to join in a few minutes.",
  tag: "raid-e1",
  url: "/#/circles/c1",
};

Deno.test("a raid alert opens the circle, an appeal answer opens Notifications", () => {
  const raid = moderationTarget(alert);
  assertEquals(targetPath(raid), "/#/circles/c1");
  assertEquals(raid.tag, "raid-e1");
  assertEquals(raid.conversation_id, null);
  assertEquals(raid.circle_id, null);
  const appeal = moderationTarget({
    ...alert,
    title: "Ban appeal approved",
    tag: "ban-appeal-a1",
    url: "/#/notifications",
  });
  assertEquals(targetPath(appeal), "/#/notifications");
  assertEquals(appeal.title, "Ban appeal approved");
});

Deno.test("the push carries the subscription it was claimed for", () => {
  const target = moderationTarget(alert);
  assertEquals(target.subscription_id, "s1");
  assertEquals(target.endpoint, "https://push.example.com/x");
  assertEquals(target.p256dh, "k");
  assertEquals(target.auth, "a");
});
