import { assertEquals } from "jsr:@std/assert@1";
import {
  DEFAULT_DAILY_LIMIT,
  DEFAULT_GUARD_LIMIT_PER_CIRCLE,
  DEFAULT_MAX_INPUT_CHARS,
  normalizeBaseUrl,
  parseExtraHeaders,
  readAiConfig,
} from "./config.ts";

const base = {
  AI_BASE_URL: "https://api.deepseek.com/v1/",
  AI_API_KEY: " sk-test ",
  AI_MODEL: "deepseek-chat",
};
const get = (env: Record<string, string>) => (name: string) => env[name];

Deno.test("the three required secrets configure AI, with defaults", () => {
  assertEquals(readAiConfig(get(base)), {
    baseUrl: "https://api.deepseek.com/v1",
    apiKey: "sk-test",
    model: "deepseek-chat",
    dailyLimit: DEFAULT_DAILY_LIMIT,
    maxInputChars: DEFAULT_MAX_INPUT_CHARS,
    extraHeaders: {},
    guardDailyLimit: DEFAULT_GUARD_LIMIT_PER_CIRCLE,
  });
});

Deno.test("a missing or blank required secret means not configured", () => {
  for (const name of ["AI_BASE_URL", "AI_API_KEY", "AI_MODEL"]) {
    const without = { ...base } as Record<string, string>;
    delete without[name];
    assertEquals(readAiConfig(get(without)), null, `${name} missing`);
    assertEquals(
      readAiConfig(get({ ...base, [name]: "  " })),
      null,
      `${name} blank`,
    );
  }
  assertEquals(readAiConfig(() => undefined), null);
});

Deno.test("the base URL must be https, except for a local provider", () => {
  assertEquals(normalizeBaseUrl("http://example.com/v1"), null);
  assertEquals(normalizeBaseUrl("ftp://example.com"), null);
  assertEquals(normalizeBaseUrl("not a url"), null);
  assertEquals(normalizeBaseUrl("https://user:pw@example.com/v1"), null);
  assertEquals(
    normalizeBaseUrl("http://localhost:11434/v1"),
    "http://localhost:11434/v1",
  );
  assertEquals(
    normalizeBaseUrl("https://opencode.ai/inference/go/openai/v1/?x=1"),
    "https://opencode.ai/inference/go/openai/v1",
  );
  assertEquals(
    readAiConfig(get({ ...base, AI_BASE_URL: "http://x.com" })),
    null,
  );
});

Deno.test("the limit and input size are read, clamped and defaulted", () => {
  const config = readAiConfig(
    get({
      ...base,
      AI_DAILY_LIMIT_PER_USER: "12",
      AI_MAX_INPUT_CHARS: "50000",
    }),
  );
  assertEquals(config?.dailyLimit, 12);
  assertEquals(config?.maxInputChars, 50000);
  const odd = readAiConfig(
    get({
      ...base,
      AI_DAILY_LIMIT_PER_USER: "lots",
      AI_MAX_INPUT_CHARS: "5",
    }),
  );
  assertEquals(odd?.dailyLimit, DEFAULT_DAILY_LIMIT);
  assertEquals(odd?.maxInputChars, 2000);
  assertEquals(
    readAiConfig(get({ ...base, AI_DAILY_LIMIT_PER_USER: "0" }))?.dailyLimit,
    1,
  );
});

Deno.test("extra headers come from a JSON object and cannot spoof identity", () => {
  assertEquals(
    parseExtraHeaders(
      JSON.stringify({
        "X-Team": "wecord",
        "User-Agent": "other-client/9",
        "Authorization": "Bearer x",
        "Bad Name": "v",
        "x-number": 5,
        "x-newline": "a\nb",
      }),
    ),
    { "x-team": "wecord" },
  );
  assertEquals(parseExtraHeaders("not json"), {});
  assertEquals(parseExtraHeaders("[1]"), {});
  assertEquals(parseExtraHeaders(undefined), {});
});

Deno.test("the guard's daily limit per circle is its own secret", () => {
  assertEquals(
    readAiConfig(get({ ...base, AI_GUARD_DAILY_LIMIT_PER_CIRCLE: "40" }))
      ?.guardDailyLimit,
    40,
  );
  assertEquals(
    readAiConfig(get({ ...base, AI_GUARD_DAILY_LIMIT_PER_CIRCLE: "lots" }))
      ?.guardDailyLimit,
    DEFAULT_GUARD_LIMIT_PER_CIRCLE,
  );
  // The per-user limit does not touch it.
  assertEquals(
    readAiConfig(get({ ...base, AI_DAILY_LIMIT_PER_USER: "3" }))
      ?.guardDailyLimit,
    DEFAULT_GUARD_LIMIT_PER_CIRCLE,
  );
});
