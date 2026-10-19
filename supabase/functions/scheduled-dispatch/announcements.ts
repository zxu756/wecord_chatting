// The push of an official notice (K6) as a push of the scheduled-dispatch
// function.
//
// claim_announcement_pushes (migration 202610240630) hands out a batch of
// devices at a time, each row already worded in the device's language: the
// notice's title and the start of its text, tag `announcement-<id>`, opening
// Notifications. The text has no time in it, so nothing is written per time
// zone; quiet hours and Do Not Disturb are applied by the dispatcher as for
// every push that is not about a message (nothing breaks through). This only
// reshapes a row into a PushTarget; it is kept out of logic.ts so that file
// stays untouched by this feature.
import type { PushTarget } from "./logic.ts";

/// A row of claim_announcement_pushes.
export interface AnnouncementPushRow {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  title: string;
  body: string;
  tag: string;
  url: string;
}

/// An official notice as a push: one tag per notice, so a device that is
/// reached twice shows it once.
export function announcementTarget(row: AnnouncementPushRow): PushTarget {
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
