// The AI function's request handling with everything it touches passed in,
// so limits, missing configuration and error mapping can be tested without
// a network or a database. index.ts wires the real thing.

import { type AiConfig, readAiConfig } from "./config.ts";
import { selectNewest, type SourceMessage } from "./chat.ts";
import { rewritePrompt, summaryPrompt, translatePrompt } from "./prompts.ts";
import { complete, ProviderError } from "./provider.ts";
import {
  type AiRequest,
  DEFAULT_RECENT_MESSAGES,
  MAX_SUMMARY_MESSAGES,
  parseAiRequest,
} from "./request.ts";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/// What the summary reads, loaded as the caller.
export interface ConversationMessages {
  /// Oldest first, at most the amount asked for (the newest ones).
  messages: SourceMessage[];
  /// All messages in the range, which may be more than [messages].
  total: number;
  /// The first message of the range.
  firstMessageId: string | null;
  /// The latest messages rather than the unread ones.
  recent: boolean;
}

export interface AiDeps {
  env: (name: string) => string | undefined;
  fetch: (input: string, init?: RequestInit) => Promise<Response>;
  /// The signed-in user's id for an Authorization header, or null.
  authenticate: (authorization: string) => Promise<string | null>;
  /// The messages a summary covers, read with the caller's own access, or
  /// null when the conversation is not visible to them.
  loadMessages: (options: {
    userId: string;
    conversationId: string;
    afterMessageId: string | null | undefined;
    recent: boolean;
    limit: number;
  }) => Promise<ConversationMessages | null>;
  /// False when the conversation's circle has turned AI features off.
  circleAllows: (
    userId: string,
    conversationId: string,
  ) => Promise<boolean>;
  /// Counts a request against today's limit; allowed is false once the
  /// limit is reached (and nothing is counted).
  consume: (
    userId: string,
    limit: number,
  ) => Promise<{ allowed: boolean; used: number }>;
  /// Gives back a request that did not get an answer.
  refund: (userId: string) => Promise<void>;
  /// Requests made today.
  usedToday: (userId: string) => Promise<number>;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function maxTokensFor(text: string): number {
  return Math.min(4_096, Math.max(256, Math.ceil(text.length * 1.5) + 128));
}

export async function handleAiRequest(
  request: Request,
  deps: AiDeps,
): Promise<Response> {
  try {
    return await route(request, deps);
  } catch (error) {
    console.error("ai request failed", String(error));
    return json({ error: "internal" }, 500);
  }
}

async function route(request: Request, deps: AiDeps): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (token === "" || token === authorization) {
    return json({ error: "unauthorized" }, 401);
  }
  const userId = await deps.authenticate(authorization);
  if (userId === null) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: unknown;
  try {
    body = JSON.parse(await request.text());
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const parsed = parseAiRequest(body);
  if (parsed === null) {
    return json({ error: "invalid_request" }, 400);
  }

  const config = readAiConfig(deps.env);
  if (config === null) {
    return json({ error: "ai_not_configured" }, 503);
  }
  if (parsed.action === "status") {
    return json({
      configured: true,
      daily_limit: config.dailyLimit,
      used: await deps.usedToday(userId),
    });
  }

  const conversationId = parsed.conversationId;
  if (
    conversationId !== null &&
    !(await deps.circleAllows(userId, conversationId))
  ) {
    return json({ error: "ai_disabled_in_circle" }, 403);
  }

  switch (parsed.action) {
    case "summarize":
      return await summarize(parsed, userId, config, deps);
    case "rewrite":
    case "translate":
      return await rewriteOrTranslate(parsed, userId, config, deps);
  }
}

/// Counts the request and runs [run]; maps the limit and provider errors to
/// responses. The request is given back when the provider fails.
async function metered(
  userId: string,
  config: AiConfig,
  deps: AiDeps,
  run: () => Promise<Response>,
): Promise<Response> {
  const { allowed, used } = await deps.consume(userId, config.dailyLimit);
  if (!allowed) {
    return json(
      { error: "ai_limit_reached", limit: config.dailyLimit, used },
      429,
    );
  }
  try {
    return await run();
  } catch (error) {
    await deps.refund(userId).catch(() => {});
    if (error instanceof ProviderError) {
      return error.kind === "busy"
        ? json({ error: "ai_busy" }, 503)
        : json({ error: "ai_failed" }, 502);
    }
    console.error("ai request failed", String(error));
    return json({ error: "ai_failed" }, 502);
  }
}

async function summarize(
  parsed: Extract<AiRequest, { action: "summarize" }>,
  userId: string,
  config: AiConfig,
  deps: AiDeps,
): Promise<Response> {
  const source = await deps.loadMessages({
    userId,
    conversationId: parsed.conversationId,
    afterMessageId: parsed.afterMessageId,
    recent: parsed.recent,
    limit: parsed.recent ? DEFAULT_RECENT_MESSAGES : MAX_SUMMARY_MESSAGES,
  });
  if (source === null) {
    return json({ error: "conversation_not_found" }, 404);
  }
  const selection = selectNewest(
    source.messages,
    config.maxInputChars,
    source.messages.length,
  );
  if (selection.lines.length === 0) {
    return json({
      summary: null,
      message_count: 0,
      summarized_count: 0,
      first_message_id: source.firstMessageId,
    });
  }
  return await metered(userId, config, deps, async () => {
    const summary = await complete(config, {
      messages: summaryPrompt({
        lines: selection.lines,
        omitted: Math.max(0, source.total - selection.lines.length),
        language: parsed.language,
        recent: source.recent,
      }),
      maxTokens: 900,
      conversationKey: parsed.conversationId,
      feature: "summary",
    }, deps.fetch);
    return json({
      summary,
      message_count: source.total,
      summarized_count: selection.lines.length,
      first_message_id: source.firstMessageId,
    });
  });
}

async function rewriteOrTranslate(
  parsed: Extract<AiRequest, { action: "rewrite" | "translate" }>,
  userId: string,
  config: AiConfig,
  deps: AiDeps,
): Promise<Response> {
  if (parsed.text.length > config.maxInputChars) {
    return json({ error: "text_too_long" }, 413);
  }
  const rewrite = parsed.action === "rewrite";
  const messages = rewrite
    ? rewritePrompt({
      mode: parsed.mode,
      text: parsed.text,
      target: parsed.target,
    })
    : translatePrompt({ text: parsed.text, target: parsed.target });
  return await metered(userId, config, deps, async () => {
    const text = await complete(config, {
      messages,
      maxTokens: maxTokensFor(parsed.text),
      conversationKey: parsed.conversationId ?? userId,
      feature: rewrite ? "rewrite" : "translate",
    }, deps.fetch);
    return json({ text });
  });
}
