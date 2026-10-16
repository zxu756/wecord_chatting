// AI features for WeCord, through any OpenAI-compatible Chat Completions
// provider named by secrets (AI_BASE_URL, AI_API_KEY, AI_MODEL; optional
// AI_DAILY_LIMIT_PER_USER, AI_MAX_INPUT_CHARS, AI_EXTRA_HEADERS; see
// docs/ai-setup.md). POST {action} with a signed-in user's token:
//   status                      -> {configured, daily_limit, used}
//   summarize {conversation_id, after_message_id?, recent?, language}
//   rewrite {mode, text, target?, conversation_id?}
//   translate {text, target, conversation_id?}
// Chat is read as the caller, so only messages they can see are used.
// Nothing is stored beyond the day's request count (ai_usage). Answers 503
// ai_not_configured until the three required secrets are set.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, handleAiRequest } from "./handler.ts";
import { loadMessages } from "./messages.ts";

Deno.serve(async (request) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "not_configured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  const authorization = request.headers.get("Authorization") ?? "";
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  // Only the usage counter uses the service role.
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return await handleAiRequest(request, {
    env: (name) => Deno.env.get(name),
    fetch: (input, init) => fetch(input, init),
    authenticate: async (header) => {
      const { data, error } = await userClient.auth.getUser(
        header.replace(/^Bearer\s+/i, ""),
      );
      return error || !data?.user ? null : data.user.id;
    },
    loadMessages: (options) => loadMessages(userClient, options),
    circleAllows: () => Promise.resolve(true),
    consume: async (userId, limit) => {
      const { data, error } = await admin.rpc("ai_consume_request", {
        p_user_id: userId,
        p_limit: limit,
      });
      if (error) {
        throw new Error(`ai_consume_request: ${error.message}`);
      }
      const row = (Array.isArray(data) ? data[0] : data) as
        | { allowed?: boolean; used?: number }
        | null;
      return { allowed: row?.allowed === true, used: row?.used ?? 0 };
    },
    refund: async (userId) => {
      await admin.rpc("ai_refund_request", { p_user_id: userId });
    },
    usedToday: async (userId) => {
      const { data } = await admin.rpc("ai_requests_today", {
        p_user_id: userId,
      });
      return typeof data === "number" ? data : 0;
    },
  });
});
