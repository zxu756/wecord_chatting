// Time tokens (`<t:unix>` or `<t:unix:F>`, styles t T d D f F R) in text the
// server builds: push titles and bodies. The app shows them in the reader's
// time zone; here the zone is the one the subscription stored, and the
// wording follows the subscription's language ('en' or 'zh'). The formats
// are the ones of formatTimeToken in
// lib/features/chats/time_tokens/time_token.dart, so a push and the chat
// read the same. Without a usable zone the time is shown in UTC and says so.

export interface TimeTokenOptions {
  /// An IANA zone such as "Asia/Shanghai"; null or unknown means UTC.
  timeZone: string | null | undefined;
  language: string | null | undefined;
  /// The current time in seconds, for relative tokens and to leave out the
  /// current year.
  nowSeconds: number;
}

/// A time token: `<t:1760000000>` or `<t:1760000000:R>`.
const tokenPattern = /<t:(-?\d{1,12})(?::([tTdDfFR]))?>/g;

/// About year 1 to 9999, so a Date never overflows.
const maxUnix = 253402300799;

const englishMonths = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];
const englishWeekdays = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];
const chineseWeekdays = ["一", "二", "三", "四", "五", "六", "日"];

/// A moment as the calendar and clock of a zone. [weekday] is 1 (Monday)
/// to 7 (Sunday).
interface Wall {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
  weekday: number;
}

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatterFor(zone: string): Intl.DateTimeFormat {
  let formatter = formatters.get(zone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: zone,
      hourCycle: "h23",
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
      weekday: "short",
    });
    formatters.set(zone, formatter);
  }
  return formatter;
}

/// [zone] when it is a time zone this runtime knows, else null.
export function validTimeZone(zone: string | null | undefined): string | null {
  if (typeof zone !== "string" || zone === "" || zone.length > 64) {
    return null;
  }
  try {
    formatterFor(zone);
    return zone;
  } catch {
    return null;
  }
}

const weekdayIndex: Record<string, number> = {
  Mon: 1,
  Tue: 2,
  Wed: 3,
  Thu: 4,
  Fri: 5,
  Sat: 6,
  Sun: 7,
};

function wallTime(unix: number, zone: string): Wall {
  const parts: Record<string, string> = {};
  for (const part of formatterFor(zone).formatToParts(new Date(unix * 1000))) {
    parts[part.type] = part.value;
  }
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    // Some runtimes write midnight as 24 even with h23.
    hour: Number(parts.hour) % 24,
    minute: Number(parts.minute),
    second: Number(parts.second),
    weekday: weekdayIndex[parts.weekday] ?? 1,
  };
}

const two = (value: number): string => String(value).padStart(2, "0");

function chinesePeriod(hour: number): string {
  if (hour < 5) return "凌晨";
  if (hour < 12) return "上午";
  if (hour < 13) return "中午";
  if (hour < 18) return "下午";
  return "晚上";
}

function clock(time: Wall, chinese: boolean, seconds: boolean): string {
  const tail = seconds ? `:${two(time.second)}` : "";
  const hour12 = time.hour % 12 === 0 ? 12 : time.hour % 12;
  const text = `${hour12}:${two(time.minute)}${tail}`;
  return chinese
    ? `${chinesePeriod(time.hour)}${text}`
    : `${text} ${time.hour < 12 ? "AM" : "PM"}`;
}

function dateShort(time: Wall, now: Wall, chinese: boolean): string {
  const sameYear = time.year === now.year;
  if (chinese) {
    return sameYear
      ? `${time.month}月${time.day}日`
      : `${time.year}年${time.month}月${time.day}日`;
  }
  const month = englishMonths[time.month - 1].slice(0, 3);
  return sameYear
    ? `${month} ${time.day}`
    : `${month} ${time.day}, ${time.year}`;
}

