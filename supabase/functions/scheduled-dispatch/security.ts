// New-login alert pushes of the scheduled-dispatch function (G3).
//
// claim_security_alert_pushes hands out one row per subscription of the
// user, already worded in the subscription's language, with the time as a
// time token that writeTimesForTargets turns into the subscription's own
// time zone. This only reshapes a row into a PushTarget; it is kept out of
// logic.ts so that file stays untouched by this feature.
import type { PushTarget } from "./logic.ts";

/// A row of claim_security_alert_pushes.
export interface SecurityPushRow {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  title: string;
  body: string;
  tag: string;
  url: string;
}

/// "New sign-in to your account" as a push: one tag per alert, and tapping
/// it opens Notifications, where the Security card has "Not me".
export function securityTarget(row: SecurityPushRow): PushTarget {
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
