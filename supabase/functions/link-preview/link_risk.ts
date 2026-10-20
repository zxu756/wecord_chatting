// How risky a link looks, from the address alone: no network, no model, and
// nothing about the message it came in. The rules are kept in step with the
// app's copy (lib/features/safety/link_risk.dart); both run against the same
// cases in test/fixtures/link_risk_cases.json.
//
// A score is added up from signals and read as:
//   >= 5 high      (the app shows a warning page before opening)
//   >= 2 caution   (the preview card says to be careful)
//   else none
// A link whose host is one of the sites listed in KNOWN_SITES is never
// scored for its words; only a disguised address (user@host, an IP) counts.

export type RiskLevel = "none" | "caution" | "high";

export type RiskReason =
  | "credentials_in_url"
  | "ip_address"
  | "punycode"
  | "short_link"
  | "lookalike_brand"
  | "brand_in_subdomain"
  | "risky_tld"
  | "login_words"
  | "many_subdomains"
  | "many_hyphens"
  | "download_file"
  | "plain_http_login"
  | "redirects_risky";

export interface LinkRisk {
  level: RiskLevel;
  score: number;
  reasons: RiskReason[];
}

export const HIGH_SCORE = 5;
export const CAUTION_SCORE = 2;

/// Sites whose names scammers imitate, with the hosts that are really theirs
/// (a host equal to one of them, or under it, is the real thing).
export const BRANDS: Record<string, string[]> = {
  paypal: ["paypal.com", "paypal.me"],
  apple: ["apple.com", "icloud.com"],
  icloud: ["icloud.com", "apple.com"],
  microsoft: [
    "microsoft.com",
    "live.com",
    "office.com",
    "outlook.com",
    "microsoftonline.com",
  ],
  google: ["google.com", "gmail.com", "goo.gl", "google.cn"],
  amazon: [
    "amazon.com",
    "amazon.co.uk",
    "amazon.de",
    "amazon.fr",
    "amazon.co.jp",
    "amazon.in",
    "amazon.ca",
    "amazon.com.au",
    "amazon.cn",
  ],
  alipay: ["alipay.com", "antgroup.com"],
  wechat: ["wechat.com", "weixin.qq.com", "qq.com"],
  weixin: ["weixin.qq.com", "wechat.com", "qq.com"],
  taobao: ["taobao.com", "tmall.com", "alibaba.com", "aliexpress.com"],
  binance: ["binance.com", "binance.us", "binance.org"],
  coinbase: ["coinbase.com"],
  metamask: ["metamask.io"],
  discord: ["discord.com", "discord.gg", "discordapp.com", "discord.media"],
  steam: ["steampowered.com", "steamcommunity.com", "steamstatic.com"],
  telegram: ["telegram.org", "t.me", "telegram.me"],
  whatsapp: ["whatsapp.com", "whatsapp.net", "wa.me"],
  netflix: ["netflix.com"],
  instagram: ["instagram.com"],
  facebook: ["facebook.com", "fb.com", "fb.me", "facebook.net"],
  tiktok: ["tiktok.com"],
  github: ["github.com", "github.io", "githubusercontent.com"],
  wecord: ["jokebear.fyi"],
};

/// Hosts that are never scored for their words: the real sites of BRANDS
/// are covered by [BRANDS]; these are other well-known ones.
export const KNOWN_SITES = [
  "wikipedia.org",
  "youtube.com",
  "youtu.be",
  "twitter.com",
  "x.com",
  "reddit.com",
  "linkedin.com",
  "baidu.com",
  "bilibili.com",
  "zhihu.com",
  "weibo.com",
  "apple.com",
  "mozilla.org",
  "cloudflare.com",
];

/// Words around a brand name that do not make the name a different one
/// ("paypal-secure", "login-paypal").
const BRAND_FILLER = [
  "secure",
  "security",
  "login",
  "signin",
  "verify",
  "verification",
  "account",
  "support",
  "help",
  "service",
  "services",
  "official",
  "wallet",
  "pay",
  "id",
  "app",
  "web",
  "online",
  "update",
  "customer",
  "center",
  "centre",
  "mail",
  "store",
  "shop",
  "com",
  "net",
  "org",
];

