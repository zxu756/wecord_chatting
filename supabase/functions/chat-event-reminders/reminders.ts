// The parts of the chat-event-reminders function that need no network.
import { callPath } from "../push/call_path.ts";

/** One device to push a reminder to, as claim_chat_event_reminder_pushes
 * returns it. */
export interface ReminderTarget {
  reminder_id: string;
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  conversation_id: string;
  event_id: string;
  title: string;
  body: string;
  /** The event's call link code, for a reminder sent in the last 20 minutes
   * before an event with a call (scheduled calls); otherwise null. */
  call_link_code?: string | null;
  /** Set by the sender: where the push opens, when it is not the chat. */
  url?: string;
}

/** Where tapping the notification opens the app (hash routes on the web): the
 * event's call when it has one and the reminder is the last one, else its
 * chat. */
export function reminderPath(target: ReminderTarget): string {
  return callPath(target.call_link_code) ??
    `/#/chats/${target.conversation_id}`;
}

/** What the push shows. The tag groups a person's reminders for one event so
 * the 1 hour one is replaced by the 15 minute one. */
export function reminderPayload(target: ReminderTarget) {
  return {
    title: `📅 ${target.title}`,
    body: target.body,
    tag: `event-${target.event_id}`,
    url: reminderPath(target),
  };
}

/** Whether [token] is the service role key (the only caller allowed). */
export function isSchedulerToken(
  authorization: string | null,
  serviceRoleKey: string | undefined,
): boolean {
  if (!authorization || !serviceRoleKey) return false;
  const match = /^Bearer\s+(.+)$/i.exec(authorization.trim());
  return match !== null && match[1] === serviceRoleKey;
}
