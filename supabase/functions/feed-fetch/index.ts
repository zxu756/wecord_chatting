// Reads the RSS and Atom feeds that channels follow and posts new items as
// cards (roadmap I6).
//
// Called by the database (pg_cron job wecord-feed-fetch, every 5 minutes
// through wake_feed_fetch_if_due, and only when a feed is due) with the shared
// secret DISPATCH_SECRET as the bearer token, which the function compares
// itself (verify_jwt = false in supabase/config.toml). Users never call it.
//
// Each feed is read at most every 15 minutes (a bad one backs off up to 6
// hours and pauses after 8 failures). The address is checked for SSRF with a
// DNS lookup before every request and redirect (supabase/functions/_shared/
// ssrf.ts), the read takes at most 8 seconds and 512 KB, nothing but a few
// text fields is taken from the document, and the database cleans the texts
// again and applies AutoMod and the daily limits (post_feed_items). See
// docs/bot-api.md.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isAuthorized } from "../_shared/auth.ts";
import { dohResolver, systemResolver } from "../_shared/dns.ts";
import { runFeeds } from "./run.ts";

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
    const summary = await runFeeds(
      (name, params) =>
        admin.rpc(name, params) as unknown as ReturnType<
          Parameters<typeof runFeeds>[0]
        >,
      {
        resolve: systemResolver(Deno, dohResolver(fetch)),
        fetch,
        now: () => Date.now(),
      },
    );
    return json(summary);
  } catch (error) {
    console.error("feed-fetch failed", error);
    return json({ error: "failed" }, 500);
  }
});
