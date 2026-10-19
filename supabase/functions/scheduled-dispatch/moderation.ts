// Moderation pushes of the scheduled-dispatch function (C5, C6): the alert to
// a circle's moderators when raid protection locked the circle down by
// itself, and the answer to a ban appeal for the person who appealed.
//
// claim_moderation_pushes hands out one row per subscription, already worded
// in the subscription's language; this only reshapes a row into a PushTarget.
// It is kept out of logic.ts so that file stays untouched by this feature.
import type { PushTarget } from "./logic.ts";

/// A row of claim_moderation_pushes.
export interface ModerationPushRow {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  title: string;
  body: string;
  tag: string;
  url: string;
}

/// "Raid protection is on" opens the circle (the Review page holds the
/// one-tap "End lockdown"); a ban appeal's answer opens Notifications. One
/// tag per event, so a second push for the same thing replaces the first.
export function moderationTarget(row: ModerationPushRow): PushTarget {
  return {
    subscription_id: row.subscription_id,
    endpoint: row.endpoint,
    p256dh: row.p256dh,
    auth: row.auth,
    conversation_id: null,
    circle_id: null,
    title: row.title,
    body: row.body,
    tag: row.tag,
    url: row.url,
  };
}
