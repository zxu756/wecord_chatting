// Join request answers as pushes of the scheduled-dispatch function (C1).
//
// claim_join_request_pushes hands out one row per subscription of the
// applicant, already worded in the subscription's language, with the time as
// a time token that writeTimesForTargets turns into the subscription's own
// time zone. This only reshapes a row into a PushTarget; it is kept out of
// logic.ts so that file stays untouched by this feature.
import type { PushTarget } from "./logic.ts";

/// A row of claim_join_request_pushes.
export interface JoinRequestPushRow {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  title: string;
  body: string;
  tag: string;
  url: string;
}

/// "Join request approved" as a push: one tag per request. Approval opens
/// the circle (the rules and the welcome message wait there); a denial opens
/// Notifications, where the card shows the moderator's note.
export function joinRequestTarget(row: JoinRequestPushRow): PushTarget {
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
