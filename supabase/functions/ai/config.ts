// Reads the AI provider settings from the function's secrets. Any
// OpenAI-compatible provider works: switching is a matter of changing
// AI_BASE_URL, AI_API_KEY and AI_MODEL (see docs/ai-setup.md).

export const DEFAULT_DAILY_LIMIT = 50;
export const DEFAULT_MAX_INPUT_CHARS = 24_000;
/// AI requests the guard may spend for one circle per UTC day.
export const DEFAULT_GUARD_LIMIT_PER_CIRCLE = 500;
const MIN_MAX_INPUT_CHARS = 2_000;
const MAX_MAX_INPUT_CHARS = 200_000;

/// Headers the operator may not set through AI_EXTRA_HEADERS: the request's
/// own framing and credentials, and the client identity, which is always
/// WeCord's own.
const RESERVED_HEADERS = new Set([
  "authorization",
  "content-type",
  "content-length",
  "host",
  "user-agent",
  "accept",
]);

export interface AiConfig {
  /// Without a trailing slash, e.g. https://api.deepseek.com/v1.
  baseUrl: string;
  apiKey: string;
  model: string;
  /// Requests one user may make per UTC day.
  dailyLimit: number;
  /// Characters of chat the model gets at most.
  maxInputChars: number;
  /// Extra request headers from the optional AI_EXTRA_HEADERS secret.
  extraHeaders: Record<string, string>;
  /// AI requests the guard of one circle may use per UTC day (charged to
  /// the circle, not to the member whose message is checked).
  guardDailyLimit: number;
}

type Getter = (name: string) => string | undefined;

function readInt(
  raw: string | undefined,
  fallback: number,
  min: number,
  max: number,
): number {
  const text = raw?.trim();
  if (!text || !/^\d+$/.test(text)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, Number.parseInt(text, 10)));
}

/// [raw] as a base URL without a trailing slash, or null when it is not an
/// https URL (plain http is only accepted for a local provider).
export function normalizeBaseUrl(raw: string | undefined): string | null {
  const text = raw?.trim();
  if (!text) {
    return null;
  }
  let url: URL;
  try {
    url = new URL(text);
  } catch {
    return null;
  }
  const local = url.hostname === "localhost" || url.hostname === "127.0.0.1" ||
    url.hostname === "[::1]";
  if (url.protocol !== "https:" && !(url.protocol === "http:" && local)) {
    return null;
  }
  if (url.username || url.password) {
    return null;
  }
  url.search = "";
  url.hash = "";
  return url.toString().replace(/\/+$/, "");
}

/// The optional AI_EXTRA_HEADERS secret: a JSON object of header names to
/// string values. Anything else, and reserved headers, are ignored.
export function parseExtraHeaders(
  raw: string | undefined,
): Record<string, string> {
  const text = raw?.trim();
  if (!text) {
    return {};
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return {};
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    return {};
  }
  const headers: Record<string, string> = {};
  for (const [name, value] of Object.entries(parsed)) {
    const key = name.trim().toLowerCase();
    if (
      typeof value !== "string" ||
      !/^[a-z0-9-]{1,64}$/.test(key) ||
      RESERVED_HEADERS.has(key) ||
      value.length > 512 ||
      /[\r\n]/.test(value)
    ) {
      continue;
    }
    headers[key] = value;
  }
  return headers;
}

/// The provider settings, or null when AI is not set up (a required secret
/// is missing or the base URL is not usable).
export function readAiConfig(get: Getter): AiConfig | null {
  const baseUrl = normalizeBaseUrl(get("AI_BASE_URL"));
  const apiKey = get("AI_API_KEY")?.trim();
  const model = get("AI_MODEL")?.trim();
  if (!baseUrl || !apiKey || !model) {
    return null;
  }
  return {
    baseUrl,
    apiKey,
    model,
    dailyLimit: readInt(
      get("AI_DAILY_LIMIT_PER_USER"),
      DEFAULT_DAILY_LIMIT,
      1,
      100_000,
    ),
    maxInputChars: readInt(
      get("AI_MAX_INPUT_CHARS"),
      DEFAULT_MAX_INPUT_CHARS,
      MIN_MAX_INPUT_CHARS,
      MAX_MAX_INPUT_CHARS,
    ),
    extraHeaders: parseExtraHeaders(get("AI_EXTRA_HEADERS")),
    guardDailyLimit: readInt(
      get("AI_GUARD_DAILY_LIMIT_PER_CIRCLE"),
      DEFAULT_GUARD_LIMIT_PER_CIRCLE,
      1,
      1_000_000,
    ),
  };
}
