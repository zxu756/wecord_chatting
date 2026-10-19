// The database side of Ask AI: the real AskStore that index.ts passes in.
// The decisions are in ask.ts and in SQL (migration 202610250300); this file
// only moves rows. Its pure parts are tested without a database. Every call
// uses the service role, with the id of the person who asked taken from their
// verified token.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { SourceMessage } from "./chat.ts";
import type { AskScope } from "./ask_request.ts";
import type { AskCandidate, AskPlace, AskStatus, AskStore } from "./ask.ts";

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

function optionalText(value: unknown): string | null {
  return typeof value === "string" && value !== "" ? value : null;
}

/// The scope as the database reads it: {type, id?}.
export function scopeJson(scope: AskScope): Record<string, unknown> {
  return scope.type === "everywhere"
    ? { type: "everywhere" }
    : { type: scope.type, id: scope.id };
}

const STATUSES: readonly AskStatus[] = [
  "ok",
  "user_off",
  "ai_off",
  "not_found",
];

/// ai_ask_scope's answer. Anything unexpected counts as "not found": the
/// person is not let in on a guess.
export function scopeFromRow(
  value: unknown,
): { status: AskStatus; conversations: number } {
  const row = asRow(value);
  const status = STATUSES.find((entry) => entry === row?.status);
  if (row === null || status === undefined) {
    return { status: "not_found", conversations: 0 };
  }
  return {
    status,
    conversations: typeof row.conversations === "number"
      ? row.conversations
      : 0,
  };
}

function placeFromJson(value: unknown): AskPlace | null {
  const row = asRow(value);
  if (row === null || typeof row.id !== "string") {
    return null;
  }
  return {
    id: row.id,
    type: text(row.type, "group"),
    title: optionalText(row.title),
    avatarUrl: optionalText(row.avatar_url),
    directUserId: optionalText(row.direct_user_id),
    circleId: optionalText(row.circle_id),
    circleName: optionalText(row.circle_name),
    channelKind: optionalText(row.channel_kind),
    parentConversationId: optionalText(row.parent_conversation_id),
    parentTitle: optionalText(row.parent_title),
  };
}

/// One row of ai_ask_search; null when it is not a message.
export function candidateFromRow(value: unknown): AskCandidate | null {
  const row = asRow(value);
  if (
    row === null || typeof row.message_id !== "string" ||
    typeof row.conversation_id !== "string"
  ) {
    return null;
  }
  const attachmentName = optionalText(row.attachment_name);
  const message: SourceMessage = {
    id: row.message_id,
    sender: text(row.sender_name, "Someone"),
    type: text(row.type, "text"),
    body: text(row.body),
    attachment: attachmentName === null ? null : { name: attachmentName },
    webhookName: optionalText(row.webhook_name),
    createdAt: text(row.created_at),
  };
  return {
    message,
    conversationId: row.conversation_id,
    place: placeFromJson(row.place),
  };
}

export function createAskStore(admin: Client): AskStore {
  return {
    scope: async (userId, scope) => {
      const { data, error } = await admin.rpc("ai_ask_scope", {
        p_user_id: userId,
        p_scope: scopeJson(scope),
      });
      if (error) {
        throw new Error(`ai_ask_scope: ${error.message}`);
      }
      return scopeFromRow(data);
    },
    search: async (userId, groups, scope, limit) => {
      const { data, error } = await admin.rpc("ai_ask_search", {
        p_user_id: userId,
        p_groups: groups,
        p_scope: scopeJson(scope),
        p_limit: limit,
      });
      if (error) {
        throw new Error(`ai_ask_search: ${error.message}`);
      }
      const candidates: AskCandidate[] = [];
      for (const row of Array.isArray(data) ? data : []) {
        const candidate = candidateFromRow(row);
        if (candidate !== null) {
          candidates.push(candidate);
        }
      }
      return candidates;
    },
    visible: async (userId, messageIds) => {
      const { data, error } = await admin.rpc("ai_ask_visible", {
        p_user_id: userId,
        p_message_ids: messageIds,
      });
      if (error) {
        throw new Error(`ai_ask_visible: ${error.message}`);
      }
      return Array.isArray(data)
        ? data.filter((id): id is string => typeof id === "string")
        : [];
    },
  };
}
