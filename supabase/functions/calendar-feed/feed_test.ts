import {
  assert,
  assertEquals,
  assertFalse,
  assertStringIncludes,
} from "jsr:@std/assert@1";
import {
  buildFeed,
  type FeedItem,
  type FeedResult,
  handleFeedRequest,
  hashToken,
  tokenFromPath,
  WindowLimiter,
} from "./feed.ts";
import { buildIcsFeed, icsEscape, icsFold, icsUtc } from "./ics.ts";

const now = new Date("2026-10-20T08:00:00Z");
const token = "0123456789abcdef0123456789abcdef0123456789abcdef";

function item(partial: Partial<FeedItem>): FeedItem {
  return {
    kind: "chat_event",
    title: "Bouldering night",
    starts_at: "2026-10-22T18:00:00+00:00",
    ends_at: "2026-10-22T20:00:00+00:00",
    all_day: false,
    conversation_id: "c-1",
    circle_id: null,
    target_id: "e-1",
    place_name: "Climbing crew",
    subtitle: "The gym, 5th street",
    ...partial,
  };
}

function okResult(
  items: FeedItem[],
  extra: Partial<Extract<FeedResult, { status: "ok" }>> = {},
): Extract<FeedResult, { status: "ok" }> {
  return {
    status: "ok",
    include_content: false,
    utc_offset_minutes: 0,
    language: "en",
    items,
    ...extra,
  };
}

/** Unfolds the lines of an .ics and checks the RFC 5545 shape of a feed. */
function parseAndValidate(text: string): string[][] {
  assert(text.endsWith("\r\n"), "ends with CRLF");
  assertFalse(/[^\r]\n/.test(text), "only CRLF line breaks");
  const physical = text.split("\r\n");
  physical.pop();
  const encoder = new TextEncoder();
  for (const line of physical) {
    assert(encoder.encode(line).length <= 75, `line over 75 bytes: ${line}`);
  }
  const lines: string[] = [];
  for (const line of physical) {
    if (line.startsWith(" ")) {
      lines[lines.length - 1] += line.slice(1);
    } else {
      lines.push(line);
    }
  }
  assertEquals(lines[0], "BEGIN:VCALENDAR");
  assertEquals(lines.at(-1), "END:VCALENDAR");
  assert(lines.includes("VERSION:2.0"));
  assert(lines.some((line) => line.startsWith("PRODID:")));

  const events: string[][] = [];
  let current: string[] | null = null;
  const uids = new Set<string>();
  for (const line of lines.slice(1, -1)) {
    if (line === "BEGIN:VEVENT") {
      assertEquals(current, null, "nested VEVENT");
      current = [];
    } else if (line === "END:VEVENT") {
      assert(current, "END:VEVENT without BEGIN");
      const names = current.map((entry) => entry.split(/[:;]/)[0]);
      for (const required of ["UID", "DTSTAMP", "DTSTART", "SUMMARY"]) {
        assert(names.includes(required), `VEVENT lacks ${required}`);
      }
      assert(
        names.includes("DTEND"),
        "VEVENT has DTEND (events and tasks both last)",
      );
      const uid = current.find((entry) => entry.startsWith("UID:"))!;
      assertFalse(uids.has(uid), "UIDs are unique");
      uids.add(uid);
      events.push(current);
      current = null;
    } else if (current) {
      assertFalse(line.startsWith("BEGIN:"), "no other components");
      current.push(line);
    }
  }
  assertEquals(current, null, "unclosed VEVENT");
  return events;
}

Deno.test("tokenFromPath reads only a 48-character hex token with .ics", () => {
  assertEquals(tokenFromPath(`/calendar-feed/${token}.ics`), token);
  assertEquals(
    tokenFromPath(`/functions/v1/calendar-feed/${token}.ics`),
    token,
  );
  assertEquals(tokenFromPath(`/${token}.ics`), token);
  assertEquals(tokenFromPath(`/calendar-feed/${token}`), null);
  assertEquals(tokenFromPath(`/calendar-feed/${token}.ics/extra`), null);
  assertEquals(
    tokenFromPath(`/calendar-feed/${token.toUpperCase()}.ics`),
    null,
  );
  assertEquals(tokenFromPath(`/calendar-feed/${token.slice(1)}.ics`), null);
  assertEquals(tokenFromPath(`/calendar-feed/${token}0.ics`), null);
  assertEquals(tokenFromPath("/calendar-feed/"), null);
  assertEquals(tokenFromPath("/"), null);
});

