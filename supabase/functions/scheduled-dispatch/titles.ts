// The push for a member title (C7): "<circle> gave you the title X".
//
// claim_circle_title_pushes (migration 202610270210) hands out one row per
// subscription of the person, already worded in the subscription's language;
// this only reshapes a row into a PushTarget. A tap opens the circle. It is
// kept out of logic.ts so that file stays untouched by this feature.
import type { PushTarget } from "./logic.ts";

/// A row of claim_circle_title_pushes.
export interface TitlePushRow {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  title: string;
  body: string;
  tag: string;
  url: string;
}

/// One tag per title, so a second push for the same notice replaces the first.
export function titleTarget(row: TitlePushRow): PushTarget {
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
