// Removes the files of expired disappearing messages from Storage.
//
// The messages themselves are deleted in SQL (purge_expired_messages, run
// by pg_cron); Storage objects can only be removed through the Storage API,
// so purge_expired_messages queues the files nothing else uses and this
// function, called with the service role key as the bearer token (a
// pg_net cron job, a scheduled function or any scheduler), claims them,
// removes them and confirms. It also runs the purge itself first, so it
// alone is enough on a project without pg_cron, and removes the PDF
// previews of messages that are gone.
import { createClient } from "jsr:@supabase/supabase-js@2";

const removeBatchSize = 200;
const maxRounds = 10;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface MediaRow {
  bucket_id?: unknown;
  object_path?: unknown;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "not_configured" }, 500);
  }
  // Only the service role may call this; users never do.
  const authorization = request.headers.get("Authorization") ?? "";
  if (authorization.replace(/^Bearer\s+/i, "") !== serviceRoleKey) {
    return json({ error: "unauthorized" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let purged = 0;
  for (let round = 0; round < maxRounds; round++) {
    const { data, error } = await admin.rpc("purge_expired_messages", {
      batch_limit: 2000,
    });
    if (error) return json({ error: "purge_failed" }, 500);
    purged += Number(data ?? 0);
    if (Number(data ?? 0) < 2000) break;
  }

  let removed = 0;
  for (let round = 0; round < maxRounds; round++) {
    const { data, error } = await admin.rpc("claim_expired_media", {
      max_rows: removeBatchSize,
    });
    if (error) return json({ error: "claim_failed", purged }, 500);
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

  return json({ purged, removed, previews: previews.length });
});
