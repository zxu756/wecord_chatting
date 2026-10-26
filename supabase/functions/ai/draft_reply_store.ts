// The database side of "Help me reply": the real DraftReplyStore that
// index.ts passes in. The decisions are in SQL (migration 202610280800,
// ai_draft_context); this file only moves rows. Its pure parts are tested
// without a database. The call uses the service role, with the id of the
// person who asked taken from their verified token.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type {
  DraftReplyContext,
  DraftReplyStatus,
  DraftReplyStore,
  DraftSourceMessage,
} from "./draft_reply.ts";

type Row = Record<string, unknown>;
// deno-lint-ignore no-explicit-any
type Client = SupabaseClient<any, any, any>;

const STATUSES: readonly DraftReplyStatus[] = [
  "ok",
  "user_off",
  "ai_off",
  "locked",
  "not_found",
];

function asRow(value: unknown): Row | null {
  const row = Array.isArray(value) ? value[0] : value;
  return row !== null && typeof row === "object" && !Array.isArray(row)
    ? row as Row
    : null;
}

function text(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

/// One message of ai_draft_context; null when it is not one.
export function messageFromRow(value: unknown): DraftSourceMessage | null {
  const row = asRow(value);
  if (row === null || typeof row.id !== "string") {
    return null;
  }
  const attachmentName =
    typeof row.attachment_name === "string" && row.attachment_name !== ""
      ? row.attachment_name
      : null;
  return {
    id: row.id,
    sender: text(row.sender, "Someone"),
    mine: row.mine === true,
    type: text(row.type, "text"),
    body: text(row.body),
    attachment: attachmentName === null ? null : { name: attachmentName },
    webhookName: typeof row.webhook_name === "string" && row.webhook_name !== ""
      ? row.webhook_name
      : null,
    createdAt: text(row.created_at),
  };
}

/// ai_draft_context's answer. Anything unexpected counts as "not found": the
/// person is not let in on a guess.
export function contextFromRow(value: unknown): DraftReplyContext {
  const row = asRow(value);
  const status = STATUSES.find((entry) => entry === row?.status);
  if (row === null || status === undefined) {
    return { status: "not_found", messages: [] };
  }
  const messages: DraftSourceMessage[] = [];
  if (status === "ok" && Array.isArray(row.messages)) {
    for (const item of row.messages) {
      const message = messageFromRow(item);
      if (message !== null) {
        messages.push(message);
      }
    }
  }
  return { status, messages };
}

export function createDraftReplyStore(admin: Client): DraftReplyStore {
  return {
    context: async (userId, conversationId, limit) => {
      const { data, error } = await admin.rpc("ai_draft_context", {
        p_user_id: userId,
        p_conversation_id: conversationId,
        p_limit: limit,
      });
      if (error) {
        throw new Error(`ai_draft_context: ${error.message}`);
      }
      return contextFromRow(data);
    },
  };
}
