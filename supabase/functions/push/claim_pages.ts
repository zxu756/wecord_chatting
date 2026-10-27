// Claims the pushes of one message a batch of people at a time (L6).
//
// claim_push_delivery used to answer with one row per device of everyone who
// should hear about a message: 6000 rows for a group of 5000, 12000 for a big
// circle channel. The REST API cuts an answer at 1000 rows, so everyone after
// that never got the push, and the message was marked as done. The database
// now takes a cursor (the last person of the previous batch) and a batch size
// (see migration 202610281220); this walks the batches. The first call claims
// the message, so it is still pushed at most once.
//
// Apply the migration before deploying a function that uses this: the new
// arguments do not exist before it.

/// What the helper needs from the database client.
export interface ClaimClient {
  rpc(
    name: string,
    args?: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message: string } | null }>;
}

/// How many people one batch holds. Each has a few devices, so a batch stays
/// well under the REST row limit.
export const CLAIM_BATCH_PEOPLE = 200;

/// Rows the REST API answers with at most (max_rows).
export const REST_ROW_LIMIT = 1000;

interface Recipient {
  recipient_id?: string | null;
}

/// Walks the batches of one message in order and hands each to `onBatch`.
/// Stops with the error when a call fails (what was handed over stays
/// handed over: the people of later batches are not told).
export async function claimPushBatches<T extends object>(
  client: ClaimClient,
  messageId: string,
  callerId: string,
  onBatch: (rows: T[]) => Promise<void> | void,
  batchPeople = CLAIM_BATCH_PEOPLE,
): Promise<{ error: string | null; batches: number }> {
  let cursor: string | null = null;
  let batches = 0;
  for (;;) {
    const { data, error } = await client.rpc("claim_push_delivery", {
      target_message_id: messageId,
      caller_id: callerId,
      after_user_id: cursor,
      page_size: batchPeople,
    });
    if (error) {
      return { error: error.message, batches };
    }
    let rows = (data ?? []) as T[];
    batches++;
    const people: string[] = [];
    for (const row of rows) {
      const id = (row as Recipient).recipient_id;
      if (id && people[people.length - 1] !== id) {
        people.push(id);
      }
    }
    let more = people.length >= batchPeople;
    if (rows.length >= REST_ROW_LIMIT && people.length > 1) {
      // The API cut the answer: the last person may be missing devices.
      // Leave that person to the next batch.
      const last = people.pop();
      rows = rows.filter((row) => (row as Recipient).recipient_id !== last);
      more = true;
    }
    if (rows.length > 0) {
      await onBatch(rows);
    }
    const next = people[people.length - 1];
    if (!more || next === undefined || next === cursor) {
      return { error: null, batches };
    }
    cursor = next;
  }
}

/// Every batch of a message, as one list (for callers that send afterwards).
export async function claimAllPushRows<T extends object>(
  client: ClaimClient,
  messageId: string,
  callerId: string,
  batchPeople = CLAIM_BATCH_PEOPLE,
): Promise<{ rows: T[]; error: string | null }> {
  const rows: T[] = [];
  const { error } = await claimPushBatches<T>(
    client,
    messageId,
    callerId,
    (batch) => {
      rows.push(...batch);
    },
    batchPeople,
  );
  return { rows, error };
}

/// Runs `work` on every item, at most `limit` at a time, so thousands of
/// devices are not all contacted at once.
export async function forEachLimited<T>(
  items: readonly T[],
  limit: number,
  work: (item: T) => Promise<void>,
): Promise<void> {
  let next = 0;
  const lanes = Array.from(
    { length: Math.max(1, Math.min(limit, items.length)) },
    async () => {
      while (next < items.length) {
        const item = items[next++];
        await work(item);
      }
    },
  );
  await Promise.all(lanes);
}

/// Devices contacted at the same time by one function run.
export const SEND_CONCURRENCY = 50;
