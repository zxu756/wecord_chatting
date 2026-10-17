import { assertEquals } from "jsr:@std/assert@1";
import {
  formatTimeToken,
  replaceTimeTokens,
  validTimeZone,
  withTimesWritten,
  writeTimesForTargets,
} from "./time_tokens.ts";

// 1760000000 is Thursday 9 October 2025, 08:53:20 UTC.
const unix = 1760000000;
const now = unix;

const shanghai = { timeZone: "Asia/Shanghai", language: "en", nowSeconds: now };
const shanghaiZh = { ...shanghai, language: "zh" };
const losAngeles = {
  timeZone: "America/Los_Angeles",
  language: "en",
  nowSeconds: now,
};

Deno.test("every style in the subscriber's zone, in English", () => {
  const cases: Record<string, string> = {
    t: "4:53 PM",
    T: "4:53:20 PM",
    d: "Oct 9",
    D: "October 9, 2025",
    f: "Thu, Oct 9, 4:53 PM",
    F: "Thursday, October 9, 2025 at 4:53 PM",
  };
  for (const [style, expected] of Object.entries(cases)) {
    assertEquals(formatTimeToken(unix, style, shanghai), expected, style);
  }
});

Deno.test("the same instant differs by zone and can change the date", () => {
  assertEquals(formatTimeToken(unix, "f", losAngeles), "Thu, Oct 9, 1:53 AM");
  assertEquals(
    formatTimeToken(unix + 20 * 3600, "d", {
      ...losAngeles,
      nowSeconds: unix + 20 * 3600,
    }),
    "Oct 9",
  );
  // 2025-10-09T20:00:00Z is already the 10th in Shanghai.
  const evening = Date.UTC(2025, 9, 9, 20) / 1000;
  assertEquals(
    formatTimeToken(evening, "d", { ...shanghai, nowSeconds: evening }),
    "Oct 10",
  );
});

Deno.test("Chinese wording follows the subscription's language", () => {
  assertEquals(formatTimeToken(unix, "t", shanghaiZh), "下午4:53");
  assertEquals(formatTimeToken(unix, "d", shanghaiZh), "10月9日");
  assertEquals(formatTimeToken(unix, "D", shanghaiZh), "2025年10月9日");
  assertEquals(formatTimeToken(unix, "f", shanghaiZh), "10月9日 周四 下午4:53");
  assertEquals(
    formatTimeToken(unix, "F", shanghaiZh),
    "2025年10月9日 星期四 下午4:53",
  );
  assertEquals(formatTimeToken(unix, "t", losAngeles), "1:53 AM");
  assertEquals(
    formatTimeToken(unix, "t", { ...losAngeles, language: "zh" }),
    "凌晨1:53",
  );
});

Deno.test("another year is written out in short dates", () => {
  const later = { ...shanghai, nowSeconds: unix + 400 * 86400 };
  assertEquals(formatTimeToken(unix, "d", later), "Oct 9, 2025");
  assertEquals(
    formatTimeToken(unix, "f", later),
    "Thu, Oct 9, 2025, 4:53 PM",
  );
});

Deno.test("midnight and noon read as 12", () => {
  const midnight = Date.UTC(2025, 9, 9, 16) / 1000; // 00:00 on the 10th in Shanghai
  assertEquals(
    formatTimeToken(midnight, "t", { ...shanghai, nowSeconds: midnight }),
    "12:00 AM",
  );
  const noon = Date.UTC(2025, 9, 9, 4) / 1000;
  assertEquals(
    formatTimeToken(noon, "t", { ...shanghai, nowSeconds: noon }),
    "12:00 PM",
  );
});

Deno.test("relative tokens", () => {
  const rel = (offset: number, language = "en") =>
    formatTimeToken(unix + offset, "R", {
      timeZone: "Asia/Shanghai",
      language,
      nowSeconds: now,
    });
  assertEquals(rel(10), "in a moment");
  assertEquals(rel(-10), "just now");
  assertEquals(rel(15 * 60), "in 15 minutes");
  assertEquals(rel(-60), "1 minute ago");
  assertEquals(rel(2 * 3600), "in 2 hours");
  assertEquals(rel(-3 * 3600), "3 hours ago");
  assertEquals(rel(86400 * 1), "tomorrow");
  assertEquals(rel(-86400 * 1), "yesterday");
  assertEquals(rel(3 * 86400), "in 3 days");
  assertEquals(rel(-5 * 86400), "5 days ago");
  assertEquals(rel(60 * 86400), "in 2 months");
  assertEquals(rel(800 * 86400), "in 2 years");
  assertEquals(rel(15 * 60, "zh"), "15 分钟后");
  assertEquals(rel(86400, "zh"), "明天");
  assertEquals(rel(-5 * 86400, "zh"), "5 天前");
});

Deno.test("relative day names use the subscriber's calendar", () => {
  // Within a day it is hours; past that it counts Shanghai's calendar days.
  const nowAt = Date.UTC(2025, 9, 9, 15) / 1000; // 23:00 on the 9th
  const target = Date.UTC(2025, 9, 9, 18) / 1000; // 02:00 on the 10th
  assertEquals(
    formatTimeToken(target, "R", {
      timeZone: "Asia/Shanghai",
      language: "en",
      nowSeconds: nowAt,
    }),
    "in 3 hours",
  );
  const nextDay = nowAt + 25 * 3600; // 00:00 on the 11th
  assertEquals(
    formatTimeToken(nextDay, "R", {
      timeZone: "Asia/Shanghai",
      language: "en",
      nowSeconds: nowAt,
    }),
    "in 2 days",
  );
});

