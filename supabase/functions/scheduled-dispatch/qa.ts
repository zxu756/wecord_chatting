// The push for a Q&A answer (C9): "your answer was accepted", and "a moderator
// marked your question solved".
//
// claim_qa_answer_pushes (migration 202610270310) hands out one row per
// subscription of the person, already worded in the subscription's language;
// this only reshapes a row into a PushTarget. A tap opens the post. It is kept
// out of logic.ts so that file stays untouched by this feature.
import type { PushTarget } from "./logic.ts";

/// A row of claim_qa_answer_pushes.
export interface QaPushRow {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  title: string;
  body: string;
  tag: string;
  url: string;
}

/// One tag per notice, so a second push for the same notice replaces the first.
export function qaTarget(row: QaPushRow): PushTarget {
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
