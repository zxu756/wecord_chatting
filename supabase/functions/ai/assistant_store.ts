// The database side of the @WeCord AI assistant and of extract_actions:
// the real AssistantStore and ActionStore that index.ts passes in, and the
// creation of the WeCord AI account. The decisions are in assistant.ts and
// extract_actions.ts (and in SQL: migrations 202610230400 to 202610230430);
// this file only moves rows. Its pure parts are tested without a database.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { SourceMessage } from "./chat.ts";
import type {
  ActionMessage,
  ActionStore,
  ConversationMember,
} from "./extract_actions.ts";
import type {
  AssistantClaim,
  AssistantContext,
  AssistantStore,
  ClaimResult,
} from "./assistant.ts";

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

/// The claim (or the reason it was skipped) in ai_assistant_claim's answer;
/// null when it is nothing.
export function claimFromRow(value: unknown): ClaimResult | null {
  const row = asRow(value);
  if (row === null) {
    return null;
  }
  if (typeof row.skipped === "string") {
    return { skipped: row.skipped };
  }
  if (typeof row.job_id !== "string" || typeof row.requester_id !== "string") {
    return null;
  }
  const claim: AssistantClaim = {
    jobId: row.job_id,
    requesterId: row.requester_id,
    requesterName: text(row.requester_name, "Someone"),
    conversationId: text(row.conversation_id),
    messageId: text(row.message_id),
    body: text(row.body),
    contextCount: typeof row.context_count === "number" ? row.context_count : 0,
    timeZone: text(row.time_zone, "UTC"),
  };
  return { claim };
}

function sourceFromRow(value: unknown): SourceMessage | null {
  const row = asRow(value);
  if (row === null || typeof row.id !== "string") {
    return null;
  }
  const attachment = asRow(row.attachment);
  return {
    id: row.id,
    sender: text(row.sender, "Someone"),
    type: text(row.type, "text"),
    body: text(row.body),
    attachment,
    webhookName: typeof row.webhook_name === "string" ? row.webhook_name : null,
    createdAt: text(row.created_at),
  };
}

/// ai_assistant_context's answer as the assistant reads it; null when the
/// requester can read nothing.
export function contextFromRow(value: unknown): AssistantContext | null {
  const row = asRow(value);
  const trigger = asRow(row?.trigger);
  if (row === null || trigger === null || typeof trigger.id !== "string") {
    return null;
  }
  const members: ConversationMember[] = [];
  if (Array.isArray(row.members)) {
    for (const entry of row.members) {
      const member = asRow(entry);
      if (member && typeof member.id === "string") {
        members.push({
          id: member.id,
          name: text(member.name, "Someone"),
          username: typeof member.username === "string"
            ? member.username
            : null,
        });
      }
    }
  }
  const recent: SourceMessage[] = [];
  if (Array.isArray(row.recent)) {
    for (const entry of row.recent) {
      const message = sourceFromRow(entry);
      if (message) {
        recent.push(message);
      }
    }
  }
  return {
    trigger: {
      id: trigger.id,
      sender: text(trigger.sender, "Someone"),
      body: text(trigger.body),
    },
    replied: sourceFromRow(row.replied),
    recent,
    members,
  };
}

/// The minimum of the Auth admin API that the account's creation uses.
export interface IdentityAdmin {
  rpc: (
    name: string,
    args?: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: { message: string } | null }>;
  auth: {
    admin: {
      createUser: (attributes: Record<string, unknown>) => PromiseLike<{
        data: { user: { id: string } | null } | null;
        error: { message: string } | null;
      }>;
      deleteUser: (id: string) => PromiseLike<unknown>;
    };
  };
}

