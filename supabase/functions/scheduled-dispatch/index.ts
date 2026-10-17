// Pushes for things the database does on its own: scheduled messages that
// were sent, reminders that came due, chat events about to start and tasks
// that came due. The same tick removes the files of expired disappearing
// messages.
//
// pg_cron calls public.run_later_dispatch() every minute. That sends what
// is due and, when pushes are waiting, wakes this function through pg_net:
//
//   POST /functions/v1/scheduled-dispatch
//   Authorization: Bearer <DISPATCH_SECRET>
//
// The function claims the waiting pushes with the service role (each is
// claimed once, so a second wake-up or a client's own push request cannot
// ring twice) and delivers them as the push function does. It is deployed
// without JWT verification: the shared secret is the credential.
// Answers 503 push_not_configured until the VAPID keys are set, and 500
// not_configured without DISPATCH_SECRET.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { readVapidKeys, sendWebPush } from "../push/webpush.ts";
import { cleanUpExpired } from "../expire-messages/cleanup.ts";
import {
  type EventReminderRow,
  eventTarget,
  isAuthorized,
  type PushTarget,
  targetPath,
  type TaskReminderRow,
  taskTarget,
} from "./logic.ts";

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
  const secret = Deno.env.get("DISPATCH_SECRET") ?? "";
  if (secret === "") {
    return json({ error: "not_configured" }, 500);
  }
  if (!isAuthorized(request.headers.get("Authorization"), secret)) {
    return json({ error: "unauthorized" }, 401);
  }
  const keys = readVapidKeys((name) => Deno.env.get(name));
  if (!keys) {
    return json({ error: "push_not_configured" }, 503);
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "not_configured" }, 500);
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const targets: PushTarget[] = [];

  // Scheduled messages that went out: push them like a message the sender
  // just sent (claim_push_delivery checks the sender and pushes it once).
  const { data: sent, error: sentError } = await admin.rpc(
    "claim_scheduled_message_pushes",
  );
  if (sentError) {
    return json({ error: "lookup_failed" }, 500);
  }
  for (
    const row of (sent ?? []) as { message_id: string; sender_id: string }[]
  ) {
    const { data } = await admin.rpc("claim_push_delivery", {
      target_message_id: row.message_id,
      caller_id: row.sender_id,
    });
    targets.push(...((data ?? []) as PushTarget[]));
  }

  // Reminders that came due: "Reminder" / "{sender}: {text}".
  const { data: reminders, error: reminderError } = await admin.rpc(
    "claim_reminder_pushes",
  );
  if (reminderError) {
    return json({ error: "lookup_failed" }, 500);
  }
  targets.push(...((reminders ?? []) as PushTarget[]));

  // Chat events about to start (the tick wrote the reminders).
  const { data: events, error: eventsError } = await admin.rpc(
    "claim_chat_event_reminder_pushes",
    { max_reminders: 200 },
  );
  if (eventsError) {
    return json({ error: "lookup_failed" }, 500);
  }
  targets.push(...((events ?? []) as EventReminderRow[]).map(eventTarget));

  // Tasks that came due: writes the inbox entries and hands out the pushes.
  const { data: tasks, error: tasksError } = await admin.rpc(
    "due_list_item_reminders",
  );
  if (tasksError) {
    return json({ error: "lookup_failed" }, 500);
  }
  targets.push(...((tasks ?? []) as TaskReminderRow[]).map(taskTarget));

  // Files of expired disappearing messages. Not a push, but it needs the
  // service role and Storage, so it rides on the same tick.
  try {
    await cleanUpExpired(admin);
  } catch {
    // Tried again on the next tick.
  }

  const gone: string[] = [];
  let delivered = 0;
  await Promise.all(targets.map(async (target) => {
    try {
      const status = await sendWebPush(keys, target, {
        title: target.title,
        body: target.body,
        tag: target.tag ?? target.conversation_id,
        url: targetPath(target),
      }, { nowSeconds: Math.floor(Date.now() / 1000) });
      if (status === 404 || status === 410) {
        gone.push(target.subscription_id);
      } else if (status >= 200 && status < 300) {
        delivered++;
      }
    } catch {
      // One unreachable push service doesn't stop the others.
    }
  }));
  if (gone.length > 0) {
    await admin.rpc("remove_push_subscriptions", { target_ids: gone });
  }
  return json({ sent: delivered, removed: gone.length });
});
