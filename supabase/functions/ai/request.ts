// Reads the app's request body. No network.

export const LANGUAGES = {
  en: "English",
  zh: "Simplified Chinese",
  ja: "Japanese",
  ko: "Korean",
  es: "Spanish",
  fr: "French",
} as const;
export type LanguageCode = keyof typeof LANGUAGES;

export const REWRITE_MODES = [
  "fix",
  "shorter",
  "polite",
  "formal",
  "translate",
] as const;
export type RewriteMode = (typeof REWRITE_MODES)[number];

/// Longest text rewritten or translated in one request.
export const MAX_TEXT_CHARS = 8_000;
/// Messages summarized at most.
export const MAX_SUMMARY_MESSAGES = 400;
export const DEFAULT_RECENT_MESSAGES = 100;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type AiRequest =
  | { action: "status" }
  /// The AI guard's check of one message, asked by the database with the
  /// shared secret (never by a signed-in user).
  | { action: "guard"; messageId: string }
  | {
    action: "summarize";
    conversationId: string;
    /// The reader's last read message when the chat opened; null starts at
    /// the beginning, undefined uses what the server has stored.
    afterMessageId: string | null | undefined;
    /// Summarize the latest messages instead of the unread ones.
    recent: boolean;
    /// The language of the summary.
    language: LanguageCode;
  }
  | {
    action: "rewrite";
    mode: RewriteMode;
    text: string;
    target: LanguageCode | null;
    conversationId: string | null;
  }
  | {
    action: "translate";
    text: string;
    target: LanguageCode;
    conversationId: string | null;
  }
  | {
    /// Speech to text for one voice message. Only the message id is sent:
    /// the function finds the audio itself, as the caller.
    action: "transcribe";
    messageId: string;
  };

export function isLanguageCode(value: unknown): value is LanguageCode {
  return typeof value === "string" &&
    Object.prototype.hasOwnProperty.call(LANGUAGES, value);
}

function optionalId(value: unknown): string | null | "invalid" {
  if (value === undefined || value === null) {
    return null;
  }
  return typeof value === "string" && UUID.test(value) ? value : "invalid";
}

function readText(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const text = value.trim();
  if (text === "" || text.length > MAX_TEXT_CHARS) {
    return null;
  }
  return text;
}

/// The request in [body], or null when it is not one the function knows.
export function parseAiRequest(body: unknown): AiRequest | null {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return null;
  }
  const fields = body as Record<string, unknown>;
  switch (fields.action) {
    case "status":
      return { action: "status" };
    case "guard": {
      const messageId = optionalId(fields.message_id);
      if (messageId === null || messageId === "invalid") {
        return null;
      }
      return { action: "guard", messageId };
    }
    case "summarize": {
      const conversationId = optionalId(fields.conversation_id);
      if (conversationId === null || conversationId === "invalid") {
        return null;
      }
      let afterMessageId: string | null | undefined;
      if ("after_message_id" in fields) {
        const parsed = optionalId(fields.after_message_id);
        if (parsed === "invalid") {
          return null;
        }
        afterMessageId = parsed;
      }
      return {
        action: "summarize",
        conversationId,
        afterMessageId,
        recent: fields.recent === true,
        language: fields.language === "zh" ? "zh" : "en",
      };
    }
    case "rewrite": {
      const text = readText(fields.text);
      const conversationId = optionalId(fields.conversation_id);
      const mode = fields.mode;
      if (
        text === null || conversationId === "invalid" ||
        !(REWRITE_MODES as readonly unknown[]).includes(mode)
      ) {
        return null;
      }
      let target: LanguageCode | null = null;
      if (mode === "translate") {
        if (!isLanguageCode(fields.target)) {
          return null;
        }
        target = fields.target;
      }
      return {
        action: "rewrite",
        mode: mode as RewriteMode,
        text,
        target,
        conversationId,
      };
    }
    case "translate": {
      const text = readText(fields.text);
      const conversationId = optionalId(fields.conversation_id);
      if (
        text === null || conversationId === "invalid" ||
        !isLanguageCode(fields.target)
      ) {
        return null;
      }
      return {
        action: "translate",
        text,
        target: fields.target,
        conversationId,
      };
    }
    case "transcribe": {
      const messageId = optionalId(fields.message_id);
      if (messageId === null || messageId === "invalid") {
        return null;
      }
      return { action: "transcribe", messageId };
    }
    default:
      return null;
  }
}
