// The calendar subscription: GET /calendar-feed/<token>.ics answers the next
// 60 days of a person's events and tasks as an iCalendar file.
//
// There is no signed-in user (Apple Calendar and Google Calendar cannot sign
// in), so the token is the credential: 192 random bits, kept by the server
// only as a SHA-256 hash, checked inside the database function
// calendar_feed_items, which also counts requests (30 an hour per token).
// By default an entry holds only its time, its kind and the conversation's
// name; titles, places and descriptions are written only when the person
// switched "Include titles and details" on.
import { DEFAULT_SITE_ORIGIN } from "../push/declarative.ts";
import { buildIcsFeed, type IcsEntry } from "./ics.ts";

export const feedDays = 60;

export type FeedItem = {
  kind: string;
  title: string | null;
  starts_at: string;
  ends_at: string | null;
  all_day: boolean;
  conversation_id: string | null;
  circle_id: string | null;
  target_id: string;
  place_name: string | null;
  subtitle: string | null;
  /** Small extras of the entry; an event with a call carries its link code. */
  meta?: { call_link_code?: string | null } | null;
};

export type FeedResult =
  | {
    status: "ok";
    include_content: boolean;
    utc_offset_minutes: number;
    language: "en" | "zh";
    items: FeedItem[];
  }
  | { status: "invalid" }
  | { status: "limited"; retry_after: number };

/** The token in `/calendar-feed/<token>.ics`, or null for any other path. */
export function tokenFromPath(pathname: string): string | null {
  const last = pathname.split("/").filter((part) => part.length > 0).pop() ??
    "";
  const match = /^([0-9a-f]{48})\.ics$/.exec(last);
  return match ? match[1] : null;
}

export async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

const labels = {
  en: {
    chat_event: "Event",
    circle_event: "Event",
    task: "Task",
    calendar: "WeCord agenda",
    fallbackPlace: "WeCord",
    joinCall: "Join the call",
  },
  zh: {
    chat_event: "活动",
    circle_event: "活动",
    task: "任务",
    calendar: "WeCord 日程",
    fallbackPlace: "WeCord",
    joinCall: "加入通话",
  },
} as const;

/**
 * An agenda row as a calendar entry. Without [includeContent] it holds the
 * kind and the conversation's name, nothing a person wrote.
 */
export function entryFor(
  item: FeedItem,
  options: {
    includeContent: boolean;
    utcOffsetMinutes: number;
    language: "en" | "zh";
    /** The site the call links of scheduled calls point at. */
    siteOrigin?: string;
  },
): IcsEntry | null {
  const text = labels[options.language];
  const start = new Date(item.starts_at);
  if (Number.isNaN(start.getTime())) return null;
  const isTask = item.kind === "task";
  const kindLabel = (text as Record<string, string>)[item.kind] ?? text.task;
  const place = item.place_name?.trim() || text.fallbackPlace;
  const title = item.title?.trim();

  const entry: IcsEntry = {
    uid: `${item.kind}-${item.target_id}@wecord`,
    summary: options.includeContent && title
      ? title
      : `${kindLabel} · ${place}`,
    start,
    categories: isTask ? "Task" : "Event",
    transparent: isTask,
  };

  if (isTask && item.all_day) {
    // A task "all day" is due at 23:59 of a day in the person's zone. Move
    // to that zone, then back six hours: the date survives an hour of
    // daylight saving drift in the stored offset.
    const local = new Date(
      start.getTime() + options.utcOffsetMinutes * 60_000 - 6 * 3_600_000,
    );
    entry.start = {
      year: local.getUTCFullYear(),
      month: local.getUTCMonth() + 1,
      day: local.getUTCDate(),
    };
  } else if (isTask) {
    // A task is a moment, not a stretch: half an hour so it can be seen.
    entry.end = new Date(start.getTime() + 30 * 60_000);
  } else if (item.ends_at) {
    const end = new Date(item.ends_at);
    if (!Number.isNaN(end.getTime())) entry.end = end;
  }

  if (options.includeContent) {
    if (item.subtitle) entry.location = item.subtitle;
    if (title && item.place_name) entry.description = item.place_name;
    // The call of a scheduled call: the way in is written only for a person
    // who asked for details, like the title is.
    const code = item.meta?.call_link_code;
    if (!isTask && typeof code === "string" && /^[a-z0-9]{12}$/.test(code)) {
      const url = `${options.siteOrigin ?? DEFAULT_SITE_ORIGIN}/call/${code}`;
      entry.url = url;
      entry.description = [entry.description, `${text.joinCall}: ${url}`]
        .filter((part) => part && part.trim())
        .join("\n");
    }
  }
  return entry;
}

