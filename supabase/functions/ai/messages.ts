// Reads the messages a summary covers with the caller's own Supabase
// client, so row level security decides what is visible: nothing the
// caller cannot see in the app reaches the model.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { SourceMessage } from "./chat.ts";
import { DEFAULT_RECENT_MESSAGES } from "./request.ts";
import type { ConversationMessages } from "./handler.ts";

interface MessageRow {
  id: string;
  sender_id: string;
  type: string;
  body: string | null;
  attachment: Record<string, unknown> | null;
  webhook_name: string | null;
  created_at: string;
}

const COLUMNS = "id,sender_id,type,body,attachment,webhook_name,created_at";

export async function loadMessages(
  // deno-lint-ignore no-explicit-any
  client: SupabaseClient<any, any, any>,
  options: {
    userId: string;
    conversationId: string;
    afterMessageId: string | null | undefined;
    recent: boolean;
    limit: number;
  },
): Promise<ConversationMessages | null> {
  const { data: conversation } = await client
    .from("conversations")
    .select("id")
    .eq("id", options.conversationId)
    .maybeSingle();
  if (!conversation) {
    return null;
  }

  // Where the unread messages start: the reader's last read message, as
  // the app remembered it when the chat opened, or as stored now.
  let anchorId: string | null = null;
  if (!options.recent) {
    if (options.afterMessageId !== undefined) {
      anchorId = options.afterMessageId;
    } else {
      const { data: member } = await client
        .from("conversation_members")
        .select("last_read_message_id")
        .eq("conversation_id", options.conversationId)
        .eq("user_id", options.userId)
        .maybeSingle();
      anchorId = (member?.last_read_message_id as string | null) ?? null;
    }
  }
  let anchorTime: string | null = null;
  let recent = options.recent;
  if (anchorId !== null) {
    const { data: anchor } = await client
      .from("messages")
      .select("created_at")
      .eq("id", anchorId)
      .eq("conversation_id", options.conversationId)
      .maybeSingle();
    if (anchor?.created_at) {
      anchorTime = anchor.created_at as string;
    } else {
      // The marker's message is gone: the latest messages are the best
      // stand-in.
      recent = true;
    }
  }
  const limit = recent
    ? Math.min(options.limit, DEFAULT_RECENT_MESSAGES)
    : options.limit;

  let query = client
    .from("messages")
    .select(COLUMNS, { count: "exact" })
    .eq("conversation_id", options.conversationId)
    .is("recalled_at", null);
  if (anchorTime !== null) {
    query = query.gt("created_at", anchorTime);
  }
  const { data, count, error } = await query
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(limit);
  if (error) {
    throw new Error(`messages: ${error.message}`);
  }
  const rows = ((data ?? []) as MessageRow[]).reverse();
  const total = recent ? rows.length : Math.max(count ?? 0, rows.length);

  let firstMessageId: string | null = rows[0]?.id ?? null;
  if (!recent && total > rows.length) {
    let first = client
      .from("messages")
      .select("id")
      .eq("conversation_id", options.conversationId)
      .is("recalled_at", null);
    if (anchorTime !== null) {
      first = first.gt("created_at", anchorTime);
    }
    const { data: firstRow } = await first
      .order("created_at", { ascending: true })
      .order("id", { ascending: true })
      .limit(1)
      .maybeSingle();
    firstMessageId = (firstRow?.id as string | undefined) ?? firstMessageId;
  }

  const senderIds = [...new Set(rows.map((row) => row.sender_id))];
  const names = new Map<string, string>();
  if (senderIds.length > 0) {
    const { data: profiles } = await client
      .from("profiles")
      .select("id,display_name,username")
      .in("id", senderIds);
    for (
      const profile of (profiles ?? []) as {
        id: string;
        display_name: string | null;
        username: string | null;
      }[]
    ) {
      names.set(
        profile.id,
        profile.display_name?.trim() || profile.username || "Someone",
      );
    }
  }

  const messages: SourceMessage[] = rows.map((row) => ({
    id: row.id,
    sender: names.get(row.sender_id) ?? "Someone",
    type: row.type,
    body: row.body ?? "",
    attachment: row.attachment,
    webhookName: row.webhook_name,
    createdAt: row.created_at,
  }));
  return { messages, total, firstMessageId, recent };
}
