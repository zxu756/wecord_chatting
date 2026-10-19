import { assertEquals } from "jsr:@std/assert@1";
import { dropQuietPushes } from "../push/quiet_hours.ts";
import { targetPath } from "./logic.ts";
import { announcementTarget } from "./announcements.ts";

const row = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  title: "Maintenance tonight",
  body: "We pause at 22:00.",
  tag: "announcement-n1",
  url: "/#/notifications",
};

Deno.test("an official notice opens Notifications, one tag per notice", () => {
  const target = announcementTarget(row);
  assertEquals(targetPath(target), "/#/notifications");
  assertEquals(target.tag, "announcement-n1");
  assertEquals(target.conversation_id, null);
  assertEquals(target.circle_id, null);
  assertEquals(target.title, "Maintenance tonight");
  assertEquals(target.message_id, undefined);
});

Deno.test("quiet hours hold a notice back: it is not about a message, so nothing breaks through", async () => {
  // 2026-10-24 12:00 UTC is a Saturday; the window is on, all day long.
  const unix = Date.UTC(2026, 9, 24, 12, 0, 0) / 1000;
  const asked: Record<string, unknown>[] = [];
  const admin = {
    rpc(name: string, args: Record<string, unknown>) {
      asked.push({ name, ...args });
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
  const other = announcementTarget({ ...row, subscription_id: "s2" });
  const kept = await dropQuietPushes(
    admin,
    [announcementTarget(row), other],
    unix,
  );
  // s1 has quiet hours on and is held back; s2 has none and is pushed.
  assertEquals(kept.map((target) => target.subscription_id), ["s2"]);
  // The lookup was for no message.
  assertEquals(asked[0]["target_message_id"], null);
});
