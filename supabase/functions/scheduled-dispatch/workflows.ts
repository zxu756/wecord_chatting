// The push for a message a workflow sent (D9): "Welcome Gus to Hike Club!".
//
// A workflow (migration 202610281330) sends its messages as the person it runs
// as, through the ordinary send functions, from a job of its own (pg_cron,
// every minute). run_workflow_tick queues each message for its push and wakes
// this function; claim_workflow_message_pushes hands each one out once. The
// push itself is then asked of claim_push_delivery, exactly as for a scheduled
// message the sender just sent, so mutes, Do Not Disturb, blocks, the language
// of the subscription and the like apply unchanged; the caller then holds it
// back in quiet hours and masks a locked chat like every other push. It is
// kept out of logic.ts so that file stays untouched by this feature.
import type { PushTarget } from "./logic.ts";

/// What the dispatcher needs from the database client.
export interface WorkflowRpcClient {
  rpc(
    name: string,
    args?: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message: string } | null }>;
}

/// A row of claim_workflow_message_pushes.
export interface WorkflowMessageRow {
  message_id: string;
  sender_id: string;
}

/// The pushes for the messages workflows sent since the last wake-up.
///
/// A failure to read is not fatal (nothing was claimed, so the messages are
/// claimed again on the next wake-up), so it returns what it could and logs
/// the rest.
export async function workflowMessageTargets(
  admin: WorkflowRpcClient,
): Promise<PushTarget[]> {
  const { data: sent, error } = await admin.rpc(
    "claim_workflow_message_pushes",
  );
  if (error) {
    console.error("claim_workflow_message_pushes failed", error.message);
    return [];
  }
  const targets: PushTarget[] = [];
  for (const row of (sent ?? []) as WorkflowMessageRow[]) {
    const { data, error: claimError } = await admin.rpc("claim_push_delivery", {
      target_message_id: row.message_id,
      caller_id: row.sender_id,
    });
    if (claimError) {
      console.error("claim_push_delivery failed", claimError.message);
      continue;
    }
    targets.push(
      ...((data ?? []) as PushTarget[]).map((target) => ({
        ...target,
        message_id: row.message_id,
      })),
    );
  }
  return targets;
}
