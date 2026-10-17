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
import { CleanupError, cleanUpExpired } from "./cleanup.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
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

  try {
    return json(await cleanUpExpired(admin));
  } catch (error) {
    if (error instanceof CleanupError) {
      return json({ error: error.code, purged: error.purged }, 500);
    }
    throw error;
  }
});
