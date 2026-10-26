// Reads the app's request body. No network.

import {
  type MeetingRecapRequest,
  parseMeetingRecapRequest,
} from "./meeting_recap_request.ts";
import { type AskRequest, parseAskRequest } from "./ask_request.ts";
import {
  type GuardItemRequest,
  type LinkCheckRequest,
  parseGuardItemRequest,
  parseLinkCheckRequest,
} from "./guard2_request.ts";
import {
  type DraftReplyRequest,
  parseDraftReplyRequest,
} from "./draft_reply_request.ts";

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

/// What the notes editor's AI can do (see note_assist.ts).
export const NOTE_ASSIST_MODES = [
  "continue",
  "summarize",
  "outline",
  "tone",
  "translate",
  "extract_tasks",
] as const;
export type NoteAssistMode = (typeof NOTE_ASSIST_MODES)[number];

/// The tones the notes editor's AI can change a text to.
export const NOTE_TONES = [
  "polite",
  "formal",
  "casual",
  "concise",
  "fix",
] as const;
export type NoteTone = (typeof NOTE_TONES)[number];

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
  }
  | {
    /// Translations of the messages a person is looking at (auto-translate,
    /// and the message menu's Translate), see translate_batch.ts.
    action: "translate_batch";
    conversationId: string;
    /// Distinct, at most MAX_BATCH_IDS in a sound request (the handler
    /// answers 400 too_many_messages above that).
    messageIds: string[];
    target: LanguageCode;
    /// A person asked for this message in particular: no skipping for
    /// language or content, the answer is shown even if it equals the text.
    manual: boolean;
  }
  /// The @WeCord AI assistant's answer to a queued job, asked by the database
  /// with the shared secret (never by a signed-in user); see assistant.ts.
  | { action: "assistant"; jobId: string }
  /// The daily digest of a queued run, asked by the database with the shared
  /// secret (never by a signed-in user); see digest.ts.
  | { action: "digest"; digestId: string }
  | {
    /// To-dos and events in the messages a person chose (extract_actions.ts).
    action: "extract_actions";
    conversationId: string;
    /// Distinct, 1 to MAX_EXTRACT_MESSAGES.
    messageIds: string[];
    /// The person's IANA time zone for dates, when the app knows it.
    timeZone: string | null;
    /// The person's offset from UTC in minutes right now: used for dates
    /// when there is no usable zone name (the iPhone and Mac apps do not
    /// know it). Null reads dates as UTC.
    utcOffsetMinutes: number | null;
  }
  | {
    /// The AI in the notes editor (note_assist.ts): continue, summarize,
    /// outline, change the tone, translate, pull out the to-dos.
    action: "note_assist";
    noteId: string;
    mode: NoteAssistMode;
    /// The selected text, or null for the whole note.
    text: string | null;
    /// For mode "tone".
    tone: NoteTone | null;
    /// For mode "translate".
    target: LanguageCode | null;
    /// The language to write in, or null for the note's own.
    language: LanguageCode | null;
  }
  /// The minutes of a call whose captions were on (meeting_recap.ts).
  | MeetingRecapRequest
  /// A question about the chats a person can read (ask.ts).
  | AskRequest
  /// The AI guard's check of an event, note or task (guard2.ts), asked by the
  /// database with the shared secret.
  | GuardItemRequest
  /// "Ask AI about this link" (link_check.ts).
  | LinkCheckRequest
  /// "Help me reply" in the message box: two or three replies to the end of
  /// a chat (draft_reply.ts).
  | DraftReplyRequest;

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
    case "translate_batch": {
      const conversationId = optionalId(fields.conversation_id);
      if (
        conversationId === null || conversationId === "invalid" ||
        !isLanguageCode(fields.target) || !Array.isArray(fields.message_ids) ||
        fields.message_ids.length === 0 || fields.message_ids.length > 200
      ) {
        return null;
      }
      const messageIds: string[] = [];
      for (const value of fields.message_ids) {
        if (typeof value !== "string" || !UUID.test(value)) {
          return null;
        }
        if (!messageIds.includes(value)) {
          messageIds.push(value);
        }
      }
      return {
        action: "translate_batch",
        conversationId,
        messageIds,
        target: fields.target,
        manual: fields.manual === true,
      };
    }
    case "assistant": {
      const jobId = optionalId(fields.job_id);
      if (jobId === null || jobId === "invalid") {
        return null;
      }
      return { action: "assistant", jobId };
    }
    case "digest": {
      const digestId = optionalId(fields.digest_id);
      if (digestId === null || digestId === "invalid") {
        return null;
      }
      return { action: "digest", digestId };
    }
    case "extract_actions": {
      const conversationId = optionalId(fields.conversation_id);
      if (
        conversationId === null || conversationId === "invalid" ||
        !Array.isArray(fields.message_ids) ||
        fields.message_ids.length === 0 || fields.message_ids.length > 200
      ) {
        return null;
      }
      const messageIds: string[] = [];
      for (const value of fields.message_ids) {
        if (typeof value !== "string" || !UUID.test(value)) {
          return null;
        }
        if (!messageIds.includes(value)) {
          messageIds.push(value);
        }
      }
      // More than 50 distinct messages is a request that is too big, not one
      // to cut down quietly.
      if (messageIds.length > 50) {
        return null;
      }
      const zone = typeof fields.time_zone === "string"
        ? fields.time_zone.trim()
        : "";
      const offset = fields.utc_offset_minutes;
      return {
        action: "extract_actions",
        conversationId,
        messageIds,
        timeZone: /^[A-Za-z0-9_+./-]{1,64}$/.test(zone) ? zone : null,
        utcOffsetMinutes:
          typeof offset === "number" && Number.isInteger(offset) &&
            offset >= -840 && offset <= 840
            ? offset
            : null,
      };
    }
    case "note_assist": {
      const noteId = optionalId(fields.note_id);
      const mode = fields.mode;
      if (
        noteId === null || noteId === "invalid" ||
        !(NOTE_ASSIST_MODES as readonly unknown[]).includes(mode)
      ) {
        return null;
      }
      // A selection is optional; an empty one counts as none, a too long
      // one is a request that is too big.
      let text: string | null = null;
      if (typeof fields.text === "string") {
        if (fields.text.trim() !== "") {
          text = readText(fields.text);
          if (text === null) {
            return null;
          }
        }
      } else if (fields.text !== undefined && fields.text !== null) {
        return null;
      }
      let tone: NoteTone | null = null;
      if (mode === "tone") {
        if (!(NOTE_TONES as readonly unknown[]).includes(fields.tone)) {
          return null;
        }
        tone = fields.tone as NoteTone;
      }
      let target: LanguageCode | null = null;
      if (mode === "translate") {
        if (!isLanguageCode(fields.target)) {
          return null;
        }
        target = fields.target;
      }
      let language: LanguageCode | null = null;
      if (fields.language !== undefined && fields.language !== null) {
        if (!isLanguageCode(fields.language)) {
          return null;
        }
        language = fields.language;
      }
      return {
        action: "note_assist",
        noteId,
        mode: mode as NoteAssistMode,
        text,
        tone,
        target,
        language,
      };
    }
    case "meeting_recap":
      return parseMeetingRecapRequest(fields);
    case "ask":
      return parseAskRequest(fields);
    case "guard_item":
      return parseGuardItemRequest(fields);
    case "link_check":
      return parseLinkCheckRequest(fields);
    case "draft_reply":
      return parseDraftReplyRequest(fields);
    default:
      return null;
  }
}
