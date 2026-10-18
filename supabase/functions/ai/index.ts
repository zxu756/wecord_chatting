// AI features for WeCord, through any OpenAI-compatible Chat Completions
// provider named by secrets (AI_BASE_URL, AI_API_KEY, AI_MODEL; optional
// AI_DAILY_LIMIT_PER_USER, AI_MAX_INPUT_CHARS, AI_EXTRA_HEADERS; see
// docs/ai-setup.md). POST {action} with a signed-in user's token:
//   status                      -> {configured, daily_limit, used}
//   summarize {conversation_id, after_message_id?, recent?, language}
//   rewrite {mode, text, target?, conversation_id?}
//   translate {text, target, conversation_id?}
//   transcribe {message_id}     -> {text}. Needs the optional secrets
//     AI_TRANSCRIBE_BASE_URL, AI_TRANSCRIBE_API_KEY and AI_TRANSCRIBE_MODEL
//     (503 transcribe_not_configured without them).
//   translate_batch {conversation_id, message_ids (<= 20), target, manual?}
//     -> {translations, skipped, cached, translated}. Translations of the
//     messages on screen, from the cache (message_translations) first and
//     from the model for the rest; see translate_batch.ts.
//   guard {message_id}          -> the AI guard for new members: only the
//     database calls it (pg_net, Authorization: Bearer <DISPATCH_SECRET>, so
//     deploy with verify_jwt = false). It classifies the text of a message
//     held back from the circle, charges the circle's daily AI limit
//     (AI_GUARD_DAILY_LIMIT_PER_CIRCLE) and releases or holds the message;
//     when AI cannot answer it releases the message as "not checked".
//   assistant {job_id}          -> the @WeCord AI assistant answers a message
//     that mentioned it: only the database calls it (the same shared secret
//     and wake-up as guard; see assistant.ts and migrations 202610230400 to
//     202610230430). Replies as the WeCord AI account, created on first use.
//   extract_actions {conversation_id, message_ids (<= 50), time_zone?}
//     -> {items: [{title, assignee, due, due_has_time, due_text, kind,
//     source_message_id}], message_count}. To-dos and events in chosen
//     messages; assignees are conversation members only; see
//     extract_actions.ts.
// Chat is read as the caller, so only messages they can see are used.
// Nothing is stored beyond the day's request count (ai_usage) and the
// translations of translate_batch (message_translations, which go with the
// message). Answers 503
// ai_not_configured until the three required secrets are set.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, handleAiRequest } from "./handler.ts";
import { loadMessages } from "./messages.ts";
import { createActionStore, createAssistantStore } from "./assistant_store.ts";
import { createTranslationStore } from "./translations_store.ts";

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
    circleAllows: async (_userId, conversationId) => {
      const { data, error } = await userClient.rpc("conversation_ai_allowed", {
        target_conversation_id: conversationId,
      });
      if (error) {
        throw new Error(`conversation_ai_allowed: ${error.message}`);
      }
      return data !== false;
    },
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
    loadVoiceMessage: async (_userId, messageId) => {
      const { data } = await userClient
        .from("messages")
        .select("conversation_id,type,attachment,recalled_at")
        .eq("id", messageId)
        .maybeSingle();
      const attachment = data?.attachment as
        | Record<string, unknown>
        | null
        | undefined;
      if (
        !data || data.type !== "voice" || data.recalled_at ||
        attachment?.kind !== "voice" ||
        typeof attachment.bucket !== "string" ||
        typeof attachment.path !== "string"
      ) {
        return null;
      }
      return {
        conversationId: data.conversation_id as string,
        bucket: attachment.bucket,
        path: attachment.path,
        mimeType: typeof attachment.mime_type === "string"
          ? attachment.mime_type
          : "audio/wav",
        size: typeof attachment.size === "number" ? attachment.size : 0,
      };
    },
    downloadAudio: async (bucket, path) => {
      const { data, error } = await userClient.storage.from(bucket)
        .download(path);
      if (error || !data) {
        return null;
      }
      return new Uint8Array(await data.arrayBuffer());
    },
    usedToday: async (userId) => {
      const { data } = await admin.rpc("ai_requests_today", {
        p_user_id: userId,
      });
      return typeof data === "number" ? data : 0;
    },
    guardClaim: async (messageId) => {
      const { data, error } = await admin.rpc("ai_guard_claim", {
        p_message_id: messageId,
      });
      if (error) {
        throw new Error(`ai_guard_claim: ${error.message}`);
      }
      const row = (Array.isArray(data) ? data[0] : data) as
        | { circle_id?: string; body?: string; ai_enabled?: boolean }
        | null
        | undefined;
      if (!row?.circle_id) {
        return null;
      }
      return {
        circleId: row.circle_id,
        body: row.body ?? "",
        aiEnabled: row.ai_enabled !== false,
      };
    },
    guardConsume: async (circleId, limit) => {
      const { data, error } = await admin.rpc("ai_consume_circle_request", {
        p_circle_id: circleId,
        p_limit: limit,
      });
      if (error) {
        throw new Error(`ai_consume_circle_request: ${error.message}`);
      }
      const row = (Array.isArray(data) ? data[0] : data) as
        | { allowed?: boolean; used?: number }
        | null;
      return { allowed: row?.allowed === true, used: row?.used ?? 0 };
    },
    guardRefund: async (circleId) => {
      await admin.rpc("ai_refund_circle_request", { p_circle_id: circleId });
    },
    guardFinish: async (messageId, result) => {
      const { data, error } = await admin.rpc("finish_message_review", {
        p_message_id: messageId,
        p_verdict: result.verdict?.category ?? "not_checked",
        p_reason: result.verdict?.reason ?? null,
        p_reason_zh: result.verdict?.reasonZh ?? null,
        p_unchecked_reason: result.unchecked ?? null,
      });
      if (error) {
        throw new Error(`finish_message_review: ${error.message}`);
      }
      return typeof data === "string" ? data : null;
    },
    translations: createTranslationStore(userClient, admin),
    assistant: createAssistantStore(admin),
    actions: createActionStore(userClient),
  });
});
