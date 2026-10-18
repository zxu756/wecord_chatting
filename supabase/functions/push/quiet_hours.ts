// Quiet hours for the push functions (push and scheduled-dispatch).
//
// A person can switch on quiet hours (user_notification_settings): between
// two times of day, on chosen weekdays, in their time zone, nothing is pushed
// to their devices. Starred friends, @mentions of them, calls and chosen
// important contacts still break through, as far as they allow it. The inbox
// and the notification records are written elsewhere and are not touched;
// only the Web Push is held back, just before it is sent.
//
// The claim functions (claim_push_delivery and the others) are not changed:
// they already leave out Do Not Disturb and muted conversations or circles,
// so quiet hours stack with those by construction. This module only drops
// subscriptions from what they returned.
//
// The rule is the one of public.quiet_window_contains in
// supabase/migrations/202610210310_quiet_hours.sql; both are tested with the
// same cases (quiet_hours_test.ts and test/supabase/quiet_hours_behaviour.sql).
//
// It fails open: when the lookup fails every push goes out, because a missed
// message is worse than a push in quiet hours.
import { validTimeZone } from "./time_tokens.ts";

/// One subscription of a person with quiet hours on, as
/// quiet_hours_recipients answers.
export interface QuietRecipient {
  subscription_id: string;
  user_id: string;
  /// An IANA zone; unknown or missing counts as UTC.
  time_zone: string | null;
  /// ISO weekdays (1 Monday .. 7 Sunday) on which a window starts.
  quiet_days: number[] | null;
  /// "HH:MM" or "HH:MM:SS".
  quiet_start: string;
  quiet_end: string;
  /// The message is one the person lets through: a call, an @mention, a
  /// starred friend or an important contact.
  breaks_through: boolean;
}

/// What the functions need of the Supabase admin client.
export interface RpcClient {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown }>;
}

/// "HH:MM[:SS]" as seconds since midnight; null when it isn't a time.
export function clockSeconds(text: string | null | undefined): number | null {
  const match = /^(\d{1,2}):(\d{2})(?::(\d{2}))?/.exec(text ?? "");
  if (!match) {
    return null;
  }
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  const second = Number(match[3] ?? "0");
  if (hour > 24 || minute > 59 || second > 59) {
    return null;
  }
  return (hour % 24) * 3600 + minute * 60 + second;
}

const weekdayNumber: Record<string, number> = {
  Mon: 1,
  Tue: 2,
  Wed: 3,
  Thu: 4,
  Fri: 5,
  Sat: 6,
  Sun: 7,
};

const formatters = new Map<string, Intl.DateTimeFormat>();

/// The wall clock of [zone] at [unix]: seconds since local midnight and the
/// ISO weekday. The runtime's time zone data does the daylight saving.
function wallClock(
  unix: number,
  zone: string,
): { seconds: number; weekday: number } {
  let formatter = formatters.get(zone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: zone,
      hourCycle: "h23",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
      weekday: "short",
    });
    formatters.set(zone, formatter);
  }
  const parts: Record<string, string> = {};
  for (const part of formatter.formatToParts(new Date(unix * 1000))) {
    parts[part.type] = part.value;
  }
  return {
    // Some runtimes write midnight as 24 even with h23.
    seconds: (Number(parts.hour) % 24) * 3600 + Number(parts.minute) * 60 +
      Number(parts.second),
    weekday: weekdayNumber[parts.weekday] ?? 1,
  };
}

/// Whether [unix] (seconds) is inside the quiet window.
///
/// * The clock is the wall clock of the zone, so daylight saving needs no
///   special case. An unknown zone counts as UTC.
/// * [days] are the weekdays on which a window starts. A window that crosses
///   midnight (start after end) goes on into the next day, so its part after
///   midnight is quiet when the previous day is picked.
/// * start equal to end is an empty window; no days is never quiet.
export function quietWindowContains(
  zone: string | null | undefined,
  days: number[] | null | undefined,
  start: string,
  end: string,
  unix: number,
): boolean {
  const from = clockSeconds(start);
  const to = clockSeconds(end);
  if (
    from === null || to === null || from === to || !days ||
    days.length === 0
  ) {
    return false;
  }
  const { seconds, weekday } = wallClock(unix, validTimeZone(zone) ?? "UTC");
  if (from < to) {
    return days.includes(weekday) && seconds >= from && seconds < to;
  }
  const previous = weekday === 1 ? 7 : weekday - 1;
  return (seconds >= from && days.includes(weekday)) ||
    (seconds < to && days.includes(previous));
}

/// Whether a push to [recipient] is held back at [unix]: its window is on
/// and the message is not one that breaks through.
export function isHeldBack(recipient: QuietRecipient, unix: number): boolean {
  return !recipient.breaks_through && quietWindowContains(
    recipient.time_zone,
    recipient.quiet_days,
    recipient.quiet_start,
    recipient.quiet_end,
    unix,
  );
}

/// [targets] without the pushes that quiet hours hold back.
///
/// [defaultMessageId] is the message a push is about (it decides who breaks
/// through); a target can name its own `message_id`, as the scheduled
/// dispatcher does when it pushes several messages at once. Pushes that are
/// not about a message (reminders, tasks, events, Moments) have none, and
/// nothing breaks through for them.
export async function dropQuietPushes<
  T extends { subscription_id: string; message_id?: string | null },
>(
  admin: RpcClient,
  targets: T[],
  nowSeconds: number,
  defaultMessageId: string | null = null,
): Promise<T[]> {
  if (targets.length === 0) {
    return targets;
  }
  const byMessage = new Map<string | null, Set<string>>();
  for (const target of targets) {
    const message = target.message_id ?? defaultMessageId;
    const ids = byMessage.get(message) ?? new Set<string>();
    ids.add(target.subscription_id);
    byMessage.set(message, ids);
  }

  // One subscription can get several messages in a tick, some of which break
  // through, so a hold is for a subscription and a message.
  const holdKey = (message: string | null, subscription: string) =>
    `${message ?? ""}|${subscription}`;
  const held = new Set<string>();
  for (const [message, ids] of byMessage) {
    try {
      const { data, error } = await admin.rpc("quiet_hours_recipients", {
        target_subscription_ids: [...ids],
        target_message_id: message,
      });
      if (error) {
        console.error("quiet_hours_recipients failed", error);
        continue;
      }
      for (const row of (data ?? []) as QuietRecipient[]) {
        if (isHeldBack(row, nowSeconds)) {
          held.add(holdKey(message, row.subscription_id));
        }
      }
    } catch (error) {
      // Fail open: the pushes of this message go out.
      console.error("quiet_hours_recipients failed", error);
    }
  }
  if (held.size === 0) {
    return targets;
  }
  return targets.filter((target) =>
    !held.has(
      holdKey(target.message_id ?? defaultMessageId, target.subscription_id),
    )
  );
}
