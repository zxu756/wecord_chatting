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
  /// The same reason in Simplified Chinese, for moderators who use the app
  /// in Chinese; null when the model gave none.
  reasonZh: string | null;
}

/// Longest reason kept.
export const MAX_REASON_CHARS = 160;
/// Longest Chinese reason kept (Chinese is denser).
export const MAX_REASON_ZH_CHARS = 80;
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
  const { en, zh } = readReasons(fields);
  return {
    category,
    reason: category === "allow" ? null : en,
    reasonZh: category === "allow" ? null : zh,
  };
}

/// A free-text field as one trimmed line cut to [max] characters; null when
/// it is not text or empty.
function cleanReason(value: unknown, max: number): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const cleaned = value.replace(/\s+/g, " ").trim();
  if (cleaned === "") {
    return null;
  }
  return cleaned.length > max
    ? `${cleaned.slice(0, max - 1).trimEnd()}…`
    : cleaned;
}

/// The English and Chinese reasons of a verdict object. Tolerates the
/// models' variations: "reason" + "reason_zh" (the asked-for shape),
/// camelCase or "reason_cn" for the Chinese one, and "reason" as an object
/// with "en" / "zh" keys.
function readReasons(
  fields: Record<string, unknown>,
): { en: string | null; zh: string | null } {
  let en: string | null = null;
  let zh: string | null = null;
  const reason = fields.reason;
  if (reason !== null && typeof reason === "object" && !Array.isArray(reason)) {
    const nested = reason as Record<string, unknown>;
    en = cleanReason(nested.en ?? nested.english, MAX_REASON_CHARS);
    zh = cleanReason(
      nested.zh ?? nested["zh-CN"] ?? nested.zh_cn ?? nested.chinese,
      MAX_REASON_ZH_CHARS,
    );
  } else {
    en = cleanReason(reason, MAX_REASON_CHARS);
  }
  zh ??= cleanReason(
    fields.reason_zh ?? fields.reasonZh ?? fields.reason_cn ??
      fields.reason_zh_cn,
    MAX_REASON_ZH_CHARS,
  );
  return { en, zh };
}
