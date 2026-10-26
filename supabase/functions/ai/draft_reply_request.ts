// Reads the body of a `draft_reply` request (roadmap F6, see draft_reply.ts).
// Kept apart from request.ts so that file only gains a branch. No network.

/// Languages a reply can be written in (the same codes as LANGUAGES in
/// request.ts).
const DRAFT_LANGUAGES = ["en", "zh", "ja", "ko", "es", "fr"] as const;
export type DraftLanguage = (typeof DRAFT_LANGUAGES)[number];

/// The longest note about what the person wants to say, in characters. A
/// longer one is refused, not cut.
export const MAX_INTENT_CHARS = 300;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// "Help me reply" in the message box: replies to the end of a chat.
export interface DraftReplyRequest {
  action: "draft_reply";
  conversationId: string;
  /// One line about what the person wants to say, or null: then the replies
  /// follow from the chat alone.
  intent: string | null;
  /// The language to fall back on when the chat does not make it clear (the
  /// app's own), or null.
  language: DraftLanguage | null;
}

/// The request in [fields] (an object with action "draft_reply"), or null
/// when it is not one: no or a malformed chat id, a note that is not text or
/// is too long, a language that is not offered.
export function parseDraftReplyRequest(
  fields: Record<string, unknown>,
): DraftReplyRequest | null {
  if (
    typeof fields.conversation_id !== "string" ||
    !UUID.test(fields.conversation_id)
  ) {
    return null;
  }
  let intent: string | null = null;
  if (fields.intent !== undefined && fields.intent !== null) {
    if (typeof fields.intent !== "string") {
      return null;
    }
    const trimmed = fields.intent.trim();
    if (Array.from(trimmed).length > MAX_INTENT_CHARS) {
      return null;
    }
    intent = trimmed === "" ? null : trimmed;
  }
  let language: DraftLanguage | null = null;
  if (fields.language !== undefined && fields.language !== null) {
    if (
      typeof fields.language !== "string" ||
      !(DRAFT_LANGUAGES as readonly string[]).includes(fields.language)
    ) {
      return null;
    }
    language = fields.language as DraftLanguage;
  }
  return {
    action: "draft_reply",
    conversationId: fields.conversation_id.toLowerCase(),
    intent,
    language,
  };
}
