// Sends events (new messages, mentions, edits, deletes, reactions, people
// joining or leaving, slash commands and presses) to the address a circle's
// managers gave a bot, as signed JSON POSTs (roadmap I2).
//
// Called by the database (a trigger when an event is queued, and pg_cron every
// minute for retries) with the shared secret DISPATCH_SECRET as the bearer
// token, which the function compares itself (verify_jwt = false in
// supabase/config.toml). Users never call it. It claims due deliveries with
// claim_bot_events (which checks again that the bot may still read the place),
// POSTs each with a signed body (supabase/functions/_shared/sign.ts), 5 second
// timeout, no redirects, only to public https addresses
// (supabase/functions/_shared/ssrf.ts), and reports each result with
// finish_bot_event, which retries after 5 seconds, 30 seconds, 2 minutes,
// 10 minutes and an hour and then gives up. See docs/bot-api.md.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isAuthorized } from "../_shared/auth.ts";
import { dohResolver, systemResolver } from "../_shared/dns.ts";
import { runEvents } from "./deliver.ts";

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
    const summary = await runEvents(
      (name, params) =>
        admin.rpc(name, params) as unknown as ReturnType<
          Parameters<typeof runEvents>[0]
        >,
      {
        resolve: systemResolver(Deno, dohResolver(fetch)),
        fetch,
        now: () => Date.now(),
      },
    );
    return json(summary);
  } catch (error) {
    console.error("bot-events failed", error);
    return json({ error: "failed" }, 500);
  }
});
