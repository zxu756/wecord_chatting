// Talks to the OpenAI-compatible Chat Completions endpoint named by the
// secrets. Provider specifics are limited to the optional, documented
// pieces: an `x-opencode-session` header for opencode.ai and whatever the
// operator puts in AI_EXTRA_HEADERS.

import type { AiConfig } from "./config.ts";
import type { ChatMessage } from "./prompts.ts";

/// How WeCord introduces itself to providers. Always our own identity.
export const USER_AGENT = "WeCord/1.0 (+https://wecord.jokebear.fyi)";

export const REQUEST_TIMEOUT_MS = 45_000;

export type ProviderFailure = "busy" | "failed" | "empty" | "timeout";

/// The provider could not answer. `busy` is a rate or spend limit on the
/// provider's side (try again later); `failed` anything else; `empty` an
/// answer without text; `timeout` that it did not answer in time.
export class ProviderError extends Error {
  constructor(
    readonly kind: ProviderFailure,
    readonly status: number | null = null,
  ) {
    super(`ai provider ${kind}${status === null ? "" : ` (${status})`}`);
  }
}

export function chatCompletionsUrl(baseUrl: string): string {
  return `${baseUrl.replace(/\/+$/, "")}/chat/completions`;
}

/// Whether [baseUrl] is on opencode.ai.
export function isOpenCodeHost(baseUrl: string): boolean {
  try {
    const host = new URL(baseUrl).hostname.toLowerCase();
    return host === "opencode.ai" || host.endsWith(".opencode.ai");
  } catch {
    return false;
  }
}

/// The first 32 hex characters of the SHA-256 of "[conversationKey]:[feature]":
/// a stable id for one conversation's use of one feature that does not
/// reveal the conversation.
export async function sessionId(
  conversationKey: string,
  feature: string,
): Promise<string> {
  const bytes = new TextEncoder().encode(`${conversationKey}:${feature}`);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const hex = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return hex.slice(0, 32);
}

export interface CompletionOptions {
  messages: ChatMessage[];
  maxTokens: number;
  /// What the session header is derived from (the conversation id, or the
  /// user's id outside a conversation) and which feature is calling.
  conversationKey: string;
  feature: string;
  /// Sampling temperature; 0.2 when not given.
  temperature?: number;
  /// How long to wait for the provider; [REQUEST_TIMEOUT_MS] when not given.
  timeoutMs?: number;
}

/// The URL and init of the provider request.
export async function buildProviderRequest(
  config: AiConfig,
  options: CompletionOptions,
): Promise<{ url: string; init: RequestInit }> {
  const headers: Record<string, string> = {
    ...config.extraHeaders,
    "Authorization": `Bearer ${config.apiKey}`,
    "Content-Type": "application/json",
    "Accept": "application/json",
    "User-Agent": USER_AGENT,
  };
  if (isOpenCodeHost(config.baseUrl)) {
    headers["x-opencode-session"] = await sessionId(
      options.conversationKey,
      options.feature,
    );
  }
  return {
    url: chatCompletionsUrl(config.baseUrl),
    init: {
      method: "POST",
      headers,
      body: JSON.stringify({
        model: config.model,
        messages: options.messages,
        temperature: options.temperature ?? 0.2,
        max_tokens: options.maxTokens,
        stream: false,
      }),
    },
  };
}

/// Whether an HTTP [status] from the provider means it is out of capacity
/// or quota for now rather than broken.
export function isBusyStatus(status: number): boolean {
  return status === 429 || status === 402 || status === 503 || status === 529;
}

/// The text of a Chat Completions answer, without any `<think>` block, or
/// null when there is none.
export function extractCompletion(body: unknown): string | null {
  if (body === null || typeof body !== "object") {
    return null;
  }
  const choices = (body as { choices?: unknown }).choices;
  if (!Array.isArray(choices) || choices.length === 0) {
    return null;
  }
  const message = (choices[0] as { message?: { content?: unknown } })?.message;
  let content = message?.content;
  if (Array.isArray(content)) {
    content = content
      .map((part) =>
        typeof part === "object" && part !== null &&
          typeof (part as { text?: unknown }).text === "string"
          ? (part as { text: string }).text
          : ""
      )
      .join("");
  }
  if (typeof content !== "string") {
    return null;
  }
  const text = content
    .replace(/<think>[\s\S]*?<\/think>/gi, "")
    .replace(/^[\s\S]*<\/think>/i, "")
    .trim();
  return text === "" ? null : text;
}

type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

/// Asks the provider and returns the answer's text; throws [ProviderError].
export async function complete(
  config: AiConfig,
  options: CompletionOptions,
  fetchFn: Fetch = fetch,
): Promise<string> {
  const { url, init } = await buildProviderRequest(config, options);
  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(),
    options.timeoutMs ?? REQUEST_TIMEOUT_MS,
  );
  let response: Response;
  try {
    response = await fetchFn(url, { ...init, signal: controller.signal });
  } catch (error) {
    clearTimeout(timer);
    console.error("ai provider request failed", String(error));
    throw new ProviderError(controller.signal.aborted ? "timeout" : "failed");
  }
  try {
    if (!response.ok) {
      await response.body?.cancel();
      console.error("ai provider answered", response.status);
      throw new ProviderError(
        isBusyStatus(response.status) ? "busy" : "failed",
        response.status,
      );
    }
    let json: unknown;
    try {
      json = await response.json();
    } catch {
      throw new ProviderError("failed", response.status);
    }
    const text = extractCompletion(json);
    if (text === null) {
      throw new ProviderError("empty", response.status);
    }
    return text;
  } finally {
    clearTimeout(timer);
  }
}
