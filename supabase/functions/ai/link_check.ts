// The `link_check` action (roadmap G5): "Ask AI about this link", offered on
// the warning page before a risky link opens. Only a person's own tap starts
// it.
//
// What the model gets is public information about the link and nothing from
// the chat: the address without its query string or fragment (those can hold
// private tokens), the address it redirects to if the link-preview function
// followed one, the page's title and description as link-preview read them,
// and the signals the app's own rules found (link_risk.ts). The link is never
// opened here. Those texts are written by whoever owns the page, so they are
// fenced as untrusted data (DATA_RULES).
//
// It counts against the person's daily limit like every AI request (and is
// given back when the model fails), honours the circle's and the person's AI
// switches, and stores nothing.

import type { AiConfig } from "./config.ts";
import { cleanText } from "./chat.ts";
import type { AiDeps } from "./handler.ts";
import { type ChatMessage, DATA_RULES } from "./prompts.ts";
import { complete, ProviderError } from "./provider.ts";
import type { LinkCheckRequest } from "./guard2_request.ts";
import { assessRedirect } from "../link-preview/link_risk.ts";

export const LINK_VERDICTS = [
  "safe",
  "suspicious",
  "dangerous",
  "unknown",
] as const;
export type LinkVerdict = (typeof LINK_VERDICTS)[number];

export interface LinkCheckAnswer {
  verdict: LinkVerdict;
  reason: string | null;
}

/// What link-preview learned about a link, read from its cache.
export interface LinkPageInfo {
  title: string | null;
  description: string | null;
  siteName: string | null;
  /// The address the link redirected to, when it did.
  finalUrl: string | null;
}

export interface LinkCheckStore {
  /// The cached preview of [url]; null when there is none.
  preview(url: string): Promise<LinkPageInfo | null>;
  /// Whether the person has AI on for themselves (user_ai_settings); true
  /// when they never chose.
  aiEnabled(userId: string): Promise<boolean>;
}

export type LinkCheckResult = { status: number; body: unknown };

const MAX_REASON_CHARS = 200;

/// [url] without its query, fragment and credentials, and cut short.
export function publicAddress(url: string): string {
  try {
    const parsed = new URL(url);
    const path = parsed.pathname.length > 200
      ? `${parsed.pathname.slice(0, 200)}…`
      : parsed.pathname;
    return `${parsed.protocol}//${parsed.host}${path}`;
  } catch {
    return "";
  }
}

function line(value: string | null, max: number): string {
  if (value === null) {
    return "(none)";
  }
  // Page text can say anything, including a closing tag for the fence.
  const cleaned = cleanText(value).replace(/\s+/g, " ").replace(/</g, "< ")
    .trim();
  return cleaned === ""
    ? "(none)"
    : cleaned.length > max
    ? `${cleaned.slice(0, max)}…`
    : cleaned;
}

export function linkCheckPrompt(options: {
  address: string;
  finalAddress: string | null;
  page: LinkPageInfo | null;
  signals: string[];
  language: "zh" | "en";
}): ChatMessage[] {
  const language = options.language === "zh" ? "Simplified Chinese" : "English";
  const system =
    "You help someone in a chat app decide whether a link is safe to open. " +
    DATA_RULES +
    "You have not opened the link and cannot: you only know its address and, when there is one, the title and description the page gave about itself. " +
    "Judge only from that. Never claim to know what is on the page, and never invent facts about the site or its owner.\n" +
    'Verdicts: "safe" = a well-known site, or an ordinary address with nothing odd about it; "suspicious" = something is off (imitates a known brand, an odd or disguised address, pressure to log in, pay or download); "dangerous" = clearly phishing, a scam or malware; "unknown" = you cannot tell. ' +
    'When unsure, choose "unknown" rather than "safe" or "dangerous". ' +
    `Reply with one JSON object and nothing else: {"verdict": "<one of the four>", "reason": "<one short sentence in ${language}, at most 120 characters>"}.`;
  const page = options.page;
  const user = `<link>\naddress: ${cleanText(options.address)}\n` +
    `redirects_to: ${options.finalAddress ?? "(none)"}\n` +
    `site_name: ${line(page?.siteName ?? null, 100)}\n` +
    `page_title: ${line(page?.title ?? null, 200)}\n` +
    `page_description: ${line(page?.description ?? null, 400)}\n` +
    `automatic_signals: ${
      options.signals.length === 0 ? "(none)" : options.signals.join(", ")
    }\n</link>`;
  return [
    { role: "system", content: system },
    { role: "user", content: user },
  ];
}

