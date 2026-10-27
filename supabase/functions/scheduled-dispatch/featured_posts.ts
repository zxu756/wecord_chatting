// The push for "your post was featured" (B8): a moderator marked the person's
// circle post as featured (精华).
//
// claim_featured_post_pushes (migration 202610280760) hands out one row per
// subscription of the author, already worded in the subscription's language;
// this only reshapes a row into a PushTarget. A tap opens the post. The post
// is not a chat, so there is no chat to lock (G2) and the words only carry the
// circle's name and the post's title. Quiet hours (A4) hold it back in
// index.ts like the other pushes. Kept out of logic.ts so that file stays
// untouched by this feature.
import type { PushTarget } from "./logic.ts";

/// A row of claim_featured_post_pushes.
export interface FeaturedPostPushRow {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  title: string;
  body: string;
  tag: string;
  url: string;
}

/// One tag per post, so a second push for the same post replaces the first.
export function featuredPostTarget(row: FeaturedPostPushRow): PushTarget {
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