function dateLong(time: Wall, chinese: boolean): string {
  return chinese
    ? `${time.year}年${time.month}月${time.day}日`
    : `${englishMonths[time.month - 1]} ${time.day}, ${time.year}`;
}

function weekday(time: Wall, chinese: boolean, abbreviated = false): string {
  const index = time.weekday - 1;
  if (chinese) {
    return `${abbreviated ? "周" : "星期"}${chineseWeekdays[index]}`;
  }
  const name = englishWeekdays[index];
  return abbreviated ? name.slice(0, 3) : name;
}

/// Calendar days from [now]'s date to [time]'s date, in the zone.
function calendarDays(time: Wall, now: Wall): number {
  const day = (wall: Wall) => Date.UTC(wall.year, wall.month - 1, wall.day);
  return Math.round((day(time) - day(now)) / 86400000);
}

/// "in 2 hours", "3 days ago", "tomorrow": relativeTimeText in Dart.
export function relativeText(
  unix: number,
  nowSeconds: number,
  zone: string,
  chinese: boolean,
): string {
  const difference = unix - nowSeconds;
  const future = difference >= 0;
  const seconds = Math.abs(difference);
  const pick = (en: string, zh: string) => chinese ? zh : en;
  if (seconds < 45) {
    return future ? pick("in a moment", "稍后") : pick("just now", "刚刚");
  }
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) {
    if (future) {
      return minutes === 1
        ? pick("in 1 minute", "1 分钟后")
        : pick(`in ${minutes} minutes`, `${minutes} 分钟后`);
    }
    return minutes === 1
      ? pick("1 minute ago", "1 分钟前")
      : pick(`${minutes} minutes ago`, `${minutes} 分钟前`);
  }
  const hours = Math.round(minutes / 60);
  if (hours < 24) {
    if (future) {
      return hours === 1
        ? pick("in 1 hour", "1 小时后")
        : pick(`in ${hours} hours`, `${hours} 小时后`);
    }
    return hours === 1
      ? pick("1 hour ago", "1 小时前")
      : pick(`${hours} hours ago`, `${hours} 小时前`);
  }
  const days = calendarDays(wallTime(unix, zone), wallTime(nowSeconds, zone));
  if (days === 1) return pick("tomorrow", "明天");
  if (days === -1) return pick("yesterday", "昨天");
  const count = Math.abs(days);
  if (count < 30) {
    return days > 0
      ? pick(`in ${count} days`, `${count} 天后`)
      : pick(`${count} days ago`, `${count} 天前`);
  }
  if (count < 365) {
    const months = Math.round(count / 30);
    if (days > 0) {
      return months === 1
        ? pick("in 1 month", "1 个月后")
        : pick(`in ${months} months`, `${months} 个月后`);
    }
    return months === 1
      ? pick("1 month ago", "1 个月前")
      : pick(`${months} months ago`, `${months} 个月前`);
  }
  const years = Math.round(count / 365);
  if (days > 0) {
    return years === 1
      ? pick("in 1 year", "1 年后")
      : pick(`in ${years} years`, `${years} 年后`);
  }
  return years === 1
    ? pick("1 year ago", "1 年前")
    : pick(`${years} years ago`, `${years} 年前`);
}

/// One token as text. Without a usable zone the time is UTC and says so.
export function formatTimeToken(
  unix: number,
  style: string,
  options: TimeTokenOptions,
): string {
  const zone = validTimeZone(options.timeZone);
  const chinese = options.language === "zh";
  if (style === "R") {
    return relativeText(unix, options.nowSeconds, zone ?? "UTC", chinese);
  }
  const effective = zone ?? "UTC";
  const time = wallTime(unix, effective);
  const now = wallTime(options.nowSeconds, effective);
  let text: string;
  switch (style) {
    case "t":
      text = clock(time, chinese, false);
      break;
    case "T":
      text = clock(time, chinese, true);
      break;
    case "d":
      text = dateShort(time, now, chinese);
      break;
    case "D":
      text = dateLong(time, chinese);
      break;
    case "F": {
      const date = dateLong(time, chinese);
      const day = weekday(time, chinese);
      text = chinese
        ? `${date} ${day} ${clock(time, true, false)}`
        : `${day}, ${date} at ${clock(time, false, false)}`;
      break;
    }
    default: {
      // "f", the style a bare `<t:unix>` has.
      const date = dateShort(time, now, chinese);
      const day = weekday(time, chinese, true);
      text = chinese
        ? `${date} ${day} ${clock(time, true, false)}`
        : `${day}, ${date}, ${clock(time, false, false)}`;
    }
  }
  return zone === null ? `${text} UTC` : text;
}

