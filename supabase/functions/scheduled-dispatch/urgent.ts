// Urgent messages and "please confirm" pushes of the scheduled-dispatch
// function (A7).
//
// claim_urgent_pushes and claim_announcement_ack_pushes hand out one row per
// subscription, already worded in the subscription's language. This reshapes
// the rows into PushTargets and decides what quiet hours may hold back; it is
// kept out of logic.ts so that file stays untouched by this feature.
//
// An urgent push breaks through quiet hours (A4), exactly as it breaks through
// Do Not Disturb and a muted conversation in the claim function. Nothing else
// does: a "please confirm the announcement" push is held back like any other.
import { dropQuietPushes, type RpcClient } from "../push/quiet_hours.ts";
import type { PushTarget } from "./logic.ts";

/// A row of claim_urgent_pushes or claim_announcement_ack_pushes.
export interface UrgentPushRow {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  conversation_id: string | null;
  circle_id: string | null;
  title: string;
  body: string;
  tag: string;
  url: string | null;
}

/// A row as a push. One tag per message (or announcement), so the second push
/// of an urgent message replaces the first instead of stacking. Tapping opens
/// the conversation (a circle channel opens in its circle).
export function urgentRowTarget(row: UrgentPushRow): PushTarget {
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
    ...(row.url ? { url: row.url } : {}),
  };
}

/// What may be sent now: [targets] without the pushes quiet hours hold back,
/// plus every one of [urgent], which quiet hours never hold back.
export async function audibleTargets(
  admin: RpcClient,
  targets: PushTarget[],
  urgent: PushTarget[],
  nowSeconds: number,
  holdBack: typeof dropQuietPushes = dropQuietPushes,
): Promise<PushTarget[]> {
  const others = await holdBack(admin, targets, nowSeconds);
  return [...others, ...urgent];
}
