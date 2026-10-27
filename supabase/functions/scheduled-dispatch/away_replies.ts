// The push for an away auto-reply (A8): "{name}: I'm away until Monday".
//
// The database wrote the reply as an ordinary message from the away person
// (migration 202610280310) and wakes this function; claim_away_reply_pushes
// hands out each reply once. The push itself is then asked of
// claim_push_delivery, exactly as for a scheduled message the sender just
// sent, so mutes, Do Not Disturb, blocks, the language of the subscription and
// the like apply unchanged; the caller then holds it back in quiet hours and
// masks a locked chat like every other push. It is kept out of logic.ts so
// that file stays untouched by this feature.
import { claimAllPushRows } from "../push/claim_pages.ts";
import type { PushTarget } from "./logic.ts";

/// What the dispatcher needs from the database client.
export interface AwayRpcClient {
  rpc(
    name: string,
    args?: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message: string } | null }>;
}

/// A row of claim_away_reply_pushes.
export interface AwayReplyRow {
  message_id: string;
  sender_id: string;
}

/// The pushes for the auto-replies written since the last wake-up.
///
/// A failure to read is not fatal (the replies are claimed again on the next
/// wake-up only if the claim itself did not happen), so it returns what it
/// could and logs the rest.
export async function awayReplyTargets(
  admin: AwayRpcClient,
): Promise<PushTarget[]> {
  const { data: replies, error } = await admin.rpc("claim_away_reply_pushes");
  if (error) {
    console.error("claim_away_reply_pushes failed", error.message);
    return [];
  }
  const targets: PushTarget[] = [];
  for (const row of (replies ?? []) as AwayReplyRow[]) {
    // In batches of people (L6): a big group has more devices than one
    // answer holds.
    const { rows, error: claimError } = await claimAllPushRows<PushTarget>(
      admin,
      row.message_id,
      row.sender_id,
    );
    if (claimError) {
      console.error("claim_push_delivery failed", claimError);
    }
    targets.push(
      ...rows.map((target) => ({ ...target, message_id: row.message_id })),
    );
  }
  return targets;
}
