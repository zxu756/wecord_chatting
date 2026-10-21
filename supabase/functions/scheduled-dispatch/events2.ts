// The push for a seat that opened up in an event (C10): "you moved up from
// the waiting list".
//
// claim_event_notice_pushes (migration 202610270460) hands out one row per
// subscription of the person, already worded in the subscription's language,
// with the event's start as a <t:unix:f> token that writeTimesForTargets turns
// into the subscription's own zone; this only reshapes a row into a
// PushTarget. A chat event's row carries its conversation, so a chat the
// person locked is told without its words (maskLockedPushes, G2) and quiet
// hours hold it back (audibleTargets, A4) like any other push; a tap opens the
// event's chat or the event in its circle. It is kept out of logic.ts so that
// file stays untouched by this feature.
import type { PushTarget } from "./logic.ts";

/// A row of claim_event_notice_pushes.
export interface EventNoticePushRow {
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
export function eventNoticeTarget(row: EventNoticePushRow): PushTarget {
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
