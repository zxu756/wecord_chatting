// Event reminders for group chats and direct messages. Called every minute
// by the scheduler with the service role key (verify_jwt is off because the
// caller is not a signed-in user; the key is checked here):
//
//   1. chat_event_due_reminders() writes the inbox rows that are due,
//   2. claim_chat_event_reminder_pushes() hands out the Web Pushes for them,
//   3. each is sent with the same VAPID keys as the push function.
//
// Answers {created, pushed, removed}. See docs/chat-events.md.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { writeTimesForTargets } from "../push/time_tokens.ts";
import { readVapidKeys, sendWebPush } from "../push/webpush.ts";
import {
  isSchedulerToken,
  reminderPayload,
  type ReminderTarget,
} from "./reminders.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "not_configured" }, 500);
  }
  if (!isSchedulerToken(request.headers.get("Authorization"), serviceRoleKey)) {
    return json({ error: "unauthorized" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const due = await admin.rpc("chat_event_due_reminders");
  if (due.error) return json({ error: "due_failed" }, 500);

  // Without VAPID keys nothing is claimed, so the pushes wait for them.
  const keys = readVapidKeys((name) => Deno.env.get(name));
  if (!keys) {
    return json({ created: due.data ?? 0, pushed: 0, removed: 0 });
  }

  const claimed = await admin.rpc("claim_chat_event_reminder_pushes", {
    max_reminders: 200,
  });
  if (claimed.error) return json({ error: "claim_failed" }, 500);

  // Times in an event's title are written for each subscriber's zone.
  const targets = await writeTimesForTargets(
    admin,
    (claimed.data ?? []) as ReminderTarget[],
    Math.floor(Date.now() / 1000),
  );
  const gone: string[] = [];
  let pushed = 0;
  await Promise.all(targets.map(async (target) => {
    try {
      const status = await sendWebPush(keys, target, reminderPayload(target), {
        nowSeconds: Math.floor(Date.now() / 1000),
        // A reminder that arrives after the event started is no use.
        ttlSeconds: 15 * 60,
      });
      if (status === 404 || status === 410) {
        gone.push(target.subscription_id);
      } else if (status >= 200 && status < 300) {
        pushed++;
      }
    } catch {
      // One unreachable push service doesn't stop the others.
    }
  }));
  if (gone.length > 0) {
    await admin.rpc("remove_push_subscriptions", { target_ids: gone });
  }
  return json({ created: due.data ?? 0, pushed, removed: gone.length });
});
