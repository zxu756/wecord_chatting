// iCalendar (RFC 5545) text for the calendar subscription. The escaping,
// folding and UTC time format are the same rules as the app's
// lib/shared/calendar/ics.dart (the .ics a person downloads for one event);
// this is the same code for a feed of many events.

const encoder = new TextEncoder();

/** `20261020T150000Z`. */
export function icsUtc(value: Date): string {
  const two = (n: number) => String(n).padStart(2, "0");
  return `${String(value.getUTCFullYear()).padStart(4, "0")}${
    two(value.getUTCMonth() + 1)
  }${two(value.getUTCDate())}T${two(value.getUTCHours())}${
    two(value.getUTCMinutes())
  }${two(value.getUTCSeconds())}Z`;
}

/** `20261020`, for an all-day date given as year, month (1-12) and day. */
export function icsDate(year: number, month: number, day: number): string {
  const two = (n: number) => String(n).padStart(2, "0");
  return `${String(year).padStart(4, "0")}${two(month)}${two(day)}`;
}

/** Escapes text for a property value (RFC 5545 section 3.3.11). */
export function icsEscape(value: string): string {
  return value
    .replaceAll("\\", "\\\\")
    .replaceAll(";", "\\;")
    .replaceAll(",", "\\,")
    .replace(/\r?\n|\r/g, "\\n");
}

/**
 * Folds a line to 75 bytes, continuing on lines that start with a space,
 * without splitting a character.
 */
export function icsFold(line: string): string {
  if (encoder.encode(line).length <= 75) return line;
  let out = "";
  let lineBytes = 0;
  for (const char of line) {
    const size = encoder.encode(char).length;
    // Continuation lines carry the leading space.
    if (lineBytes + size > 75) {
      out += "\r\n ";
      lineBytes = 1;
    }
    out += char;
    lineBytes += size;
  }
  return out;
}

/** A property value that must not hold a line break or control character. */
function plain(value: string): string {
  // deno-lint-ignore no-control-regex
  return value.replace(/[\u0000-\u001f\u007f]+/g, " ").trim();
}

export type IcsEntry = {
  uid: string;
  summary: string;
  /** A moment, or an all-day date `{year, month, day}`. */
  start: Date | { year: number; month: number; day: number };
  /** Only for a moment; an all-day entry always lasts its one day. */
  end?: Date;
  description?: string;
  location?: string;
  /** Where the entry leads: the call link of a scheduled call. */
  url?: string;
  categories?: string;
  /** Tasks do not make the person busy. */
  transparent?: boolean;
};

export function buildIcsFeed(
  entries: IcsEntry[],
  options: { name: string; now: Date; productId?: string },
): string {
  const lines: string[] = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    `PRODID:${options.productId ?? "-//WeCord//Agenda//EN"}`,
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `X-WR-CALNAME:${icsEscape(plain(options.name))}`,
    "REFRESH-INTERVAL;VALUE=DURATION:PT1H",
    "X-PUBLISHED-TTL:PT1H",
  ];
  const stamp = icsUtc(options.now);
  for (const entry of entries) {
    lines.push("BEGIN:VEVENT", `UID:${entry.uid}`, `DTSTAMP:${stamp}`);
    if (entry.start instanceof Date) {
      const end = entry.end && entry.end > entry.start
        ? entry.end
        : new Date(entry.start.getTime() + 60 * 60 * 1000);
      lines.push(`DTSTART:${icsUtc(entry.start)}`, `DTEND:${icsUtc(end)}`);
    } else {
      const { year, month, day } = entry.start;
      const next = new Date(Date.UTC(year, month - 1, day + 1));
      lines.push(
        `DTSTART;VALUE=DATE:${icsDate(year, month, day)}`,
        `DTEND;VALUE=DATE:${
          icsDate(
            next.getUTCFullYear(),
            next.getUTCMonth() + 1,
            next.getUTCDate(),
          )
        }`,
      );
    }
    lines.push(`SUMMARY:${icsEscape(plain(entry.summary))}`);
    if (entry.description && entry.description.trim()) {
      lines.push(`DESCRIPTION:${icsEscape(entry.description.trim())}`);
    }
    if (entry.location && plain(entry.location)) {
      lines.push(`LOCATION:${icsEscape(plain(entry.location))}`);
    }
    if (entry.url && /^https?:\/\/\S+$/.test(entry.url)) {
      lines.push(`URL:${entry.url}`);
    }
    if (entry.categories) {
      lines.push(`CATEGORIES:${icsEscape(entry.categories)}`);
    }
    if (entry.transparent) lines.push("TRANSP:TRANSPARENT");
    lines.push("END:VEVENT");
  }
  lines.push("END:VCALENDAR");
  return `${lines.map(icsFold).join("\r\n")}\r\n`;
}
