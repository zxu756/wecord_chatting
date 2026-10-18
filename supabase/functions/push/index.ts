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
// All answer 503 push_not_configured until VAPID_PUBLIC_KEY and
// VAPID_PRIVATE_KEY (and optionally VAPID_SUBJECT) are set.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { dropQuietPushes } from "./quiet_hours.ts";
import { writeTimesForTargets } from "./time_tokens.ts";
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
  try {
    const body = await request.json();
    messageId = body?.message_id;
    callId = body?.call_id;
    taskItemId = body?.task_item_id;
    momentsPostId = body?.moments_post_id;
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
  if (
    !isMomentsPush && !isTaskPush && typeof callId === "string" &&
    uuidPattern.test(callId)
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
    !isMomentsPush && !isTaskPush &&
    (typeof messageId !== "string" || !uuidPattern.test(messageId))
  ) {
    return json({ error: "invalid_message" }, 400);
  }
  // Checks the caller sent it and claims it, so it is pushed only once.
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
    : await admin.rpc("claim_push_delivery", {
      target_message_id: messageId,
      caller_id: user.id,
    });
  if (error) {
    return json({ error: "lookup_failed" }, 500);
  }

  // Quiet hours hold back what is not for the recipient's exceptions (the
  // inbox is written elsewhere and does not depend on this).
  const audible = await dropQuietPushes(
    admin,
    (data ?? []) as PushTarget[],
    Math.floor(Date.now() / 1000),
    isMomentsPush || isTaskPush ? null : (messageId as string),
  );
  // Times in the text are written for each subscriber's zone and language.
  const targets = await writeTimesForTargets(
    admin,
    audible,
    Math.floor(Date.now() / 1000),
  );
  const gone: string[] = [];
  let sent = 0;
  await Promise.all(targets.map(async (target) => {
    try {
      const status = await sendWebPush(keys, target, {
        title: target.title,
        body: target.body,
        tag: target.tag ?? target.conversation_id ?? undefined,
        url: targetPath(target),
      }, { nowSeconds: Math.floor(Date.now() / 1000) });
      if (status === 404 || status === 410) {
        gone.push(target.subscription_id);
      } else if (status >= 200 && status < 300) {
        sent++;
      }
    } catch {
      // One unreachable push service doesn't stop the others.
    }
  }));
  if (gone.length > 0) {
    await admin.rpc("remove_push_subscriptions", { target_ids: gone });
  }
  return json({ sent, removed: gone.length });
});