export function buildFeed(
  result: Extract<FeedResult, { status: "ok" }>,
  now: Date,
  siteOrigin?: string,
): string {
  const entries: IcsEntry[] = [];
  for (const item of result.items) {
    const entry = entryFor(item, {
      includeContent: result.include_content,
      utcOffsetMinutes: result.utc_offset_minutes,
      language: result.language,
      siteOrigin,
    });
    if (entry) entries.push(entry);
  }
  return buildIcsFeed(entries, {
    name: labels[result.language].calendar,
    now,
  });
}

/** Counts events per key in a sliding window kept in memory. */
export class WindowLimiter {
  #hits = new Map<string, { start: number; count: number }>();

  constructor(
    private readonly limit: number,
    private readonly windowMs: number,
    private readonly maxKeys = 5000,
  ) {}

  /** Records one hit; false when [key] is over the limit. */
  hit(key: string, nowMs: number): boolean {
    const entry = this.#hits.get(key);
    if (!entry || nowMs - entry.start >= this.windowMs) {
      if (this.#hits.size >= this.maxKeys) this.#sweep(nowMs);
      this.#hits.set(key, { start: nowMs, count: 1 });
      return true;
    }
    entry.count++;
    return entry.count <= this.limit;
  }

  /** Whether [key] has used up its hits in the current window. */
  isBlocked(key: string, nowMs: number): boolean {
    const entry = this.#hits.get(key);
    return entry !== undefined && nowMs - entry.start < this.windowMs &&
      entry.count >= this.limit;
  }

  retryAfterSeconds(key: string, nowMs: number): number {
    const entry = this.#hits.get(key);
    if (!entry) return 1;
    return Math.max(1, Math.ceil((entry.start + this.windowMs - nowMs) / 1000));
  }

  #sweep(nowMs: number) {
    for (const [key, entry] of this.#hits) {
      if (nowMs - entry.start >= this.windowMs) this.#hits.delete(key);
    }
    // Still full of live keys: start over rather than grow without bound.
    if (this.#hits.size >= this.maxKeys) this.#hits.clear();
  }
}

export type FeedDeps = {
  /** Asks the database (calendar_feed_items) for a token's agenda. */
  lookup: (tokenHash: string, from: Date, to: Date) => Promise<FeedResult>;
  now: () => Date;
  /** Wrong tokens per address; guessing is hopeless, this only saves work. */
  badTokens: WindowLimiter;
  /** The site call links point at; the default site when missing. */
  siteOrigin?: string;
};

function headers(extra: Record<string, string> = {}): Headers {
  return new Headers({
    "Cache-Control": "private, no-store",
    "Referrer-Policy": "no-referrer",
    "X-Robots-Tag": "noindex, nofollow",
    "X-Content-Type-Options": "nosniff",
    ...extra,
  });
}

function plainResponse(status: number, body: string, extra = {}): Response {
  return new Response(body, {
    status,
    headers: headers({ "Content-Type": "text/plain; charset=utf-8", ...extra }),
  });
}

function clientAddress(request: Request): string {
  return request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    "unknown";
}

export async function handleFeedRequest(
  request: Request,
  deps: FeedDeps,
): Promise<Response> {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return plainResponse(405, "Method not allowed", { Allow: "GET, HEAD" });
  }
  const nowDate = deps.now();
  const nowMs = nowDate.getTime();
  const missKey = clientAddress(request);

  // An address that keeps sending wrong tokens is turned away without a
  // database call.
  if (deps.badTokens.isBlocked(missKey, nowMs)) {
    return plainResponse(429, "Too many requests", {
      "Retry-After": String(deps.badTokens.retryAfterSeconds(missKey, nowMs)),
    });
  }

  const token = tokenFromPath(new URL(request.url).pathname);
  if (token === null) {
    deps.badTokens.hit(missKey, nowMs);
    return plainResponse(404, "Not found");
  }

  const from = new Date(nowMs - 24 * 3_600_000);
  const to = new Date(nowMs + feedDays * 24 * 3_600_000);
  let result: FeedResult;
  try {
    result = await deps.lookup(await hashToken(token), from, to);
  } catch {
    return plainResponse(503, "Try again later", { "Retry-After": "300" });
  }

  if (result.status === "limited") {
    return plainResponse(429, "Too many requests", {
      "Retry-After": String(Math.max(1, Math.round(result.retry_after))),
    });
  }
  if (result.status !== "ok") {
    deps.badTokens.hit(missKey, nowMs);
    return plainResponse(404, "Not found");
  }

  const body = buildFeed(result, nowDate, deps.siteOrigin);
  return new Response(request.method === "HEAD" ? null : body, {
    status: 200,
    headers: headers({
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": 'inline; filename="wecord-agenda.ics"',
    }),
  });
}
