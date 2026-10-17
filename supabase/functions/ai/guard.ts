// The AI guard's pieces that need no network: the hosts of the links in a
// message and the reading of the model's answer.

export const GUARD_CATEGORIES = [
  "allow",
  "spam",
  "scam",
  "harassment",
  "sexual",
  "other",
] as const;
export type GuardCategory = (typeof GUARD_CATEGORIES)[number];

export interface GuardVerdict {
  category: GuardCategory;
  /// A short reason for the moderators; null when the model gave none.
  reason: string | null;
}

/// Longest reason kept.
export const MAX_REASON_CHARS = 160;
/// Most link hosts sent along.
export const MAX_DOMAINS = 10;
/// Most characters of the message the model gets.
export const MAX_GUARD_CHARS = 4_000;

const HOST = "(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,24}";
const SCHEME_URL = new RegExp(
  `\\b(?:https?|ftp)://(?:[^\\s/@]+@)?(${HOST}|\\d{1,3}(?:\\.\\d{1,3}){3})(?::\\d+)?`,
  "gi",
);
const BARE_HOST = new RegExp(
  `(?<![\\w@.-])(${HOST})(?![\\w-])(?=[/?#:]|\\b)`,
  "gi",
);

/// The distinct host names of the links in [text], lower case and without
/// "www.", at most [MAX_DOMAINS]. Finds links with a scheme and bare
/// addresses such as "free-prizes.example/claim"; the domain of an email
/// address is skipped.
export function extractLinkDomains(text: string): string[] {
  const hosts: string[] = [];
  const add = (raw: string) => {
    const host = raw.toLowerCase().replace(/^www\./, "").replace(/\.$/, "");
    if (host !== "" && !hosts.includes(host) && hosts.length < MAX_DOMAINS) {
      hosts.push(host);
    }
  };
  const withoutEmails = text.replace(/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g, " ");
  // Links with a scheme first, from the original text: a "user@host" in
  // one is the classic disguise, not an email address.
  for (const match of text.matchAll(SCHEME_URL)) {
    add(match[1]);
  }
  for (const match of withoutEmails.matchAll(BARE_HOST)) {
    add(match[1]);
  }
  return hosts;
}

/// [text] cut to what the model gets.
export function guardText(text: string): string {
  const trimmed = text.trim();
  return trimmed.length > MAX_GUARD_CHARS
    ? trimmed.slice(0, MAX_GUARD_CHARS)
    : trimmed;
}

const ALIASES: Record<string, GuardCategory> = {
  allow: "allow",
  allowed: "allow",
  ok: "allow",
  safe: "allow",
  fine: "allow",
  spam: "spam",
  scam: "scam",
  phishing: "scam",
  "scam/phishing": "scam",
  "scam-phishing": "scam",
  scam_phishing: "scam",
  fraud: "scam",
  harassment: "harassment",
  abuse: "harassment",
  hate: "harassment",
  sexual: "sexual",
  sex: "sexual",
  nsfw: "sexual",
  other: "other",
};

/// The model's answer as a verdict, or null when it is not one (no JSON
/// object, or a category that is not on the list). Accepts the object
/// alone, in a code fence or with text around it.
export function parseGuardVerdict(raw: string): GuardVerdict | null {
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
  if (typeof fields.category !== "string") {
    return null;
  }
  const category = ALIASES[fields.category.trim().toLowerCase()];
  if (category === undefined) {
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
  return { category, reason: category === "allow" ? null : reason };
}
