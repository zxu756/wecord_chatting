// Reads the body of a `meeting_recap` request (roadmap E1, see
// meeting_recap.ts). No network. Kept apart from request.ts so that file only
// gains a branch.

/// Languages the recap can be written in (the same codes as LANGUAGES in
/// request.ts).
const RECAP_LANGUAGES = ["en", "zh", "ja", "ko", "es", "fr"] as const;
export type RecapLanguage = (typeof RECAP_LANGUAGES)[number];

/// Most sentences one request may carry. A long meeting is a few hundred.
export const MAX_RECAP_ENTRIES = 2_000;
/// Longest sentence kept, in characters. A speech recognizer makes short
/// ones; anything longer is cut, not refused.
export const MAX_RECAP_ENTRY_CHARS = 600;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// One sentence somebody said, as their own device heard it.
export interface RecapEntry {
  /// The speaker's user id. The function maps it to a member's name itself:
  /// the app's idea of a name is never used.
  speakerId: string;
  text: string;
  /// Seconds since captions were turned on, or null when not known.
  atSeconds: number | null;
}

export interface MeetingRecapRequest {
  action: "meeting_recap";
  conversationId: string;
  entries: RecapEntry[];
  /// The language to write the recap in, or null for the meeting's own.
  language: RecapLanguage | null;
  timeZone: string | null;
  utcOffsetMinutes: number | null;
}

/// The request in [fields] (an object with action "meeting_recap"), or null
/// when it is not one: no conversation, no sentences, too many sentences, a
/// malformed sentence.
export function parseMeetingRecapRequest(
  fields: Record<string, unknown>,
): MeetingRecapRequest | null {
  const conversationId = fields.conversation_id;
  if (typeof conversationId !== "string" || !UUID.test(conversationId)) {
    return null;
  }
  const raw = fields.entries;
  if (
    !Array.isArray(raw) || raw.length === 0 || raw.length > MAX_RECAP_ENTRIES
  ) {
    return null;
  }
  const entries: RecapEntry[] = [];
  for (const value of raw) {
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      return null;
    }
    const entry = value as Record<string, unknown>;
    if (typeof entry.speaker !== "string" || !UUID.test(entry.speaker)) {
      return null;
    }
    if (typeof entry.text !== "string") {
      return null;
    }
    const text = Array.from(entry.text.replace(/\s+/g, " ").trim())
      .slice(0, MAX_RECAP_ENTRY_CHARS).join("");
    if (text === "") {
      continue;
    }
    const at = entry.at;
    entries.push({
      speakerId: entry.speaker.toLowerCase(),
      text,
      atSeconds: typeof at === "number" && Number.isFinite(at) && at >= 0 &&
          at <= 86_400 * 2
        ? Math.floor(at)
        : null,
    });
  }
  if (entries.length === 0) {
    return null;
  }
  let language: RecapLanguage | null = null;
  if (fields.language !== undefined && fields.language !== null) {
    if (
      typeof fields.language !== "string" ||
      !(RECAP_LANGUAGES as readonly string[]).includes(fields.language)
    ) {
      return null;
    }
    language = fields.language as RecapLanguage;
  }
  const zone = typeof fields.time_zone === "string"
    ? fields.time_zone.trim()
    : "";
  const offset = fields.utc_offset_minutes;
  return {
    action: "meeting_recap",
    conversationId,
    entries,
    language,
    timeZone: /^[A-Za-z0-9_+./-]{1,64}$/.test(zone) ? zone : null,
    utcOffsetMinutes: typeof offset === "number" && Number.isInteger(offset) &&
        offset >= -840 && offset <= 840
      ? offset
      : null,
  };
}
