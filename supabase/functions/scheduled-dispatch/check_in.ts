// The push for a daily check-in that has not been done (D3): "you have not
// checked in today", with the length of the run when it would break.
//
// claim_check_in_pushes (migration 202610280520) hands out one row per
// subscription of the person, already worded in the subscription's language
// ('en' or 'zh'); this only reshapes a row into a PushTarget. The row carries
// its chat, so a chat the person locked is told without its words
// (maskLockedPushes, G2) and quiet hours and Do Not Disturb hold it back
// (audibleTargets, A4) like any other push; a tap opens the chat. check_in_sweep
// (every 5 minutes, its own pg_cron job) wakes this function when it writes
// notices. It is kept out of logic.ts so that file stays untouched by this
// feature.
import type { PushTarget } from "./logic.ts";

/// A row of claim_check_in_pushes.
export interface CheckInPushRow {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  conversation_id: string | null;
  circle_id: string | null;
  title: string;
  body: string;
  tag: string;
  url: string;
}

/// One tag per notice, so a second push for the same notice replaces the first.
export function checkInTarget(row: CheckInPushRow): PushTarget {
  return {
    subscription_id: row.subscription_id,
    endpoint: row.endpoint,
    p256dh: row.p256dh,
    auth: row.auth,
    conversation_id: row.conversation_id,
    circle_id: row.circle_id,
    title: row.title,
    body: row.body,
    tag: row.tag,
    url: row.url,
  };
}
