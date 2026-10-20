// Reads the bodies of the two requests AI guard 2.0 adds (roadmap F7 and G5):
// `guard_item` (the database asks, with the shared secret) and `link_check`
// (a signed-in person asks about a link). Kept apart from request.ts so that
// file only gains a branch. No network.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// The longest address accepted for a link check, in characters.
export const MAX_LINK_CHARS = 2048;

/// The check of one event, note, task list or task, asked by the database
/// (never by a signed-in user); see guard2.ts.
export interface GuardItemRequest {
  action: "guard_item";
  reviewId: string;
}

/// "Ask AI about this link" (link_check.ts).
export interface LinkCheckRequest {
  action: "link_check";
  url: string;
  /// "zh" or "en": the language of the reason.
  language: "zh" | "en";
  /// The chat the link was in, when the app knows it: the circle's or the
  /// group's AI switch is read from it.
  conversationId: string | null;
}

export function parseGuardItemRequest(
  fields: Record<string, unknown>,
): GuardItemRequest | null {
  if (typeof fields.review_id !== "string" || !UUID.test(fields.review_id)) {
    return null;
  }
  return { action: "guard_item", reviewId: fields.review_id.toLowerCase() };
}

export function parseLinkCheckRequest(
  fields: Record<string, unknown>,
): LinkCheckRequest | null {
  if (typeof fields.url !== "string") {
    return null;
  }
  const raw = fields.url.trim();
  if (raw === "" || raw.length > MAX_LINK_CHARS) {
    return null;
  }
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return null;
  }
  let conversationId: string | null = null;
  if (fields.conversation_id !== undefined && fields.conversation_id !== null) {
    if (
      typeof fields.conversation_id !== "string" ||
      !UUID.test(fields.conversation_id)
    ) {
      return null;
    }
    conversationId = fields.conversation_id.toLowerCase();
  }
  return {
    action: "link_check",
    url: url.href,
    language: fields.language === "zh" ? "zh" : "en",
    conversationId,
  };
}
