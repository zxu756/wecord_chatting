// Web push for WeCord.
//
// GET  → {public_key}: the VAPID key browsers subscribe with.
// POST {message_id} → pushes a message the caller just sent to everyone
//      who should hear about it (see claim_push_delivery), at most once.
// POST {call_id} → the same for the "started a call" notice of a call the
//      caller started, so the others' devices ring.
// POST {task_item_id} → the same for the assignments the caller just made on
//      a list item (see claim_task_assignment_push).
// POST {moments_post_id} → the same for the likes, comments and replies the
//      caller just made on a Moment (see claim_moments_pushes). Moments the
//      caller did nothing on claim nothing.
// POST {read_reminder_message_id} → the same for the "please read this"
//      reminder the caller just sent to the members who have not read their
//      message (see claim_read_reminder_pushes). Quiet hours hold it back
//      like any push; nothing breaks through for it.
// All answer 503 push_not_configured until VAPID_PUBLIC_KEY and
// VAPID_PRIVATE_KEY (and optionally VAPID_SUBJECT) are set.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  claimPushBatches,
  forEachLimited,
  SEND_CONCURRENCY,
} from "./claim_pages.ts";
import { maskLockedPushes } from "./locked_chats.ts";
import { dropQuietPushes } from "./quiet_hours.ts";
import { dropSilentPushes } from "./silent_messages.ts";
import { writeTimesForTargets } from "./time_tokens.ts";
import { newTally, recordPushOutcome, tallyPush } from "./outcome.ts";
import { readVapidKeys, sendWebPush } from "./webpush.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface PushTarget {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  conversation_id: string | null;
  circle_id: string | null;
  title: string;
  body: string;
  /// Notifications with the same tag replace each other (Moments: one per
  /// post); the conversation by default.
  tag?: string;
  /// Where tapping opens the app, when it is not a chat (Moments).
  url?: string;
}

/// Where tapping the notification opens the app (hash routes on the web).
export function targetPath(target: PushTarget): string {
  if (target.url) {
    return target.url;
  }
  return target.circle_id
    ? `/#/circles/${target.circle_id}?c=${target.conversation_id}`
    : `/#/chats/${target.conversation_id}`;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const keys = readVapidKeys((name) => Deno.env.get(name));
  if (request.method === "GET") {
    return keys
      ? json({ public_key: keys.publicKey })
      : json({ error: "push_not_configured" }, 503);
  }
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "not_configured" }, 500);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (token === "" || token === authorization) {
    return json({ error: "unauthorized" }, 401);
  }
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(
    token,
  );
  const user = userData?.user;
  if (userError || !user) {
    return json({ error: "unauthorized" }, 401);
  }

  let messageId: unknown;
  let callId: unknown;
  let taskItemId: unknown;
  let momentsPostId: unknown;
  let readReminderMessageId: unknown;
  try {
    const body = await request.json();
    messageId = body?.message_id;
    callId = body?.call_id;
    taskItemId = body?.task_item_id;
    momentsPostId = body?.moments_post_id;
    readReminderMessageId = body?.read_reminder_message_id;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!keys) {
    return json({ error: "push_not_configured" }, 503);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const isMomentsPush = typeof momentsPostId === "string" &&
    uuidPattern.test(momentsPostId);
  const isTaskPush = !isMomentsPush && typeof taskItemId === "string" &&
    uuidPattern.test(taskItemId);
  const isReadReminderPush = !isMomentsPush && !isTaskPush &&
    typeof readReminderMessageId === "string" &&
    uuidPattern.test(readReminderMessageId);
  if (
    !isMomentsPush && !isTaskPush && !isReadReminderPush &&
    typeof callId === "string" && uuidPattern.test(callId)
  ) {
    // claim_push_delivery checks the notice was sent by the caller.
    const { data: call } = await admin
      .from("direct_calls")
      .select("system_message_id")
      .eq("id", callId)
      .maybeSingle();
    messageId = call?.system_message_id;
  }
  if (
    !isMomentsPush && !isTaskPush && !isReadReminderPush &&
    (typeof messageId !== "string" || !uuidPattern.test(messageId))
  ) {
    return json({ error: "invalid_message" }, 400);
  }
  const isChatPush = !isMomentsPush && !isTaskPush && !isReadReminderPush;
  // A reminder, a task or a Moment is not a message: no message id for the
  // silent and quiet-hours checks.
  const silentKey = isMomentsPush || isTaskPush || isReadReminderPush
    ? null
    : (messageId as string);
  const gone: string[] = [];
  let sent = 0;
  // How it went, as three numbers for the monitoring (K3).
  const tally = newTally();

  // Tells the people of one batch of claimed rows: the checks, then the
  // devices, a few dozen at a time.
  const deliver = async (rows: PushTarget[]) => {
    // A message sent silently is told to nobody (it is still in the chats).
    const claimed = await dropSilentPushes(admin, rows, silentKey);
    // Quiet hours hold back what is not for the recipient's exceptions (the
    // inbox is written elsewhere and does not depend on this).
    const audible = await dropQuietPushes(
      admin,
      claimed,
      Math.floor(Date.now() / 1000),
      silentKey,
    );
    // A chat the subscriber locked is told without its words (G2).
    const unrevealing = await maskLockedPushes(admin, audible);
    // Times in the text are written for each subscriber's zone and language.
    const targets = await writeTimesForTargets(
      admin,
      unrevealing,
      Math.floor(Date.now() / 1000),
    );
    const goneHere: string[] = [];
    await forEachLimited(targets, SEND_CONCURRENCY, async (target) => {
      try {
        const status = await sendWebPush(keys, target, {
          title: target.title,
          body: target.body,
          tag: target.tag ?? target.conversation_id ?? undefined,
          url: targetPath(target),
        }, { nowSeconds: Math.floor(Date.now() / 1000) });
        tallyPush(tally, status);
        if (status === 404 || status === 410) {
          goneHere.push(target.subscription_id);
        } else if (status >= 200 && status < 300) {
          sent++;
        }
      } catch {
        // One unreachable push service doesn't stop the others.
        tallyPush(tally, null);
      }
    });
    if (goneHere.length > 0) {
      await admin.rpc("remove_push_subscriptions", { target_ids: goneHere });
      gone.push(...goneHere);
    }
  };

  // Checks the caller sent it and claims it, so it is pushed only once. A
  // chat message comes in batches of people (a big group has thousands of
  // devices); the others are small.
  if (isChatPush) {
    const { error: claimError, batches } = await claimPushBatches<
      PushTarget & { recipient_id?: string | null }
    >(
      admin,
      messageId as string,
      user.id,
      deliver,
    );
    if (claimError) {
      if (batches === 0) {
        return json({ error: "lookup_failed" }, 500);
      }
      // Some batches went out; the rest are not retried (the message is
      // claimed), so say so in the log.
      console.error("claim_push_delivery stopped", claimError);
    }
  } else {
    const { data, error } = isMomentsPush
      ? await admin.rpc("claim_moments_pushes", {
        caller_id: user.id,
        target_post_id: momentsPostId,
      })
      : isTaskPush
      ? await admin.rpc("claim_task_assignment_push", {
        target_item_id: taskItemId,
        caller_id: user.id,
      })
      : await admin.rpc("claim_read_reminder_pushes", {
        target_message_id: readReminderMessageId,
        caller_id: user.id,
      });
    if (error) {
      return json({ error: "lookup_failed" }, 500);
    }
    await deliver((data ?? []) as PushTarget[]);
  }
  await recordPushOutcome(admin, tally);
  return json({ sent, removed: gone.length });
});