/// The model's answer, or null when it is not a verdict.
export function parseLinkCheckAnswer(raw: string): LinkCheckAnswer | null {
  const text = raw.trim();
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end <= start) {
    return null;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text.slice(start, end + 1));
  } catch {
    return null;
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    return null;
  }
  const fields = parsed as Record<string, unknown>;
  const verdict = typeof fields.verdict === "string"
    ? fields.verdict.trim().toLowerCase()
    : "";
  if (!(LINK_VERDICTS as readonly string[]).includes(verdict)) {
    return null;
  }
  let reason: string | null = null;
  if (typeof fields.reason === "string") {
    const cleaned = fields.reason.replace(/\s+/g, " ").trim();
    if (cleaned !== "") {
      reason = cleaned.length > MAX_REASON_CHARS
        ? `${cleaned.slice(0, MAX_REASON_CHARS - 1).trimEnd()}…`
        : cleaned;
    }
  }
  return { verdict: verdict as LinkVerdict, reason };
}

export async function runLinkCheck(
  parsed: LinkCheckRequest,
  userId: string,
  config: AiConfig,
  deps: AiDeps,
): Promise<LinkCheckResult> {
  const store = deps.linkCheck;
  if (store === undefined) {
    return { status: 503, body: { error: "ai_not_configured" } };
  }
  // The circle's (or group's) switch and the person's own come before
  // anything is read or sent.
  if (
    parsed.conversationId !== null &&
    !(await deps.circleAllows(userId, parsed.conversationId))
  ) {
    return { status: 403, body: { error: "ai_disabled_in_circle" } };
  }
  if (!(await store.aiEnabled(userId))) {
    return { status: 403, body: { error: "ai_disabled_for_user" } };
  }

  const address = publicAddress(parsed.url);
  if (address === "") {
    return { status: 400, body: { error: "invalid_request" } };
  }
  const page = await store.preview(parsed.url).catch(() => null);
  const finalAddress = page?.finalUrl ? publicAddress(page.finalUrl) : null;
  const risk = assessRedirect(parsed.url, page?.finalUrl ?? null);

  const { allowed, used } = await deps.consume(userId, config.dailyLimit);
  if (!allowed) {
    return {
      status: 429,
      body: { error: "ai_limit_reached", limit: config.dailyLimit, used },
    };
  }
  try {
    const answer = await complete(config, {
      messages: linkCheckPrompt({
        address,
        finalAddress: finalAddress === "" ? null : finalAddress,
        page,
        signals: risk.reasons,
        language: parsed.language,
      }),
      maxTokens: 240,
      temperature: 0,
      conversationKey: userId,
      feature: "link_check",
    }, deps.fetch);
    const result = parseLinkCheckAnswer(answer);
    if (result === null) {
      throw new ProviderError("empty");
    }
    return {
      status: 200,
      body: {
        verdict: result.verdict,
        reason: result.reason,
        host: new URL(parsed.url).hostname,
      },
    };
  } catch (error) {
    await deps.refund(userId).catch(() => {});
    if (error instanceof ProviderError) {
      return error.kind === "busy"
        ? { status: 503, body: { error: "ai_busy" } }
        : { status: 502, body: { error: "ai_failed" } };
    }
    console.error("link_check failed", String(error));
    return { status: 502, body: { error: "ai_failed" } };
  }
}
