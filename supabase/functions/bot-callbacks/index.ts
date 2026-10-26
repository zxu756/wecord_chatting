// Sends interactions (slash commands and presses on a bot's buttons and
// lists) to the callback address a circle's managers gave the bot.
//
// Called by the database (a trigger when a press is queued, and pg_cron every
// minute for retries) with the shared secret DISPATCH_SECRET as the bearer
// token, which the function compares itself (verify_jwt = false in
// supabase/config.toml). Users never call it. It claims due interactions with
// claim_bot_callbacks, POSTs each to its bot with a signed body (sign.ts),
// 5 second timeout, no redirects, only to public https addresses (ssrf.ts),
// and reports each result with finish_bot_callback, which retries after
// 5 seconds, 30 seconds and 2 minutes and then hands the press back to
// polling. See docs/bot-api.md.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isAuthorized } from "./auth.ts";
import { runCallbacks } from "./deliver.ts";
import { dohResolver, systemResolver } from "./dns.ts";

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
    const summary = await runCallbacks(
      (name, params) =>
        admin.rpc(name, params) as unknown as ReturnType<
          Parameters<typeof runCallbacks>[0]
        >,
      {
        resolve: systemResolver(Deno, dohResolver(fetch)),
        fetch,
        now: () => Date.now(),
      },
    );
    return json(summary);
  } catch (error) {
    console.error("bot-callbacks failed", error);
    return json({ error: "failed" }, 500);
  }
});
