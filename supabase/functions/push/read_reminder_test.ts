// The "please read this" reminder push (A6): {read_reminder_message_id} goes
// through claim_read_reminder_pushes and then through the same quiet hours
// filter as every push, with no message id, so nothing breaks through.
//
//   deno test --allow-read supabase/functions/push/read_reminder_test.ts
import { assert, assertEquals } from "jsr:@std/assert@1";
import { dropQuietPushes, type RpcClient } from "./quiet_hours.ts";

const source = Deno.readTextFileSync(new URL("./index.ts", import.meta.url));

Deno.test("the function claims reminders for the caller only", () => {
  assert(source.includes("body?.read_reminder_message_id"));
  assert(source.includes('admin.rpc("claim_read_reminder_pushes"'));
  assert(source.includes("caller_id: user.id"));
});

Deno.test("a reminder is not a message: quiet hours get no message id", () => {
  assert(
    /isMomentsPush \|\| isTaskPush \|\| isReadReminderPush\s*\? null/.test(
      source,
    ),
  );
});

Deno.test("quiet hours hold a reminder back, with nothing breaking through", async () => {
  const calls: Record<string, unknown>[] = [];
  const admin: RpcClient = {
    rpc(_name, args) {
      calls.push(args);
      // What quiet_hours_recipients answers for a person whose window is on
      // all day: this message id is null, so breaks_through is false.
      return Promise.resolve({
        data: [{
          subscription_id: "sub-1",
          user_id: "user-1",
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
  const targets = [
    { subscription_id: "sub-1" },
    { subscription_id: "sub-2" },
  ];
  const noon = Date.parse("2026-10-21T12:00:00Z") / 1000;
  const audible = await dropQuietPushes(admin, targets, noon, null);
  assertEquals(audible, [{ subscription_id: "sub-2" }]);
  assertEquals(calls[0].target_message_id, null);
});
