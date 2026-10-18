// Calendar subscription: GET /calendar-feed/<token>.ics. verify_jwt is off
// (supabase/config.toml) because Apple Calendar and Google Calendar cannot
// sign in; the token is checked inside the database function
// calendar_feed_items, which only the service role may call. See feed.ts.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { type FeedResult, handleFeedRequest, WindowLimiter } from "./feed.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

const admin = supabaseUrl && serviceRoleKey
  ? createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  : null;

// 20 wrong tokens a minute per address, per running instance.
const badTokens = new WindowLimiter(20, 60_000);

Deno.serve((request) =>
  handleFeedRequest(request, {
    now: () => new Date(),
    badTokens,
    lookup: async (tokenHash, from, to) => {
      if (!admin) throw new Error("not configured");
      const { data, error } = await admin.rpc("calendar_feed_items", {
        p_token_hash: tokenHash,
        p_from: from.toISOString(),
        p_to: to.toISOString(),
      });
      if (error) throw error;
      return data as FeedResult;
    },
  })
);
