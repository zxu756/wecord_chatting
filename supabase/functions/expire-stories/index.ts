// Removes the files of dailies that have ended from Storage.
//
// The dailies themselves are deleted in SQL (purge_expired_stories, run by
// pg_cron every five minutes); Storage objects can only be removed through
// the Storage API, so a trigger queues the files of every deleted daily and
// this function, called with the shared secret DISPATCH_SECRET as the bearer
// token (the pg_cron job wecord-expire-story-files through
// wake_expire_stories(), or a scheduler of your choice), claims them, removes them
// and confirms. It also runs the purge itself first, so it alone is enough
// on a project without pg_cron. Reading already stopped at the end of a daily
// (story_visible_to), this only frees the space.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isAuthorized } from "./auth.ts";
import { cleanUpStories, StoryCleanupError } from "./cleanup.ts";

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
  const secret = Deno.env.get("DISPATCH_SECRET") ?? "";
  if (secret === "") {
    return json({ error: "not_configured" }, 500);
  }
  // Only the database calls this; users never do.
  if (!isAuthorized(request.headers.get("Authorization"), secret)) {
    return json({ error: "unauthorized" }, 401);
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "not_configured" }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    return json(await cleanUpStories(admin));
  } catch (error) {
    if (error instanceof StoryCleanupError) {
      return json({ error: error.code, purged: error.purged }, 500);
    }
    throw error;
  }
});
