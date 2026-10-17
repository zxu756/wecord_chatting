// Removing what expired disappearing messages leave behind, shared by
// expire-messages and the scheduled-dispatch tick.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const removeBatchSize = 200;
const maxRounds = 10;

interface MediaRow {
  bucket_id?: unknown;
  object_path?: unknown;
}

export class CleanupError extends Error {
  constructor(readonly code: string, readonly purged = 0) {
    super(code);
  }
}

/// Deletes expired messages (purge_expired_messages), removes their files
/// from Storage and drops the PDF previews of messages that are gone. Needs
/// a service role client. Throws a [CleanupError] when a lookup fails.
export async function cleanUpExpired(
  admin: SupabaseClient,
): Promise<{ purged: number; removed: number; previews: number }> {
  let purged = 0;
  for (let round = 0; round < maxRounds; round++) {
    const { data, error } = await admin.rpc("purge_expired_messages", {
      batch_limit: 2000,
    });
    if (error) throw new CleanupError("purge_failed");
    purged += Number(data ?? 0);
    if (Number(data ?? 0) < 2000) break;
  }

  let removed = 0;
  for (let round = 0; round < maxRounds; round++) {
    const { data, error } = await admin.rpc("claim_expired_media", {
      max_rows: removeBatchSize,
    });
    if (error) throw new CleanupError("claim_failed", purged);
    const rows = (data ?? []) as MediaRow[];
    if (rows.length === 0) break;

    const byBucket = new Map<string, string[]>();
    for (const row of rows) {
      if (typeof row.bucket_id !== "string") continue;
      if (typeof row.object_path !== "string") continue;
      const paths = byBucket.get(row.bucket_id) ?? [];
      paths.push(row.object_path);
      byBucket.set(row.bucket_id, paths);
    }
    for (const [bucket, paths] of byBucket) {
      const { error: removeError } = await admin.storage.from(bucket).remove(
        paths,
      );
      // Keep the rows for the next run when Storage refused.
      if (removeError) continue;
      await admin.rpc("finish_expired_media", {
        buckets: paths.map(() => bucket),
        paths,
      });
      removed += paths.length;
    }
    if (rows.length < removeBatchSize) break;
  }

  // Office previews of messages that are gone (best effort).
  const { data: stale } = await admin.rpc("stale_file_previews", {
    max_rows: 50,
  });
  const previews = ((stale ?? []) as { object_name?: unknown }[])
    .map((row) => row.object_name)
    .filter((name): name is string => typeof name === "string");
  if (previews.length > 0) {
    await admin.storage.from("file-previews").remove(previews);
  }
  return { purged, removed, previews: previews.length };
}
