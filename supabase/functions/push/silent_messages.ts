// Silent messages for the push functions (push and scheduled-dispatch).
//
// A message sent with "send silently" (messages.silent, migration
// 202610240500) is stored and shown like any other and counts as unread, but
// nobody's device is told about it. The claim functions (claim_push_delivery
// and the others) are not changed: this module drops the pushes about silent
// messages from what they returned, just before sending. Web Push has a
// `silent` flag, but Safari ignores it and would still ring, so the push is
// not sent at all.
//
// It fails open, like quiet hours: when the lookup fails the pushes go out,
// because a missed message is worse than a push that rang.
import type { RpcClient } from "./quiet_hours.ts";

/// [targets] without the pushes about silent messages.
///
/// [defaultMessageId] is the message a push is about; a target can name its
/// own `message_id`, as the scheduled dispatcher does. Pushes that are not
/// about a message have none and are never dropped.
export async function dropSilentPushes<
  T extends { subscription_id: string; message_id?: string | null },
>(
  admin: RpcClient,
  targets: T[],
  defaultMessageId: string | null = null,
): Promise<T[]> {
  const ids = new Set<string>();
  for (const target of targets) {
    const message = target.message_id ?? defaultMessageId;
    if (message) {
      ids.add(message);
    }
  }
  if (ids.size === 0) {
    return targets;
  }
  try {
    const { data, error } = await admin.rpc("silent_message_ids", {
      message_ids: [...ids],
    });
    if (error) {
      console.error("silent_message_ids failed", error);
      return targets;
    }
    const silent = new Set((data ?? []) as string[]);
    if (silent.size === 0) {
      return targets;
    }
    return targets.filter((target) => {
      const message = target.message_id ?? defaultMessageId;
      return !message || !silent.has(message);
    });
  } catch (error) {
    console.error("silent_message_ids failed", error);
    return targets;
  }
}
