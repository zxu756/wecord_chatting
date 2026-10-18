// The AI function's request handling with everything it touches passed in,
// so limits, missing configuration and error mapping can be tested without
// a network or a database. index.ts wires the real thing.

import { type AiConfig, readAiConfig } from "./config.ts";
import { selectNewest, type SourceMessage } from "./chat.ts";
import {
  extractLinkDomains,
  guardText,
  type GuardVerdict,
  parseGuardVerdict,
} from "./guard.ts";
import {
  guardPrompt,
  rewritePrompt,
  summaryPrompt,
  translatePrompt,
} from "./prompts.ts";
import { complete, ProviderError } from "./provider.ts";
import { type AssistantStore, runAssistantJob } from "./assistant.ts";
import { type ActionStore, runExtractActions } from "./extract_actions.ts";
import { runTranslateBatch, type TranslationStore } from "./translate_batch.ts";
import {
  audioFileName,
  MAX_AUDIO_BYTES,
  readTranscribeConfig,
  transcribeAudio,
} from "./transcribe.ts";
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

/// The voice message a transcription is for, read as the caller.
export interface VoiceMessage {
  conversationId: string;
  bucket: string;
  path: string;
  mimeType: string;
  /// The size the sender recorded, in bytes.
  size: number;
}

/// How long the guard waits for the provider: a message is held back from
/// the others meanwhile, so a slow model counts as unavailable.
export const GUARD_TIMEOUT_MS = 15_000;

/// A message waiting for the guard, as the database hands it out.
export interface GuardClaim {
  circleId: string;
  body: string;
  /// Whether the circle still allows AI features.
  aiEnabled: boolean;
}

/// Why a message was released without a check.
export type UncheckedReason =
  | "not_configured"
  | "ai_off"
  | "limit"
  | "error"
  | "timeout";

