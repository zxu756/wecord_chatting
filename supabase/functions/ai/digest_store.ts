// The database side of the daily digest: the real DigestStore that index.ts
// passes in. The decisions are in digest.ts and in SQL (migrations
// 202610230500 to 202610230540); this file only moves rows. Its pure parts are
// tested without a database.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { SourceMessage } from "./chat.ts";
import type {
  DigestChat,
  DigestClaimResult,
  DigestItem,
  DigestStore,
} from "./digest.ts";

type Row = Record<string, unknown>;
// deno-lint-ignore no-explicit-any
type Client = SupabaseClient<any, any, any>;

function asRow(value: unknown): Row | null {
  const row = Array.isArray(value) ? value[0] : value;
  return row !== null && typeof row === "object" && !Array.isArray(row)
    ? row as Row
    : null;
}

function text(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

/// The claim (or the reason it was skipped) in ai_digest_claim's answer; null
/// when it is nothing.
export function digestClaimFromRow(value: unknown): DigestClaimResult | null {
  const row = asRow(value);
  if (row === null) {
    return null;
  }
  if (typeof row.skipped === "string") {
    return { skipped: row.skipped };
  }
  if (typeof row.digest_id !== "string" || typeof row.user_id !== "string") {
    return null;
  }
  return {
    claim: {
      digestId: row.digest_id,
      userId: row.user_id,
      language: row.language === "zh" ? "zh" : "en",
      timeZone: text(row.time_zone, "UTC"),
    },
  };
}

function messageFromRow(value: unknown): SourceMessage | null {
  const row = asRow(value);
  if (row === null || typeof row.id !== "string") {
    return null;
  }
  return {
    id: row.id,
    sender: text(row.sender, "Someone"),
    type: text(row.type, "text"),
    body: text(row.body),
    attachment: asRow(row.attachment),
    webhookName: typeof row.webhook_name === "string" ? row.webhook_name : null,
    createdAt: text(row.created_at),
  };
}

/// ai_digest_context's answer as the digest reads it; null when the digest is
/// not running.
export function digestContextFromRow(value: unknown): DigestChat[] | null {
  const row = asRow(value);
  if (row === null || !Array.isArray(row.conversations)) {
    return null;
  }
  const chats: DigestChat[] = [];
  for (const entry of row.conversations) {
    const chat = asRow(entry);
    if (chat === null || typeof chat.conversation_id !== "string") {
      continue;
    }
    const messages: SourceMessage[] = [];
    if (Array.isArray(chat.messages)) {
      for (const message of chat.messages) {
        const parsed = messageFromRow(message);
        if (parsed) {
          messages.push(parsed);
        }
      }
    }
    chats.push({
      conversationId: chat.conversation_id,
      title: text(chat.title),
      circleName: typeof chat.circle_name === "string"
        ? chat.circle_name
        : null,
      total: typeof chat.total === "number" ? chat.total : messages.length,
      messages,
    });
  }
  return chats;
}

/// The card as ai_digest_finish takes it.
export function digestItemsToRows(items: DigestItem[]): Row[] {
  return items.map((item) => ({
    conversation_id: item.conversationId,
    summary: item.summary,
    message_count: item.messageCount,
  }));
}

/// The digest's rows, through the service role.
export function createDigestStore(admin: Client): DigestStore {
  return {
    claim: async (digestId) => {
      const { data, error } = await admin.rpc("ai_digest_claim", {
        p_digest_id: digestId,
      });
      if (error) {
        throw new Error(`ai_digest_claim: ${error.message}`);
      }
      return digestClaimFromRow(data);
    },
    context: async (digestId) => {
      const { data, error } = await admin.rpc("ai_digest_context", {
        p_digest_id: digestId,
      });
      if (error) {
        throw new Error(`ai_digest_context: ${error.message}`);
      }
      return digestContextFromRow(data);
    },
    finish: async (digestId, items) => {
      const { data, error } = await admin.rpc("ai_digest_finish", {
        p_digest_id: digestId,
        p_items: digestItemsToRows(items),
      });
      if (error) {
        throw new Error(`ai_digest_finish: ${error.message}`);
      }
      return data === true;
    },
    close: async (digestId, status, reason) => {
      const { error } = await admin.rpc("ai_digest_close", {
        p_digest_id: digestId,
        p_status: status,
        p_reason: reason,
      });
      if (error) {
        throw new Error(`ai_digest_close: ${error.message}`);
      }
    },
  };
}