Deno.test("unknown or missing zones fall back to UTC with a suffix", () => {
  for (
    const timeZone of [null, undefined, "", "Mars/Olympus", "x".repeat(80)]
  ) {
    const options = { timeZone, language: "en", nowSeconds: now };
    assertEquals(formatTimeToken(unix, "t", options), "8:53 AM UTC");
    assertEquals(
      formatTimeToken(unix, "F", options),
      "Thursday, October 9, 2025 at 8:53 AM UTC",
    );
  }
  assertEquals(
    formatTimeToken(unix, "t", {
      timeZone: null,
      language: "zh",
      nowSeconds: now,
    }),
    "上午8:53 UTC",
  );
  // Relative times need no zone, so no suffix.
  assertEquals(
    formatTimeToken(unix + 7200, "R", {
      timeZone: null,
      language: "en",
      nowSeconds: now,
    }),
    "in 2 hours",
  );
});

Deno.test("validTimeZone", () => {
  assertEquals(validTimeZone("Asia/Kolkata"), "Asia/Kolkata");
  assertEquals(validTimeZone("Europe/London"), "Europe/London");
  assertEquals(validTimeZone("Nope/Zone"), null);
  assertEquals(validTimeZone(null), null);
});

Deno.test("half hour zones", () => {
  assertEquals(
    formatTimeToken(unix, "t", {
      timeZone: "Asia/Kolkata",
      language: "en",
      nowSeconds: now,
    }),
    "2:23 PM",
  );
});

Deno.test("replaceTimeTokens changes tokens and leaves the rest", () => {
  assertEquals(
    replaceTimeTokens(`Meet <t:${unix}:t> or <t:${unix}:d>!`, shanghai),
    "Meet 4:53 PM or Oct 9!",
  );
  // No style is the short date and time.
  assertEquals(
    replaceTimeTokens(`<t:${unix}>`, shanghai),
    "Thu, Oct 9, 4:53 PM",
  );
  assertEquals(
    replaceTimeTokens("no tokens <t> here", shanghai),
    "no tokens <t> here",
  );
  assertEquals(
    replaceTimeTokens("<t:999999999999999:t> <t:abc> <t:1:x>", shanghai),
    "<t:999999999999999:t> <t:abc> <t:1:x>",
  );
});

Deno.test("withTimesWritten uses each subscription's own zone and language", () => {
  const locales = new Map([
    ["a", { time_zone: "Asia/Shanghai", language: "zh" }],
    ["b", { time_zone: "America/Los_Angeles", language: "en" }],
  ]);
  const target = (id: string) => ({
    subscription_id: id,
    title: "Ada",
    body: `Call at <t:${unix}:t>`,
  });
  assertEquals(
    withTimesWritten(target("a"), locales, now).body,
    "Call at 下午4:53",
  );
  assertEquals(
    withTimesWritten(target("b"), locales, now).body,
    "Call at 1:53 AM",
  );
  assertEquals(
    withTimesWritten(target("unknown"), locales, now).body,
    "Call at 8:53 AM UTC",
  );
  const plain = { subscription_id: "a", title: "Ada", body: "hello" };
  assertEquals(withTimesWritten(plain, locales, now), plain);
});

Deno.test("writeTimesForTargets reads zones from push_subscriptions", async () => {
  const asked: string[][] = [];
  const admin = {
    from: (table: string) => {
      assertEquals(table, "push_subscriptions");
      return {
        select: (_columns: string) => ({
          in: (_column: string, values: string[]) => {
            asked.push(values);
            return Promise.resolve({
              data: [{ id: "a", time_zone: "Asia/Shanghai", language: "en" }],
              error: null,
            });
          },
        }),
      };
    },
  };
  const targets = [
    { subscription_id: "a", title: "T", body: `At <t:${unix}:t>` },
    { subscription_id: "a", title: "T", body: "plain" },
    { subscription_id: "b", title: "T", body: `At <t:${unix}:t>` },
  ];
  const result = await writeTimesForTargets(admin, targets, now);
  assertEquals(result.map((t) => t.body), [
    "At 4:53 PM",
    "plain",
    "At 8:53 AM UTC",
  ]);
  assertEquals(asked, [["a", "b"]]);
  // Nothing to write: the table is not read at all.
  const untouched = await writeTimesForTargets(admin, [targets[1]], now);
  assertEquals(untouched, [targets[1]]);
  assertEquals(asked.length, 1);
});

Deno.test("a failed lookup still sends, in UTC", async () => {
  const admin = {
    from: () => ({
      select: () => ({
        in: () => Promise.resolve({ data: null, error: { message: "down" } }),
      }),
    }),
  };
  const result = await writeTimesForTargets(
    admin,
    [{ subscription_id: "a", title: "T", body: `At <t:${unix}:t>` }],
    now,
  );
  assertEquals(result[0].body, "At 8:53 AM UTC");
});