function randomPassword(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/// Makes sure the WeCord AI account exists, creating it the first time.
///
/// SQL cannot insert into auth.users on hosted projects, so this does what
/// the `bots` function does for circle bots: a login that can never sign in
/// (banned, no real address, a random password, provider "bot" in its app
/// metadata, which only the service role can set), then
/// register_ai_assistant turns it into the assistant's profile. Calls that
/// race each other end up with one account: the loser's login is deleted.
export async function ensureAssistantIdentity(
  admin: IdentityAdmin,
): Promise<string> {
  const existing = await admin.rpc("ai_assistant_user_id");
  if (existing.error) {
    throw new Error(`ai_assistant_user_id: ${existing.error.message}`);
  }
  if (typeof existing.data === "string") {
    return existing.data;
  }

  const created = await admin.auth.admin.createUser({
    email: `wecord-ai-${crypto.randomUUID()}@bots.wecord.invalid`,
    password: randomPassword(),
    email_confirm: true,
    ban_duration: "876000h",
    app_metadata: { provider: "bot", providers: ["bot"] },
    user_metadata: { bot: true, display_name: "WeCord AI" },
  });
  const loginId = created.data?.user?.id;
  if (created.error || !loginId) {
    throw new Error(
      `create the assistant's login: ${created.error?.message ?? "no user"}`,
    );
  }

  const registered = await admin.rpc("register_ai_assistant", {
    p_user_id: loginId,
  });
  if (registered.error || typeof registered.data !== "string") {
    await admin.auth.admin.deleteUser(loginId);
    throw new Error(
      `register_ai_assistant: ${registered.error?.message ?? "no id"}`,
    );
  }
  if (registered.data !== loginId) {
    // Another call was first; this login is surplus.
    await admin.auth.admin.deleteUser(loginId);
  }
  return registered.data;
}

/// The assistant's jobs, through the service role.
export function createAssistantStore(admin: Client): AssistantStore {
  return {
    claim: async (jobId) => {
      const { data, error } = await admin.rpc("ai_assistant_claim", {
        p_job_id: jobId,
      });
      if (error) {
        throw new Error(`ai_assistant_claim: ${error.message}`);
      }
      return claimFromRow(data);
    },
    context: async (jobId) => {
      const { data, error } = await admin.rpc("ai_assistant_context", {
        p_job_id: jobId,
      });
      if (error) {
        throw new Error(`ai_assistant_context: ${error.message}`);
      }
      return contextFromRow(data);
    },
    ensureIdentity: async () => {
      await ensureAssistantIdentity(admin as unknown as IdentityAdmin);
    },
    reply: async (jobId, body, kind, items) => {
      const { data, error } = await admin.rpc("ai_assistant_reply", {
        p_job_id: jobId,
        p_body: body,
        p_kind: kind,
        p_items: items,
      });
      if (error) {
        throw new Error(`ai_assistant_reply: ${error.message}`);
      }
      return typeof data === "string" ? data : null;
    },
    finish: async (jobId, status, reason) => {
      const { error } = await admin.rpc("ai_assistant_finish", {
        p_job_id: jobId,
        p_status: status,
        p_reason: reason,
      });
      if (error) {
        throw new Error(`ai_assistant_finish: ${error.message}`);
      }
    },
  };
}

/// What extract_actions reads, as the caller (row level security decides
/// what exists for them).
export function createActionStore(userClient: Client): ActionStore {
  return {
    aiEnabled: async (userId) => {
      const { data } = await userClient
        .from("user_ai_settings")
        .select("ai_enabled")
        .eq("user_id", userId)
        .maybeSingle();
      const value = (data as { ai_enabled?: boolean | null } | null)
        ?.ai_enabled;
      return typeof value === "boolean" ? value : null;
    },
    loadMessages: async (_userId, conversationId, ids) => {
      const { data, error } = await userClient
        .from("messages")
        .select(
          "id,sender_id,type,body,attachment,webhook_name,created_at,recalled_at,expires_at,review_state",
        )
        .eq("conversation_id", conversationId)
        .in("id", ids);
      if (error) {
        throw new Error(`messages: ${error.message}`);
      }
      const rows = (data ?? []) as Row[];
      const names = await profileNames(
        userClient,
        [...new Set(rows.map((row) => text(row.sender_id)))],
      );
      return rows.map((row): ActionMessage => ({
        id: text(row.id),
        sender: names.get(text(row.sender_id)) ?? "Someone",
        type: text(row.type, "text"),
        body: text(row.body),
        attachment: asRow(row.attachment),
        webhookName: typeof row.webhook_name === "string"
          ? row.webhook_name
          : null,
        createdAt: text(row.created_at),
        recalledAt: typeof row.recalled_at === "string"
          ? row.recalled_at
          : null,
        expiresAt: typeof row.expires_at === "string" ? row.expires_at : null,
        reviewState: typeof row.review_state === "string"
          ? row.review_state
          : null,
      }));
    },
    loadMembers: async (_userId, conversationId) => {
      const { data: memberRows, error } = await userClient
        .from("conversation_members")
        .select("user_id")
        .eq("conversation_id", conversationId)
        .limit(200);
      if (error) {
        throw new Error(`conversation_members: ${error.message}`);
      }
      const ids = ((memberRows ?? []) as Row[]).map((row) => text(row.user_id));
      if (ids.length === 0) {
        return [];
      }
      const { data: profiles } = await userClient
        .from("profiles")
        .select("id,display_name,username,is_bot")
        .in("id", ids);
      const members: ConversationMember[] = [];
      for (const profile of (profiles ?? []) as Row[]) {
        if (profile.is_bot === true) {
          continue;
        }
        members.push({
          id: text(profile.id),
          name: text(profile.display_name).trim() ||
            text(profile.username, "Someone"),
          username: typeof profile.username === "string"
            ? profile.username
            : null,
        });
      }
      return members;
    },
  };
}

async function profileNames(
  client: Client,
  ids: string[],
): Promise<Map<string, string>> {
  const names = new Map<string, string>();
  if (ids.length === 0) {
    return names;
  }
  const { data } = await client
    .from("profiles")
    .select("id,display_name,username")
    .in("id", ids);
  for (const profile of (data ?? []) as Row[]) {
    names.set(
      text(profile.id),
      text(profile.display_name).trim() || text(profile.username, "Someone"),
    );
  }
  return names;
}
