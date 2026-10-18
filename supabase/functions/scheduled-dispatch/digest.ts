// "Your daily digest is ready" as a push of the scheduled-dispatch function
// (F3, migration 202610230530).
//
// claim_digest_pushes hands out one row per subscription of the person for a
// digest the `ai` function just finished, already worded in the subscription's
// language. The text carries no chat content (only how many chats had news).
// This only reshapes a row into a PushTarget; it is kept out of logic.ts so
// that file stays untouched by this feature.
import type { PushTarget } from "./logic.ts";

/// A row of claim_digest_pushes.
export interface DigestPushRow {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  title: string;
  body: string;
  tag: string;
  url: string;
}

/// The digest push: one tag per digest, opens Notifications where the card
/// waits.
export function digestPushTarget(row: DigestPushRow): PushTarget {
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
