// Reads the body of an `ask` request (roadmap F1, see ask.ts). No network.
// Kept apart from request.ts so that file only gains a branch.

/// Languages the answer can be written in (the same codes as LANGUAGES in
/// request.ts).
const ASK_LANGUAGES = ["en", "zh", "ja", "ko", "es", "fr"] as const;
export type AskLanguage = (typeof ASK_LANGUAGES)[number];

/// The longest question, in characters. A longer one is refused, not cut.
export const MAX_QUESTION_CHARS = 500;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// Where the answer may come from. Asking everywhere is a choice the person
/// makes; the app starts in the chat or circle they came from.
export type AskScope =
  | { type: "everywhere" }
  | { type: "circle"; id: string }
  | { type: "conversation"; id: string };

export interface AskRequest {
  action: "ask";
  question: string;
  scope: AskScope;
  language: AskLanguage;
  timeZone: string | null;
  utcOffsetMinutes: number | null;
}

/// The scope in [value], or null when it is none: a missing scope is not read
/// as "everywhere", because that is a choice the person has to make.
export function parseAskScope(value: unknown): AskScope | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  const fields = value as Record<string, unknown>;
  if (fields.type === "everywhere") {
    return { type: "everywhere" };
  }
  if (
    (fields.type === "circle" || fields.type === "conversation") &&
    typeof fields.id === "string" && UUID.test(fields.id)
  ) {
    return { type: fields.type, id: fields.id.toLowerCase() };
  }
  return null;
}

/// The request in [fields] (an object with action "ask"), or null when it is
/// not one: no question, a question that is too long, no or a malformed
/// scope, a language that is not offered.
export function parseAskRequest(
  fields: Record<string, unknown>,
): AskRequest | null {
  if (typeof fields.question !== "string") {
    return null;
  }
  const question = fields.question.replace(/\s+/g, " ").trim();
  if (question === "" || Array.from(question).length > MAX_QUESTION_CHARS) {
    return null;
  }
  const scope = parseAskScope(fields.scope);
  if (scope === null) {
    return null;
  }
  let language: AskLanguage = "en";
  if (fields.language !== undefined && fields.language !== null) {
    if (
      typeof fields.language !== "string" ||
      !(ASK_LANGUAGES as readonly string[]).includes(fields.language)
    ) {
      return null;
    }
    language = fields.language as AskLanguage;
  }
  const zone = typeof fields.time_zone === "string"
    ? fields.time_zone.trim()
    : "";
  const offset = fields.utc_offset_minutes;
  return {
    action: "ask",
    question,
    scope,
    language,
    timeZone: /^[A-Za-z0-9_+./-]{1,64}$/.test(zone) ? zone : null,
    utcOffsetMinutes: typeof offset === "number" && Number.isInteger(offset) &&
        offset >= -840 && offset <= 840
      ? offset
      : null,
  };
}