/// Services that hide where a link goes.
export const SHORTENERS = [
  "bit.ly",
  "t.co",
  "tinyurl.com",
  "is.gd",
  "cutt.ly",
  "rb.gy",
  "t.cn",
  "url.cn",
  "dwz.cn",
  "ow.ly",
  "buff.ly",
  "shorturl.at",
  "tiny.cc",
  "s.id",
  "v.gd",
  "lnkd.in",
  "goo.gl",
  "reurl.cc",
  "suo.im",
];

const RISKY_TLDS = [
  "zip",
  "mov",
  "top",
  "xyz",
  "click",
  "gq",
  "tk",
  "ml",
  "cf",
  "ga",
  "icu",
  "buzz",
  "rest",
  "cyou",
  "sbs",
  "cfd",
  "monster",
  "work",
  "loan",
  "country",
];

const LOGIN_WORDS = [
  "login",
  "signin",
  "verify",
  "verification",
  "secure",
  "account",
  "wallet",
  "claim",
  "airdrop",
  "prize",
  "reward",
  "bonus",
  "giftcard",
  "recover",
  "unlock",
  "suspended",
  "billing",
  "password",
  "refund",
];

const DOWNLOAD_EXTENSIONS = [
  ".apk",
  ".exe",
  ".msi",
  ".scr",
  ".bat",
  ".cmd",
  ".dmg",
  ".pkg",
  ".jar",
  ".ps1",
];

/// Second-level labels that sit under a two-letter country code
/// (example.co.uk, example.com.cn).
const SECOND_LEVELS = ["co", "com", "net", "org", "gov", "edu", "ac"];

const NONE: LinkRisk = { level: "none", score: 0, reasons: [] };

function hostMatches(host: string, domains: string[]): boolean {
  return domains.some((domain) =>
    host === domain || host.endsWith(`.${domain}`)
  );
}

/// The part of [host] a person registered: "evil.example.co.uk" gives
/// "example.co.uk". Without a public-suffix list this is a close guess.
export function registrableDomain(host: string): string {
  const labels = host.split(".");
  if (labels.length <= 2) {
    return host;
  }
  const tld = labels[labels.length - 1];
  const second = labels[labels.length - 2];
  if (tld.length === 2 && SECOND_LEVELS.includes(second)) {
    return labels.slice(-3).join(".");
  }
  return labels.slice(-2).join(".");
}

function isIpHost(host: string): boolean {
  return /^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.startsWith("[");
}

/// A label with its hyphens taken out, digits that stand for letters turned
/// into them ("paypa1" is "paypal"), and the brand and filler words removed:
/// what is left is empty when the label is only a brand name with filler.
function reducesToBrand(label: string, brand: string): boolean {
  const variants = new Set<string>();
  const plain = label.replace(/-/g, "");
  variants.add(plain.replace(/[0-9]/g, ""));
  variants.add(
    plain
      .replace(/0/g, "o")
      .replace(/1/g, "l")
      .replace(/3/g, "e")
      .replace(/5/g, "s")
      .replace(/rn/g, "m")
      .replace(/vv/g, "w"),
  );
  for (const variant of variants) {
    if (!variant.includes(brand)) {
      continue;
    }
    let rest = variant.split(brand).join("");
    // Longest filler first so "services" is not left as "s".
    for (
      const word of [...BRAND_FILLER].sort((a, b) => b.length - a.length)
    ) {
      rest = rest.split(word).join("");
    }
    if (rest === "") {
      return true;
    }
  }
  return false;
}