/// What the guard hands in for a message.
export type GuardResult =
  | { verdict: GuardVerdict; unchecked?: undefined }
  | { verdict?: undefined; unchecked: UncheckedReason };

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
  /// The voice message [messageId], or null when it does not exist, is not
  /// a voice message, was recalled, or the caller cannot see it.
  loadVoiceMessage: (
    userId: string,
    messageId: string,
  ) => Promise<VoiceMessage | null>;
  /// The message's audio, downloaded with the caller's own access, or null
  /// when it cannot be read.
  downloadAudio: (
    bucket: string,
    path: string,
  ) => Promise<Uint8Array | null>;

  /// The guard (service calls only, see [handleGuardRequest]).
  /// Claims a message that waits for its check; null when it does not (any
  /// more) or another call has it.
  guardClaim: (messageId: string) => Promise<GuardClaim | null>;
  /// Counts a request against the circle's day; allowed is false at the
  /// limit.
  guardConsume: (
    circleId: string,
    limit: number,
  ) => Promise<{ allowed: boolean; used: number }>;
  guardRefund: (circleId: string) => Promise<void>;
  /// Hands in the result. Resolves to the review's new state ('released',
  /// 'held' or 'flagged') or null.
  guardFinish: (
    messageId: string,
    result: GuardResult,
  ) => Promise<string | null>;

  /// The translation cache and the person's translation choices, for
  /// translate_batch (see translate_batch.ts). Without it that action
  /// answers 503.
  translations?: TranslationStore;

  /// The @WeCord AI assistant's jobs (see assistant.ts); service calls only.
  /// Without it the `assistant` action answers 503.
  assistant?: AssistantStore;
  /// What extract_actions reads (see extract_actions.ts). Without it that
  /// action answers 503.
  actions?: ActionStore;
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
  // The database asks for the AI guard with the shared secret as the bearer
  // token (the same DISPATCH_SECRET as scheduled-dispatch). It is the only
  // thing that secret may do here; nobody signed in can use it.
  if (isDispatchAuthorized(authorization, deps.env("DISPATCH_SECRET") ?? "")) {
    // The same secret also wakes the @WeCord AI assistant (assistant.ts).
    const peeked = await request.clone().json().catch(() => null) as
      | { action?: unknown; job_id?: unknown }
      | null;
    if (peeked?.action === "assistant") {
      const parsedJob = parseAiRequest(peeked);
      if (parsedJob === null || parsedJob.action !== "assistant") {
        return json({ error: "invalid_request" }, 400);
      }
      const result = await runAssistantJob(parsedJob.jobId, deps);
      return json(result.body, result.status);
    }
    return await handleGuardRequest(request, deps);
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

  if (parsed.action === "guard" || parsed.action === "assistant") {
    // Only the database (with the shared secret) may ask for a check or an
    // assistant answer.
    return json({ error: "forbidden" }, 403);
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
      transcribe_configured: readTranscribeConfig(deps.env) !== null,
    });
  }
  if (parsed.action === "transcribe") {
    return await transcribe(parsed, userId, config, deps);
  }
  if (parsed.action === "translate_batch") {
    const result = await runTranslateBatch(parsed, userId, config, deps);
    return json(result.body, result.status);
  }
  if (parsed.action === "extract_actions") {
    const result = await runExtractActions(parsed, userId, config, deps);
    return json(result.body, result.status);
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
  /// A response for an error that is the request's own fault, or null to
  /// use the usual mapping.
  mapError: (error: unknown) => Response | null = () => null,
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
    const mapped = mapError(error);
    if (mapped !== null) {
      return mapped;
    }
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

class AudioTooLongError extends Error {}

/// Speech to text for a voice message. The audio is found from the message
/// id as the caller (so only audio they can open is read), sent to the
/// transcription provider for this request, and not kept.
async function transcribe(
  parsed: Extract<AiRequest, { action: "transcribe" }>,
  userId: string,
  config: AiConfig,
  deps: AiDeps,
): Promise<Response> {
  const transcribeConfig = readTranscribeConfig(deps.env);
  if (transcribeConfig === null) {
    return json({ error: "transcribe_not_configured" }, 503);
  }
  const voice = await deps.loadVoiceMessage(userId, parsed.messageId);
  if (voice === null) {
    return json({ error: "message_not_found" }, 404);
  }
  // The circle's own AI switch is read from the message's conversation, not
  // from anything the app says.
  if (!(await deps.circleAllows(userId, voice.conversationId))) {
    return json({ error: "ai_disabled_in_circle" }, 403);
  }
  if (voice.size > MAX_AUDIO_BYTES) {
    return json({ error: "audio_too_long" }, 413);
  }
  return await metered(
    userId,
    config,
    deps,
    async () => {
      const bytes = await deps.downloadAudio(voice.bucket, voice.path);
      if (bytes === null) {
        throw new ProviderError("failed");
      }
      if (bytes.length > MAX_AUDIO_BYTES) {
        throw new AudioTooLongError();
      }
      const text = await transcribeAudio(transcribeConfig, {
        bytes,
        mimeType: voice.mimeType,
        fileName: audioFileName(voice.mimeType, voice.path),
      }, deps.fetch);
      return json({ text });
    },
    (error) =>
      error instanceof AudioTooLongError
        ? json({ error: "audio_too_long" }, 413)
        : null,
  );
}

/// Whether [header] is `Bearer <secret>`, compared in constant time. An
/// empty secret (not configured) never matches.
export function isDispatchAuthorized(
  header: string | null,
  secret: string,
): boolean {
  if (secret === "" || header === null) {
    return false;
  }
  const expected = new TextEncoder().encode(`Bearer ${secret}`);
  const given = new TextEncoder().encode(header);
  let difference = expected.length ^ given.length;
  for (let index = 0; index < expected.length; index++) {
    difference |= expected[index] ^ (given[index] ?? 0);
  }
  return difference === 0;
}

/// The AI guard: classifies the text of one new member's message that the
/// database holds back (messages.review_state 'checking') and hands the
/// answer to finish_message_review, which releases or holds it.
///
/// Fails open: when AI is not set up, the circle turned it off, the
/// circle's daily limit is reached or the provider fails, answers badly or
/// is too slow, the message is released as "not checked". Only the claim or
/// the hand-in itself failing leaves the message waiting (answer 500); the
/// database's sweep releases it within two minutes.
///
/// Only the message's text and the hosts of its links go to the model. The
/// request is charged to the circle (ai_circle_usage), never to the member.
export async function handleGuardRequest(
  request: Request,
  deps: AiDeps,
): Promise<Response> {
  let body: unknown;
  try {
    body = JSON.parse(await request.text());
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const parsed = parseAiRequest(body);
  if (parsed === null || parsed.action !== "guard") {
    return json({ error: "invalid_request" }, 400);
  }
  const messageId = parsed.messageId;

  const claim = await deps.guardClaim(messageId);
  if (claim === null) {
    return json({ ok: true, skipped: true });
  }

  const release = async (unchecked: UncheckedReason) => {
    const state = await deps.guardFinish(messageId, { unchecked });
    return json({ ok: true, state, unchecked });
  };

  try {
    if (!claim.aiEnabled) {
      return await release("ai_off");
    }
    const config = readAiConfig(deps.env);
    if (config === null) {
      return await release("not_configured");
    }
    const { allowed } = await deps.guardConsume(
      claim.circleId,
      config.guardDailyLimit,
    );
    if (!allowed) {
      return await release("limit");
    }

    let verdict: GuardVerdict | null;
    try {
      const text = guardText(claim.body);
      const answer = await complete(config, {
        messages: guardPrompt({ text, domains: extractLinkDomains(text) }),
        maxTokens: 320,
        temperature: 0,
        timeoutMs: GUARD_TIMEOUT_MS,
        conversationKey: claim.circleId,
        feature: "guard",
      }, deps.fetch);
      verdict = parseGuardVerdict(answer);
    } catch (error) {
      await deps.guardRefund(claim.circleId).catch(() => {});
      if (error instanceof ProviderError) {
        return await release(
          error.kind === "timeout"
            ? "timeout"
            : error.kind === "busy"
            ? "limit"
            : "error",
        );
      }
      throw error;
    }
    if (verdict === null) {
      // An answer that is not a verdict is no use, and not the circle's cost.
      await deps.guardRefund(claim.circleId).catch(() => {});
      return await release("error");
    }

    const state = await deps.guardFinish(messageId, { verdict });
    return json({ ok: true, state, category: verdict.category });
  } catch (error) {
    console.error("ai guard failed", String(error));
    try {
      return await release("error");
    } catch (inner) {
      console.error("ai guard could not release", String(inner));
      return json({ error: "internal" }, 500);
    }
  }
}
