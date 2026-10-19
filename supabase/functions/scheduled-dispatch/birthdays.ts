// Friends' birthdays as pushes of the scheduled-dispatch function (B5).
//
// claim_birthday_pushes hands out one row per subscription of a recipient
// whose local time is between 09:00 and 20:59 on a friend's birthday, already
// worded in the subscription's language (there is no time in the text, so
// nothing is written in a time zone). This only reshapes a row into a
// PushTarget; it is kept out of logic.ts so that file stays untouched by
// this feature.
import type { PushTarget } from "./logic.ts";

/// A row of claim_birthday_pushes.
export interface BirthdayPushRow {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  title: string;
  body: string;
  tag: string;
  url: string;
}

/// "It's Ada's birthday today" as a push: one tag per friend and year, so a
/// second device of the same person replaces rather than doubles it. It opens
/// Notifications, where the birthday card waits with a one-tap greeting.
export function birthdayTarget(row: BirthdayPushRow): PushTarget {
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