/// Scores [rawUrl]. Anything that is not an http(s) address with a host
/// scores nothing: the app does not open it as a web page anyway.
export function assessLink(rawUrl: string): LinkRisk {
  let url: URL;
  try {
    url = new URL(rawUrl.trim());
  } catch {
    return NONE;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return NONE;
  }
  const host = url.hostname.toLowerCase().replace(/\.$/, "");
  if (host === "") {
    return NONE;
  }

  const reasons: RiskReason[] = [];
  let score = 0;
  const add = (reason: RiskReason, points: number) => {
    reasons.push(reason);
    score += points;
  };

  // "https://paypal.com@evil.example": the part before the @ is not the
  // host. A dot in it makes it look like one.
  const userInfo = url.password === ""
    ? url.username
    : `${url.username}:${url.password}`;
  if (userInfo !== "") {
    add("credentials_in_url", userInfo.includes(".") ? 5 : 2);
  }

  if (isIpHost(host)) {
    add("ip_address", 3);
  }

  const labels = host.split(".");
  const hasNonAscii = [...host].some((char) => char.charCodeAt(0) > 127);
  if (labels.some((label) => label.startsWith("xn--")) || hasNonAscii) {
    add("punycode", 3);
  }

  const known = hostMatches(host, KNOWN_SITES) ||
    Object.values(BRANDS).some((domains) => hostMatches(host, domains));

  const path = `${url.pathname}${url.search}`.toLowerCase();
  const wordsIn = (text: string) =>
    LOGIN_WORDS.some((word) => text.includes(word));
  let loginWords = false;

  if (!known) {
    const registrable = registrableDomain(host);
    const registrableLabels = registrable.split(".");
    for (const [brand, domains] of Object.entries(BRANDS)) {
      if (isIpHost(host)) {
        break;
      }
      if (hostMatches(host, domains)) {
        continue;
      }
      const brandLabelIndex = labels.findIndex((label) =>
        reducesToBrand(label, brand)
      );
      if (brandLabelIndex === -1) {
        continue;
      }
      // In the part the owner chose (example.com's "example") it is an
      // imitation; in a subdomain it is a disguise.
      const inRegistrable = brandLabelIndex >=
        labels.length - registrableLabels.length;
      add(
        inRegistrable ? "lookalike_brand" : "brand_in_subdomain",
        inRegistrable ? 3 : 5,
      );
      break;
    }

    if (wordsIn(host)) {
      add("login_words", 2);
      loginWords = true;
    } else if (wordsIn(path)) {
      add("login_words", 1);
      loginWords = true;
    }

    if (labels.length > 5) {
      add("many_subdomains", 1);
    }
    if ((host.replaceAll("xn--", "").match(/-/g) ?? []).length >= 3) {
      add("many_hyphens", 1);
    }
    if (RISKY_TLDS.includes(labels[labels.length - 1])) {
      add("risky_tld", 1);
    }
  }

  if (SHORTENERS.includes(host)) {
    add("short_link", 2);
  }

  const pathOnly = url.pathname.toLowerCase();
  if (DOWNLOAD_EXTENSIONS.some((extension) => pathOnly.endsWith(extension))) {
    add("download_file", 3);
  }

  if (url.protocol === "http:" && loginWords) {
    add("plain_http_login", 1);
  }

  return {
    level: score >= HIGH_SCORE
      ? "high"
      : score >= CAUTION_SCORE
      ? "caution"
      : "none",
    score,
    reasons,
  };
}

const LEVEL_ORDER: Record<RiskLevel, number> = { none: 0, caution: 1, high: 2 };

/// The risk of a link that was found to redirect: the worse of the address
/// given and the address it ended at, with "redirects_risky" added when the
/// end is the worse one.
export function assessRedirect(
  startUrl: string,
  finalUrl: string | null | undefined,
): LinkRisk {
  const start = assessLink(startUrl);
  if (!finalUrl) {
    return start;
  }
  const end = assessLink(finalUrl);
  if (LEVEL_ORDER[end.level] > LEVEL_ORDER[start.level]) {
    return {
      level: end.level,
      score: end.score,
      reasons: [...new Set<RiskReason>([...start.reasons, "redirects_risky"])],
    };
  }
  return start;
}