Deno.test("hashToken is the SHA-256 hex the database computes", async () => {
  assertEquals(
    await hashToken("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
});

Deno.test("text is escaped, folded at 75 bytes and never split mid-character", () => {
  assertEquals(icsEscape("a,b;c\\d\ne"), "a\\,b\\;c\\\\d\\ne");
  assertEquals(icsEscape("one\r\ntwo\rthree"), "one\\ntwo\\nthree");
  assertEquals(icsUtc(new Date("2026-10-20T15:00:00Z")), "20261020T150000Z");

  const long = "SUMMARY:" + "活动".repeat(40);
  const folded = icsFold(long);
  const physical = folded.split("\r\n");
  assert(physical.length > 1);
  for (const line of physical) {
    assert(new TextEncoder().encode(line).length <= 75);
  }
  // Unfolding gives the line back, with every character whole.
  assertEquals(
    physical.map((line, index) => index === 0 ? line : line.slice(1)).join(""),
    long,
  );
  assertEquals(icsFold("short"), "short");
});

Deno.test("a feed is a valid VCALENDAR with unique UIDs", () => {
  const feed = buildFeed(
    okResult([
      item({}),
      item({ kind: "circle_event", target_id: "e-2", circle_id: "k-1" }),
      item({
        kind: "task",
        target_id: "t-1",
        ends_at: null,
        starts_at: "2026-10-23T09:00:00+00:00",
      }),
    ]),
    now,
  );
  const events = parseAndValidate(feed);
  assertEquals(events.length, 3);
  assertStringIncludes(feed, "DTSTAMP:20261020T080000Z");
  assertStringIncludes(feed, "DTSTART:20261022T180000Z");
  assertStringIncludes(feed, "DTEND:20261022T200000Z");
  assertStringIncludes(feed, "UID:chat_event-e-1@wecord");
  assertStringIncludes(feed, "UID:task-t-1@wecord");
  assertStringIncludes(feed, "METHOD:PUBLISH");
});

Deno.test("an empty feed is still a valid calendar", () => {
  const feed = buildFeed(okResult([]), now);
  assertEquals(parseAndValidate(feed).length, 0);
});

Deno.test("by default only the kind, the time and the conversation name appear", () => {
  const feed = buildFeed(
    okResult([
      item({ title: "Secret surprise party", subtitle: "Ada's flat" }),
      item({
        kind: "task",
        target_id: "t-1",
        title: "Buy the cake, with candles",
        ends_at: null,
        place_name: "Climbing crew",
      }),
    ]),
    now,
  );
  assertStringIncludes(feed, "SUMMARY:Event · Climbing crew");
  assertStringIncludes(feed, "SUMMARY:Task · Climbing crew");
  for (const secret of ["surprise", "party", "Ada", "cake", "candles", "5th"]) {
    assertFalse(feed.includes(secret), `the feed leaks ${secret}`);
  }
  assertFalse(feed.includes("DESCRIPTION"));
  assertFalse(feed.includes("LOCATION"));
});

Deno.test("with the switch on titles and places are written, escaped", () => {
  const feed = buildFeed(
    okResult(
      [item({ title: "Dinner, drinks; fun", subtitle: "Bar 5, Main St" })],
      { include_content: true },
    ),
    now,
  );
  parseAndValidate(feed);
  assertStringIncludes(feed, "SUMMARY:Dinner\\, drinks\\; fun");
  assertStringIncludes(feed, "LOCATION:Bar 5\\, Main St");
  assertStringIncludes(feed, "DESCRIPTION:Climbing crew");
});

Deno.test("a title with a line break cannot add a property", () => {
  const feed = buildFeed(
    okResult([item({ title: "Hi\r\nATTENDEE:mailto:x@y.z" })], {
      include_content: true,
    }),
    now,
  );
  parseAndValidate(feed);
  assertFalse(/^ATTENDEE/m.test(feed));
});

Deno.test("Chinese labels follow the person's language", () => {
  const feed = buildFeed(
    okResult(
      [item({}), item({ kind: "task", target_id: "t", ends_at: null })],
      {
        language: "zh",
      },
    ),
    now,
  );
  assertStringIncludes(
    feed.replaceAll("\r\n ", ""),
    "SUMMARY:活动 · Climbing crew",
  );
  assertStringIncludes(
    feed.replaceAll("\r\n ", ""),
    "SUMMARY:任务 · Climbing crew",
  );
  assertStringIncludes(
    feed.replaceAll("\r\n ", ""),
    "X-WR-CALNAME:WeCord 日程",
  );
  parseAndValidate(feed);
});

Deno.test("an all-day task is a DATE in the person's zone; a timed task lasts half an hour", () => {
  // Due 23:59 on 21 October in Shanghai (UTC+8) = 15:59 UTC the same day.
  const allDay = item({
    kind: "task",
    target_id: "t-day",
    starts_at: "2026-10-21T15:59:00+00:00",
    ends_at: null,
    all_day: true,
  });
  const timed = item({
    kind: "task",
    target_id: "t-time",
    starts_at: "2026-10-21T15:59:00+00:00",
    ends_at: null,
  });
  const feed = buildFeed(
    okResult([allDay, timed], { utc_offset_minutes: 480 }),
    now,
  );
  parseAndValidate(feed);
  assertStringIncludes(feed, "DTSTART;VALUE=DATE:20261021");
  assertStringIncludes(feed, "DTEND;VALUE=DATE:20261022");
  assertStringIncludes(feed, "DTSTART:20261021T155900Z");
  assertStringIncludes(feed, "DTEND:20261021T162900Z");
  assertStringIncludes(feed, "TRANSP:TRANSPARENT");

  // In New York (UTC-4 in October) the same day's 23:59 is 03:59 UTC next day;
  // an offset that is an hour out (daylight saving) still lands on the date.
  const west = item({
    kind: "task",
    target_id: "t-west",
    starts_at: "2026-10-22T03:59:00+00:00",
    ends_at: null,
    all_day: true,
  });
  for (const offset of [-240, -300]) {
    assertStringIncludes(
      buildFeed(okResult([west], { utc_offset_minutes: offset }), now),
      "DTSTART;VALUE=DATE:20261021",
    );
  }
});

Deno.test("an event without an end lasts an hour; the month rolls over for DATE ends", () => {
  const feed = buildFeed(okResult([item({ ends_at: null })]), now);
  assertStringIncludes(feed, "DTEND:20261022T190000Z");
  const end = buildIcsFeed(
    [{
      uid: "x",
      summary: "Last day",
      start: { year: 2026, month: 12, day: 31 },
    }],
    { name: "t", now },
  );
  assertStringIncludes(end, "DTEND;VALUE=DATE:20270101");
});

Deno.test("a row with a broken time is skipped, not fatal", () => {
  const feed = buildFeed(
    okResult([item({ starts_at: "not a time" }), item({ target_id: "ok" })]),
    now,
  );
  assertEquals(parseAndValidate(feed).length, 1);
});

// The request handler -------------------------------------------------------

function deps(result: FeedResult | Error, seen: unknown[] = []) {
  return {
    now: () => now,
    badTokens: new WindowLimiter(3, 60_000),
    lookup: (hash: string, from: Date, to: Date) => {
      seen.push({ hash, from, to });
      return result instanceof Error
        ? Promise.reject(result)
        : Promise.resolve(result);
    },
  };
}

const url = `https://x.supabase.co/functions/v1/calendar-feed/${token}.ics`;

Deno.test("a good token gets the calendar, asked for the next 60 days by hash", async () => {
  const seen: { hash: string; from: Date; to: Date }[] = [];
  const response = await handleFeedRequest(
    new Request(url),
    deps(okResult([item({})]), seen),
  );
  assertEquals(response.status, 200);
  assertStringIncludes(
    response.headers.get("Content-Type") ?? "",
    "text/calendar",
  );
  assertStringIncludes(response.headers.get("Cache-Control") ?? "", "no-store");
  parseAndValidate(await response.text());
  assertEquals(seen.length, 1);
  assertEquals(seen[0].hash, await hashToken(token));
  assertFalse(seen[0].hash.includes(token));
  assertEquals(seen[0].to.getTime() - now.getTime(), 60 * 24 * 3_600_000);
  assert(seen[0].from.getTime() < now.getTime());
});

Deno.test("HEAD has headers and no body; other methods are refused", async () => {
  const head = await handleFeedRequest(
    new Request(url, { method: "HEAD" }),
    deps(okResult([])),
  );
  assertEquals(head.status, 200);
  assertEquals(await head.text(), "");
  const post = await handleFeedRequest(
    new Request(url, { method: "POST", body: "x" }),
    deps(okResult([])),
  );
  assertEquals(post.status, 405);
  assertEquals(post.headers.get("Allow"), "GET, HEAD");
});

Deno.test("an unknown token and a malformed path are 404 and say nothing more", async () => {
  const seen: unknown[] = [];
  const unknown = await handleFeedRequest(
    new Request(url),
    deps({ status: "invalid" }, seen),
  );
  assertEquals(unknown.status, 404);
  assertEquals(await unknown.text(), "Not found");
  const malformed = await handleFeedRequest(
    new Request("https://x.supabase.co/functions/v1/calendar-feed/abc.ics"),
    deps(okResult([]), seen),
  );
  assertEquals(malformed.status, 404);
  // The malformed path never reached the database.
  assertEquals(seen.length, 1);
});

Deno.test("a limited token is 429 with Retry-After", async () => {
  const response = await handleFeedRequest(
    new Request(url),
    deps({ status: "limited", retry_after: 1800 }),
  );
  assertEquals(response.status, 429);
  assertEquals(response.headers.get("Retry-After"), "1800");
});

Deno.test("a database failure is 503, not a leak", async () => {
  const response = await handleFeedRequest(
    new Request(url),
    deps(new Error("connection refused: secret details")),
  );
  assertEquals(response.status, 503);
  assertFalse((await response.text()).includes("secret"));
});

Deno.test("an address that sends wrong tokens is turned away before the database", async () => {
  const seen: unknown[] = [];
  const shared = deps({ status: "invalid" }, seen);
  const request = () =>
    new Request(url, {
      headers: { "x-forwarded-for": "203.0.113.9, 10.0.0.1" },
    });
  for (let index = 0; index < 3; index++) {
    assertEquals((await handleFeedRequest(request(), shared)).status, 404);
  }
  const blocked = await handleFeedRequest(request(), shared);
  assertEquals(blocked.status, 429);
  assert(Number(blocked.headers.get("Retry-After")) >= 1);
  assertEquals(seen.length, 3);
  // Another address is not affected.
  const other = await handleFeedRequest(
    new Request(url, { headers: { "x-forwarded-for": "198.51.100.1" } }),
    shared,
  );
  assertEquals(other.status, 404);
  assertEquals(seen.length, 4);
});

Deno.test("good requests don't count against the wrong-token limit", async () => {
  const shared = deps(okResult([]));
  for (let index = 0; index < 10; index++) {
    assertEquals(
      (await handleFeedRequest(new Request(url), shared)).status,
      200,
    );
  }
});

Deno.test("the limiter counts per key inside a window and sweeps old keys", () => {
  const limiter = new WindowLimiter(2, 1000, 2);
  assert(limiter.hit("a", 0));
  assert(limiter.hit("a", 10));
  assertFalse(limiter.hit("a", 20));
  assert(limiter.isBlocked("a", 30));
  assertEquals(limiter.retryAfterSeconds("a", 30), 1);
  assertFalse(limiter.isBlocked("b", 30));
  // After the window the key starts again.
  assertFalse(limiter.isBlocked("a", 1500));
  assert(limiter.hit("a", 1500));
  // The table does not grow past its cap.
  limiter.hit("b", 1600);
  limiter.hit("c", 1700);
  limiter.hit("d", 1800);
  assert(limiter.hit("e", 1900));
});
