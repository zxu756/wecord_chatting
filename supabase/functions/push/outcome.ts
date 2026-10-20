// How a round of pushes went, for the monitoring of the admin console (K3):
// three counts and nothing else. The push functions tally the answer of each
// push service as they send, then report once through ops_record_push (which
// only the service role may call), and the health check reads the share of
// failures per hour.
//
//   sent    the push service took it (2xx)
//   gone    the subscription is dead (404/410); it is removed, and that is
//           normal housekeeping, so it does not count as a failure
//   failed  anything else: another status, or the request threw

export interface PushTally {
  sent: number;
  failed: number;
  gone: number;
}

export function newTally(): PushTally {
  return { sent: 0, failed: 0, gone: 0 };
}

/// Counts the answer of one push. [status] is null when the request threw.
export function tallyPush(tally: PushTally, status: number | null): void {
  if (status === null) {
    tally.failed++;
  } else if (status === 404 || status === 410) {
    tally.gone++;
  } else if (status >= 200 && status < 300) {
    tally.sent++;
  } else {
    tally.failed++;
  }
}

interface RpcClient {
  rpc(name: string, args: Record<string, unknown>): PromiseLike<unknown>;
}

/// Reports a round. Never throws and never waits for a failure to matter:
/// the pushes have gone out already, and the numbers are only for watching.
export async function recordPushOutcome(
  admin: RpcClient,
  tally: PushTally,
): Promise<void> {
  if (tally.sent + tally.failed + tally.gone === 0) {
    return;
  }
  try {
    await admin.rpc("ops_record_push", {
      sent_count: tally.sent,
      failed_count: tally.failed,
      gone_count: tally.gone,
    });
  } catch {
    // Not worth failing a push for.
  }
}
