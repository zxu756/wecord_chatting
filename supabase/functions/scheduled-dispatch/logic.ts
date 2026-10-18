// Pure helpers of the scheduled-dispatch Edge Function.

export interface PushTarget {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  conversation_id: string | null;
  circle_id: string | null;
  title: string;
  body: string;
  /// Notifications with the same tag replace each other; the conversation
  /// by default.
  tag?: string;
  /// Where tapping opens the app, when it is not a chat (Moments).
  url?: string;
  /// The message a push is about, when it is one: quiet hours let calls,
  /// @mentions and starred or important senders through.
  message_id?: string;
}

/// A row of claim_moments_pushes.
export interface MomentsPushRow {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  title: string;
  body: string;
  tag: string;
  url: string;
}

/// A row of claim_chat_event_reminder_pushes.
export interface EventReminderRow {
  reminder_id: string;
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  conversation_id: string;
  event_id: string;
  title: string;
  body: string;
}

/// A row of due_list_item_reminders.
export interface TaskReminderRow {
  notification_id: string;
  user_id: string;
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  conversation_id: string;
  circle_id: string | null;
  title: string;
  body: string;
}

/// An event reminder as a push: "📅 {event}" / "Starts in 15 minutes". One
/// tag per event, so the 15 minute reminder replaces the 1 hour one.
export function eventTarget(row: EventReminderRow): PushTarget {
  return {
    subscription_id: row.subscription_id,
    endpoint: row.endpoint,
    p256dh: row.p256dh,
    auth: row.auth,
    conversation_id: row.conversation_id,
    circle_id: null,
    title: `📅 ${row.title}`,
    body: row.body,
    tag: `event-${row.event_id}`,
  };
}

/// A task reminder as a push: "Task due soon" / "{task}".
export function taskTarget(row: TaskReminderRow): PushTarget {
  return {
    subscription_id: row.subscription_id,
    endpoint: row.endpoint,
    p256dh: row.p256dh,
    auth: row.auth,
    conversation_id: row.conversation_id,
    circle_id: row.circle_id,
    title: row.title,
    body: row.body,
    tag: `task-${row.notification_id}`,
  };
}

/// A Moments like, comment or reply as a push: "{name} liked your Moment".
/// One tag per post, so several likes of it replace each other.
export function momentsTarget(row: MomentsPushRow): PushTarget {
  return {
    subscription_id: row.subscription_id,
    endpoint: row.endpoint,
    p256dh: row.p256dh,
    auth: row.auth,
    conversation_id: null,
    circle_id: null,
    title: row.title,
    body: row.body,
    tag: row.tag,
    url: row.url,
  };
}

/// Where tapping the notification opens the app (hash routes on the web),
/// the same as the push function.
export function targetPath(target: PushTarget): string {
  if (target.url) {
    return target.url;
  }
  return target.circle_id
    ? `/#/circles/${target.circle_id}?c=${target.conversation_id}`
    : `/#/chats/${target.conversation_id}`;
}

/// Whether [header] is `Bearer <secret>`, compared in constant time. An
/// empty secret (not configured) never matches.
export function isAuthorized(header: string | null, secret: string): boolean {
  if (secret === "" || header === null) {
    return false;
  }
  const expected = new TextEncoder().encode(`Bearer ${secret}`);
  const given = new TextEncoder().encode(header);
  let difference = expected.length ^ given.length;
  for (let index = 0; index < expected.length; index++) {
    difference |= expected[index] ^ (given[index] ?? 0);
  }
  return difference === 0;
}
