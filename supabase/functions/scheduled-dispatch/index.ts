// Pushes for things the database does on its own: scheduled messages that
// were sent, messages the AI guard released, reminders that came due, chat
// events about to start, tasks that came due, likes and comments on
// Moments, new-login alerts, answers to circle join requests, the one push of
// an official notice, friends' birthdays (at 9 in the morning of the
// recipient's device), urgent messages (with their one second push) and
// "please confirm the announcement" and the alerts of the monitoring (K3). The same
// tick removes the files of expired disappearing messages.
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
import { newTally, recordPushOutcome, tallyPush } from "../push/outcome.ts";
import { maskLockedPushes } from "../push/locked_chats.ts";
import { dropSilentPushes } from "../push/silent_messages.ts";
import { writeTimesForTargets } from "../push/time_tokens.ts";
import { readVapidKeys, sendWebPush } from "../push/webpush.ts";
import { cleanUpExpired } from "../expire-messages/cleanup.ts";
import {
  type EventReminderRow,
  eventTarget,
  isAuthorized,
  type MomentsPushRow,
  momentsTarget,
  type PushTarget,
  targetPath,
  type TaskReminderRow,
  taskTarget,
} from "./logic.ts";
import {
  type AnnouncementPushRow,
  announcementTarget,
} from "./announcements.ts";
import { type DigestPushRow, digestPushTarget } from "./digest.ts";
import { type BirthdayPushRow, birthdayTarget } from "./birthdays.ts";
import { type JoinRequestPushRow, joinRequestTarget } from "./join_requests.ts";
import { type ModerationPushRow, moderationTarget } from "./moderation.ts";
import { type TitlePushRow, titleTarget } from "./titles.ts";
import { type QaPushRow, qaTarget } from "./qa.ts";
import { type OpsAlertPushRow, opsAlertTarget } from "./ops_alerts.ts";
import { type SecurityPushRow, securityTarget } from "./security.ts";
import {
  audibleTargets,
  type UrgentPushRow,
  urgentRowTarget,
} from "./urgent.ts";

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
    targets.push(
      ...((data ?? []) as PushTarget[]).map((target) => ({
        ...target,
        message_id: row.message_id,
      })),
    );
  }

  // Messages the AI guard released (allowed, not checked, flagged in flag
  // mode, or approved by a moderator): they were held back from everyone,
  // so nobody has been told yet. Pushed like a message the sender just sent.
  const { data: released, error: releasedError } = await admin.rpc(
    "claim_released_message_pushes",
  );
  if (releasedError) {
    // Not fatal: the other pushes still go out (and the releases are
    // claimed again on the next wake-up).
    console.error(
      "claim_released_message_pushes failed",
      releasedError.message,
    );
  }
  for (
    const row of (released ?? []) as { message_id: string; sender_id: string }[]
  ) {
    const { data } = await admin.rpc("claim_push_delivery", {
      target_message_id: row.message_id,
      caller_id: row.sender_id,
    });
    targets.push(
      ...((data ?? []) as PushTarget[]).map((target) => ({
        ...target,
        message_id: row.message_id,
      })),
    );
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

  // Likes, comments and replies on Moments nobody has pushed yet (the
  // actor's app asks for its own right away; this catches the rest).
  const { data: moments, error: momentsError } = await admin.rpc(
    "claim_moments_pushes",
  );
  if (momentsError) {
    // Not fatal: the other pushes still go out (the notifications are
    // claimed again on the next wake-up).
    console.error("claim_moments_pushes failed", momentsError.message);
  }
  targets.push(...((moments ?? []) as MomentsPushRow[]).map(momentsTarget));

  // New-login alerts: "New sign-in to your account", to the user's other
  // devices (the login wakes this function through wake_scheduled_dispatch).
  const { data: security, error: securityError } = await admin.rpc(
    "claim_security_alert_pushes",
  );
  if (securityError) {
    // Not fatal: the other pushes still go out.
    console.error("claim_security_alert_pushes failed", securityError.message);
  }
  targets.push(...((security ?? []) as SecurityPushRow[]).map(securityTarget));

  // Answers to circle join requests ("approved" / "declined"), to the
  // applicant's devices (decide_join_request wakes this function).
  const { data: joinAnswers, error: joinAnswersError } = await admin.rpc(
    "claim_join_request_pushes",
  );
  if (joinAnswersError) {
    // Not fatal: the other pushes still go out.
    console.error("claim_join_request_pushes failed", joinAnswersError.message);
  }
  targets.push(
    ...((joinAnswers ?? []) as JoinRequestPushRow[]).map(joinRequestTarget),
  );

  // Raid protection locked a circle by itself (to its moderators), and the
  // answer to a ban appeal (to the person who appealed): decide_ban_appeal
  // and the raid check wake this function.
  const { data: moderation, error: moderationError } = await admin.rpc(
    "claim_moderation_pushes",
  );
  if (moderationError) {
    // Not fatal: the other pushes still go out.
    console.error("claim_moderation_pushes failed", moderationError.message);
  }
  targets.push(
    ...((moderation ?? []) as ModerationPushRow[]).map(moderationTarget),
  );

  // "<circle> gave you the title X" (C7): set_circle_member_title wakes this
  // function.
  const { data: titles, error: titlesError } = await admin.rpc(
    "claim_circle_title_pushes",
  );
  if (titlesError) {
    // Not fatal: the other pushes still go out.
    console.error("claim_circle_title_pushes failed", titlesError.message);
  }
  targets.push(...((titles ?? []) as TitlePushRow[]).map(titleTarget));

  // "Your answer was accepted" / "your question was marked solved" (C9):
  // mark_post_solved wakes this function.
  const { data: qaPushes, error: qaError } = await admin.rpc(
    "claim_qa_answer_pushes",
  );
  if (qaError) {
    // Not fatal: the other pushes still go out.
    console.error("claim_qa_answer_pushes failed", qaError.message);
  }
  targets.push(...((qaPushes ?? []) as QaPushRow[]).map(qaTarget));

  // The push of an official notice (K6), a batch of devices at a time: in
  // the language of each device, held back in quiet hours below like the
  // rest. publish_announcement wakes this function, and claim gives out the
  // next batch and wakes it again until every device has been reached.
  const { data: notices, error: noticesError } = await admin.rpc(
    "claim_announcement_pushes",
  );
  if (noticesError) {
    // Not fatal: the other pushes still go out.
    console.error("claim_announcement_pushes failed", noticesError.message);
  }
  targets.push(
    ...((notices ?? []) as AnnouncementPushRow[]).map(announcementTarget),
  );
  // A monitoring alert that failed (K3), to the devices of the owners and
  // moderators: ops_raise_alert wakes this function.
  const { data: opsAlerts, error: opsAlertsError } = await admin.rpc(
    "claim_ops_alert_pushes",
  );
  if (opsAlertsError) {
    // Not fatal: the other pushes still go out.
    console.error("claim_ops_alert_pushes failed", opsAlertsError.message);
  }
  targets.push(
    ...((opsAlerts ?? []) as OpsAlertPushRow[]).map(opsAlertTarget),
  );
  // "Your daily digest is ready", once the `ai` function finished a card (it
  // wakes this function).
  const { data: digests, error: digestsError } = await admin.rpc(
    "claim_digest_pushes",
  );
  if (digestsError) {
    // Not fatal: the other pushes still go out.
    console.error("claim_digest_pushes failed", digestsError.message);
  }
  targets.push(...((digests ?? []) as DigestPushRow[]).map(digestPushTarget));
  // Friends' birthdays: at 9 in the morning of the recipient's device (the
  // tick wakes this function while one is due).
  const { data: birthdays, error: birthdaysError } = await admin.rpc(
    "claim_birthday_pushes",
  );
  if (birthdaysError) {
    // Not fatal: the other pushes still go out (the reminders are claimed
    // again on the next wake-up).
    console.error("claim_birthday_pushes failed", birthdaysError.message);
  }
  targets.push(...((birthdays ?? []) as BirthdayPushRow[]).map(birthdayTarget));

  // "Please confirm the announcement" (the owner or an admin asked): a
  // normal push, held back by quiet hours like the others.
  const { data: announcementAcks, error: announcementAcksError } = await admin
    .rpc("claim_announcement_ack_pushes");
  if (announcementAcksError) {
    // Not fatal: the other pushes still go out.
    console.error(
      "claim_announcement_ack_pushes failed",
      announcementAcksError.message,
    );
  }
  targets.push(
    ...((announcementAcks ?? []) as UrgentPushRow[]).map(urgentRowTarget),
  );

  // Urgent messages, first push and the one second push after 10 minutes
  // without a confirmation. They break through quiet hours (and, in the
  // claim, Do Not Disturb and mutes), so they skip the quiet hours filter
  // below.
  const { data: urgent, error: urgentError } = await admin.rpc(
    "claim_urgent_pushes",
  );
  if (urgentError) {
    // Not fatal: the other pushes still go out (the rows are claimed again
    // on the next wake-up).
    console.error("claim_urgent_pushes failed", urgentError.message);
  }
  const urgentTargets = ((urgent ?? []) as UrgentPushRow[]).map(
    urgentRowTarget,
  );

  // Files of expired disappearing messages. Not a push, but it needs the
  // service role and Storage, so it rides on the same tick.
  try {
    await cleanUpExpired(admin);
  } catch {
    // Tried again on the next tick.
  }

  // Quiet hours hold back what is not for the recipient's exceptions (the
  // inbox entries were written above and do not depend on this). Urgent
  // messages are not held back.
  const audible = await audibleTargets(
    admin,
    // Messages sent silently (a silent scheduled message, for one) are told
    // to nobody.
    await dropSilentPushes(admin, targets),
    await dropSilentPushes(admin, urgentTargets),
    Math.floor(Date.now() / 1000),
  );
  // A chat the subscriber locked is told without its words (G2).
  const unrevealing = await maskLockedPushes(admin, audible);
  // Times in the text are written for each subscriber's zone and language.
  const ready = await writeTimesForTargets(
    admin,
    unrevealing,
    Math.floor(Date.now() / 1000),
  );
  const gone: string[] = [];
  let delivered = 0;
  // How it went, as three numbers for the monitoring (K3).
  const tally = newTally();
  await Promise.all(ready.map(async (target) => {
    try {
      const status = await sendWebPush(keys, target, {
        title: target.title,
        body: target.body,
        tag: target.tag ?? target.conversation_id ?? undefined,
        url: targetPath(target),
      }, { nowSeconds: Math.floor(Date.now() / 1000) });
      tallyPush(tally, status);
      if (status === 404 || status === 410) {
        gone.push(target.subscription_id);
      } else if (status >= 200 && status < 300) {
        delivered++;
      }
    } catch {
      // One unreachable push service doesn't stop the others.
      tallyPush(tally, null);
    }
  }));
  if (gone.length > 0) {
    await admin.rpc("remove_push_subscriptions", { target_ids: gone });
  }
  await recordPushOutcome(admin, tally);
  return json({ sent: delivered, removed: gone.length });
});