/// [text] with every time token turned into its time in the subscriber's
/// zone. Text without tokens comes back as it is, and a token that is out of
/// range stays as written, as in the app.
export function replaceTimeTokens(
  text: string,
  options: TimeTokenOptions,
): string {
  if (!text.includes("<t:")) {
    return text;
  }
  return text.replace(tokenPattern, (match, unix: string, style?: string) => {
    const seconds = Number(unix);
    if (!Number.isFinite(seconds) || Math.abs(seconds) > maxUnix) {
      return match;
    }
    return formatTimeToken(seconds, style ?? "f", options);
  });
}

/// What the push functions need to know about a subscription.
export interface SubscriptionLocale {
  time_zone: string | null;
  language: string | null;
}

/// The part of the Supabase client [loadSubscriptionLocales] uses.
interface LocaleReader {
  from: (table: string) => {
    select: (columns: string) => {
      in: (
        column: string,
        values: string[],
      ) => PromiseLike<{ data: unknown; error: unknown }>;
    };
  };
}

/// Reads the zone and language of the subscriptions in [ids] (the rows the
/// claim functions return carry only the id), keyed by subscription id. A
/// failed read leaves them out, so those pushes still go with UTC times.
export async function loadSubscriptionLocales(
  // Typed loosely: the Supabase client's own type is too deep to check here.
  client: unknown,
  ids: string[],
): Promise<Map<string, SubscriptionLocale>> {
  const admin = client as LocaleReader;
  const locales = new Map<string, SubscriptionLocale>();
  const unique = [...new Set(ids)];
  for (let start = 0; start < unique.length; start += 200) {
    const { data, error } = await admin
      .from("push_subscriptions")
      .select("id, time_zone, language")
      .in("id", unique.slice(start, start + 200));
    if (error) {
      continue;
    }
    for (
      const row of (data ?? []) as (SubscriptionLocale & { id: string })[]
    ) {
      locales.set(row.id, row);
    }
  }
  return locales;
}

/// [target] with the time tokens of its title and body written out for its
/// subscription.
export function withTimesWritten<
  T extends { subscription_id: string; title: string; body: string },
>(
  target: T,
  locales: Map<string, SubscriptionLocale>,
  nowSeconds: number,
): T {
  if (!target.title.includes("<t:") && !target.body.includes("<t:")) {
    return target;
  }
  const locale = locales.get(target.subscription_id);
  const options: TimeTokenOptions = {
    timeZone: locale?.time_zone,
    language: locale?.language,
    nowSeconds,
  };
  return {
    ...target,
    title: replaceTimeTokens(target.title, options),
    body: replaceTimeTokens(target.body, options),
  };
}

/// Loads the locales of [targets] and writes out their time tokens.
export async function writeTimesForTargets<
  T extends { subscription_id: string; title: string; body: string },
>(
  admin: unknown,
  targets: T[],
  nowSeconds: number,
): Promise<T[]> {
  if (
    !targets.some((t) => t.title.includes("<t:") || t.body.includes("<t:"))
  ) {
    return targets;
  }
  const locales = await loadSubscriptionLocales(
    admin,
    targets.map((t) => t.subscription_id),
  );
  return targets.map((t) => withTimesWritten(t, locales, nowSeconds));
}
