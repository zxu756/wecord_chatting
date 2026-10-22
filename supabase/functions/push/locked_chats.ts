// Locked chats for the push functions (push, scheduled-dispatch and
// chat-event-reminders).
//
// A person can lock a chat on their devices (app lock and chat lock, roadmap
// G2). The lock screen is the place a borrowed phone is read, so a push about
// a locked chat says only that something came: no sender, no text, no chat
// name. The claim functions (claim_push_delivery and the others) are not
// changed; this module swaps the title and body of the pushes they returned,
// just before sending, with what locked_chat_push_text (migration
// 202610260300) answers, worded in each subscription's own language.
//
// Tapping the push still opens the chat; the app asks for the unlock there.
//
// It fails CLOSED on the words, not on the delivery: when the lookup fails
// every push that belongs to a chat goes out with a plain, bilingual notice
// instead of its real text. A missed message is worse than a push that is
// less specific, but a locked chat's words on a lock screen are worse still.
import { isCallPath } from "./call_path.ts";
import type { RpcClient } from "./quiet_hours.ts";

/// What the function needs of a push target.
export interface MaskableTarget {
  subscription_id: string;
  conversation_id?: string | null;
  title: string;
  body: string;
  /// Where the push opens, when it is not the chat. A call link (scheduled
  /// calls) is swapped for the chat when the chat is locked.
  url?: string | null;
  /// The call link code of an event reminder (scheduled calls).
  call_link_code?: string | null;
}

/// The words used when the lookup fails and nothing is known about the
/// subscription's language.
export const FALLBACK_TITLE = "WeCord";
export const FALLBACK_BODY = "New message · 新消息";

interface MaskRow {
  subscription_id: string;
  conversation_id: string;
  title: string;
  body: string;
}

function keyOf(subscriptionId: string, conversationId: string): string {
  return `${subscriptionId}|${conversationId}`;
}

/// [targets] with the title and body replaced where the subscription's
/// person locked the chat the push is about. Targets that are not about a
/// chat (Moments, tasks without a chat, announcements) are never touched.
export async function maskLockedPushes<T extends MaskableTarget>(
  admin: RpcClient,
  targets: T[],
): Promise<T[]> {
  const pairs = targets.filter((target) => target.conversation_id).map(
    (target) => ({
      subscription_id: target.subscription_id,
      conversation_id: target.conversation_id as string,
    }),
  );
  if (pairs.length === 0) {
    return targets;
  }
  let rows: MaskRow[] | null = null;
  try {
    const { data, error } = await admin.rpc("locked_chat_push_text", {
      target_pairs: pairs,
    });
    if (error) {
      console.error("locked_chat_push_text failed", error);
    } else {
      rows = (data ?? []) as MaskRow[];
    }
  } catch (error) {
    console.error("locked_chat_push_text failed", error);
  }

  if (rows === null) {
    return targets.map((target) =>
      target.conversation_id
        ? withoutCall({ ...target, title: FALLBACK_TITLE, body: FALLBACK_BODY })
        : target
    );
  }
  if (rows.length === 0) {
    return targets;
  }
  const masks = new Map<string, MaskRow>();
  for (const row of rows) {
    masks.set(keyOf(row.subscription_id, row.conversation_id), row);
  }
  return targets.map((target) => {
    const mask = target.conversation_id
      ? masks.get(keyOf(target.subscription_id, target.conversation_id))
      : undefined;
    if (!mask) {
      return target;
    }
    return withoutCall({ ...target, title: mask.title, body: mask.body });
  });
}

/// [target] without the call link of a scheduled call: a locked chat's
/// reminder opens the chat (where the app asks for the unlock), not the call.
function withoutCall<T extends MaskableTarget>(target: T): T {
  if (!isCallPath(target.url) && !target.call_link_code) {
    return target;
  }
  const { url: _url, ...rest } = target;
  return { ...rest, call_link_code: null } as unknown as T;
}
