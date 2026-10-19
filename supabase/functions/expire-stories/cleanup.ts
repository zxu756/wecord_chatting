// Removing the files of dailies that have ended (B1), shared by the
// expire-stories function and anything else that wants to run it.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const removeBatchSize = 200;
const maxRounds = 10;

interface MediaRow {
  bucket_id?: unknown;
  object_path?: unknown;
}

export class StoryCleanupError extends Error {
  constructor(readonly code: string, readonly purged = 0) {
    super(code);
  }
}

/// Deletes the dailies past their end (purge_expired_stories; their files
/// are queued by a trigger), removes the queued files from Storage and
/// confirms them. Needs a service role client. Throws a [StoryCleanupError]
/// when a lookup fails. Files Storage refused to remove stay queued for the
/// next run.
export async function cleanUpStories(
  admin: SupabaseClient,
): Promise<{ purged: number; removed: number }> {
  let purged = 0;
  for (let round = 0; round < maxRounds; round++) {
    const { data, error } = await admin.rpc("purge_expired_stories", {
      batch_limit: 1000,
    });
    if (error) throw new StoryCleanupError("purge_failed");
    purged += Number(data ?? 0);
    if (Number(data ?? 0) < 1000) break;
  }

  let removed = 0;
  for (let round = 0; round < maxRounds; round++) {
    const { data, error } = await admin.rpc("claim_story_media", {
      max_rows: removeBatchSize,
    });
    if (error) throw new StoryCleanupError("claim_failed", purged);
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
    let progressed = false;
    for (const [bucket, paths] of byBucket) {
      const { error: removeError } = await admin.storage.from(bucket).remove(
        paths,
      );
      // Keep the rows for the next run when Storage refused.
      if (removeError) continue;
      await admin.rpc("finish_story_media", { paths });
      removed += paths.length;
      progressed = true;
    }
    // Nothing could be removed: do not claim the same rows again this run.
    if (!progressed || rows.length < removeBatchSize) break;
  }
  return { purged, removed };
}
