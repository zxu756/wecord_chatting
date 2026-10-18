// The database side of translate_batch. Messages, cached translations and the
// person's choices are read with the caller's own Supabase client, so row
// level security decides what is visible; translations are written with the
// service role through store_message_translations, which refuses text that
// has changed since it was translated.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { TranslationStore } from "./translate_batch.ts";

// deno-lint-ignore no-explicit-any
type Client = SupabaseClient<any, any, any>;

export function createTranslationStore(
  userClient: Client,
  admin: Client,
): TranslationStore {
  return {
    loadSettings: async (userId) => {
      const { data, error } = await userClient
        .from("user_ai_settings")
        .select("ai_enabled,no_translate_langs")
        .eq("user_id", userId)
        .maybeSingle();
      if (error) {
        throw new Error(`user_ai_settings: ${error.message}`);
      }
      if (!data) {
        return null;
      }
      return {
        aiEnabled: typeof data.ai_enabled === "boolean"
          ? data.ai_enabled
          : null,
        noTranslate: Array.isArray(data.no_translate_langs)
          ? (data.no_translate_langs as unknown[]).filter((
            value,
          ): value is string => typeof value === "string")
          : [],
      };
    },
    loadMessages: async (_userId, conversationId, ids) => {
      const { data, error } = await userClient
        .from("messages")
        .select("id,type,body,recalled_at,expires_at,review_state")
        .eq("conversation_id", conversationId)
        .in("id", ids);
      if (error) {
        throw new Error(`messages: ${error.message}`);
      }
      return (data ?? []).map((row) => ({
        id: row.id as string,
        type: row.type as string,
        body: (row.body as string | null) ?? "",
        recalledAt: (row.recalled_at as string | null) ?? null,
        expiresAt: (row.expires_at as string | null) ?? null,
        reviewState: (row.review_state as string | null) ?? null,
      }));
    },
    loadCached: async (_userId, ids, target) => {
      const { data, error } = await userClient
        .from("message_translations")
        .select("message_id,text,source_lang")
        .eq("target_lang", target)
        .in("message_id", ids);
      if (error) {
        throw new Error(`message_translations: ${error.message}`);
      }
      return (data ?? []).map((row) => ({
        messageId: row.message_id as string,
        text: row.text as string,
        sourceLang: (row.source_lang as string | null) ?? null,
      }));
    },
    save: async (target, rows) => {
      const { error } = await admin.rpc("store_message_translations", {
        p_rows: rows.map((row) => ({
          message_id: row.messageId,
          target_lang: target,
          text: row.text,
          source_lang: row.sourceLang,
          model: row.model,
          source_text: row.sourceText,
        })),
      });
      if (error) {
        throw new Error(`store_message_translations: ${error.message}`);
      }
    },
  };
}
