// Server-side HTML for the public circle pages (C8): /c/<slug> and
// /invite/<code>. Pure functions with no I/O, so every rule here is tested in
// render_test.ts. The data comes from the anon-callable database functions
// get_public_circle_card and get_public_invite_card (see
// supabase/migrations/202610260510_public_circle_card.sql), which are the only
// source: a page can show nothing they did not return.
//
// Everything that reaches the HTML is either a string from this file or a
// value that went through parseCard (type, length and shape checked) and then
// escapeHtml. The page has no script, and the Content-Security-Policy in
// securityHeaders says so: even a hole in the escaping could not run code.

export type Lang = "en" | "zh";
export type PageKind = "circle" | "invite";

/** The circle on a card, as far as the page trusts it. */
export interface Card {
  slug: string | null;
  name: string;
  description: string | null;
  iconUrl: string | null;
  category: string | null;
  language: string | null;
  tags: string[];
  /** 5, 10, 25 ... 10000, or null below 5 members. */
  memberLevel: number | null;
  joinMode: "open" | "apply" | "invite_only";
}

const CATEGORY_LABELS: Record<string, Record<Lang, string>> = {
  gaming: { en: "Gaming", zh: "游戏" },
  music: { en: "Music", zh: "音乐" },
  education: { en: "Education", zh: "教育" },
  science_tech: { en: "Science & Tech", zh: "科学与技术" },
  entertainment: { en: "Entertainment", zh: "娱乐" },
  art: { en: "Art", zh: "艺术" },
  sports: { en: "Sports", zh: "体育" },
  travel_outdoors: { en: "Travel & Outdoors", zh: "旅行与户外" },
  food: { en: "Food", zh: "美食" },
  local: { en: "Local", zh: "同城" },
  other: { en: "Other", zh: "其他" },
};

// Each language by its own name, like the app's picker.
const LANGUAGE_NAMES: Record<string, string> = {
  en: "English",
  zh: "中文",
  ja: "日本語",
  ko: "한국어",
  es: "Español",
  fr: "Français",
  de: "Deutsch",
  pt: "Português",
  ru: "Русский",
  it: "Italiano",
  vi: "Tiếng Việt",
  th: "ไทย",
  id: "Bahasa Indonesia",
};

const MEMBER_LEVELS = new Set([
  5,
  10,
  25,
  50,
  100,
  250,
  500,
  1000,
  2500,
  5000,
  10000,
]);

const TEXT: Record<Lang, Record<string, string>> = {
  en: {
    siteName: "WeCord",
    invited: "You're invited to join",
    publicCircle: "A public circle on WeCord",
    joinOpen: "Join in WeCord",
    joinApply: "Request to join in WeCord",
    open: "Open in WeCord",
    hintJoin:
      "You'll sign in or create a free account first, then join from there.",
    hintApply:
      "You'll sign in or create a free account first. This circle reviews who joins.",
    hintOpen: "You'll sign in or create a free account first.",
    members: "{n}+ members",
    ogDescription: "Join {name} on WeCord.",
    unavailableTitle: "This page isn't available",
    unavailableBody:
      "The link may have expired or been turned off, or the circle isn't public.",
    unavailableCta: "Go to WeCord",
    errorTitle: "Temporarily unavailable",
    errorBody: "We couldn't load this page just now. Try again in a moment.",
    iconAlt: "",
  },
  zh: {
    siteName: "WeCord",
    invited: "邀请你加入",
    publicCircle: "WeCord 上的公开圈子",
    joinOpen: "在 WeCord 中加入",
    joinApply: "在 WeCord 中申请加入",
    open: "在 WeCord 中打开",
    hintJoin: "先登录或免费注册一个账号，再从那里加入。",
    hintApply: "先登录或免费注册一个账号。这个圈子需要审核才能加入。",
    hintOpen: "先登录或免费注册一个账号。",
    members: "{n}+ 位成员",
    ogDescription: "在 WeCord 加入「{name}」。",
    unavailableTitle: "此页面不可用",
    unavailableBody: "链接可能已失效或被关闭，也可能是这个圈子并未公开。",
    unavailableCta: "前往 WeCord",
    errorTitle: "暂时无法访问",
    errorBody: "刚才没能加载这个页面，请稍后再试。",
    iconAlt: "",
  },
};

export function t(
  lang: Lang,
  key: string,
  values: Record<string, string | number> = {},
): string {
  let text = TEXT[lang][key] ?? TEXT.en[key] ?? key;
  for (const [name, value] of Object.entries(values)) {
    text = text.split(`{${name}}`).join(String(value));
  }
  return text;
}

/** Escapes text for HTML content and double- or single-quoted attributes. */
export function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;")
    .replaceAll("`", "&#96;");
}

/**
 * The page language: an explicit ?lang=zh|en wins, otherwise the first
 * language in Accept-Language (by q-value) that is Chinese or English;
 * English when there is none.
 */
export function pickLanguage(
  acceptLanguage: string | null | undefined,
  queryLang?: string | null,
): Lang {
  const forced = (queryLang ?? "").toLowerCase();
  if (forced === "zh" || forced === "en") return forced;
  const ranked: { tag: string; q: number; order: number }[] = [];
  const parts = (acceptLanguage ?? "").slice(0, 500).split(",");
  parts.forEach((part, order) => {
    const [rawTag, ...params] = part.trim().split(";");
    const tag = rawTag.trim().toLowerCase();
    if (!tag) return;
    let q = 1;
    for (const param of params) {
      const match = /^\s*q\s*=\s*([0-9.]+)\s*$/i.exec(param);
      if (match) q = Number(match[1]);
    }
    if (Number.isFinite(q) && q > 0) ranked.push({ tag, q, order });
  });
  ranked.sort((a, b) => b.q - a.q || a.order - b.order);
  for (const { tag } of ranked) {
    if (tag === "zh" || tag.startsWith("zh-")) return "zh";
    if (tag === "en" || tag.startsWith("en-")) return "en";
  }
  return "en";
}

const SLUG = /^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$/;
const INVITE_CODE = /^[a-z2-9]{10}$/;
// Mirrors the database: a plain https address with no quotes, spaces or
// markup characters.
const ICON_URL = /^https:\/\/[A-Za-z0-9._~:/?#@!$&()*+,;=%-]{1,255}$/;

export function isSlug(value: string): boolean {
  return SLUG.test(value);
}

export function isInviteCode(value: string): boolean {
  return INVITE_CODE.test(value);
}

function text(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value
    // deno-lint-ignore no-control-regex
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "")
    .trim();
  if (!cleaned) return null;
  return Array.from(cleaned).slice(0, max).join("");
}

/**
 * The card from the database function's answer, or null when the answer
 * says "unavailable" or is not a card at all. Nothing is trusted: every
 * field is type checked, bounded and (for the picture) shape checked.
 */
export function parseCard(raw: unknown): Card | null {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    return null;
  }
  const row = raw as Record<string, unknown>;
  if (row.available !== true) return null;
  const name = text(row.name, 100);
  if (!name) return null;
  const slug = typeof row.slug === "string" && isSlug(row.slug)
    ? row.slug
    : null;
  const icon = typeof row.icon_url === "string" && ICON_URL.test(row.icon_url)
    ? row.icon_url
    : null;
  const category = typeof row.category === "string" &&
      Object.hasOwn(CATEGORY_LABELS, row.category)
    ? row.category
    : null;
  const language = typeof row.language === "string" &&
      Object.hasOwn(LANGUAGE_NAMES, row.language)
    ? row.language
    : null;
  const tags = Array.isArray(row.tags)
    ? row.tags.map((tag) => text(tag, 24)).filter((tag): tag is string =>
      tag !== null
    ).slice(0, 5)
    : [];
  const level = typeof row.member_level === "number" &&
      MEMBER_LEVELS.has(row.member_level)
    ? row.member_level
    : null;
  const joinMode = row.join_mode === "apply" || row.join_mode === "invite_only"
    ? row.join_mode
    : "open";
  return {
    slug,
    name,
    description: text(row.description, 300),
    iconUrl: icon,
    category,
    language,
    tags,
    memberLevel: level,
    joinMode,
  };
}

// The only styles on the page. Their hash goes into the CSP, so any other
// inline style is refused by the browser.
export const PAGE_CSS = `
:root{--paper:#F5F4F1;--panel:#FFFFFF;--ink:#17171A;--muted:#5F5E66;--line:#E4E2DD;--raised:#F2F1EE;--accent:#2F6BF6;--on-accent:#FFFFFF;--accent-text:#1F5FE0;--shadow:0 1px 2px rgba(23,23,26,.06),0 12px 32px rgba(23,23,26,.08)}
@media (prefers-color-scheme:dark){:root{--paper:#111113;--panel:#1B1B1E;--ink:#F3F2EF;--muted:#A3A1AA;--line:#2C2C31;--raised:#26262A;--accent:#6E95FF;--on-accent:#111113;--accent-text:#9DB8FF;--shadow:0 1px 2px rgba(0,0,0,.4),0 12px 32px rgba(0,0,0,.4)}}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:20px;padding:24px 16px;background:var(--paper);color:var(--ink);font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Hiragino Sans GB","Microsoft YaHei",Roboto,"Helvetica Neue",Arial,sans-serif}
.card{width:100%;max-width:420px;background:var(--panel);border-radius:28px;box-shadow:var(--shadow);padding:32px 24px 24px;text-align:center}
.eyebrow{margin:0 0 16px;font-size:13px;font-weight:600;letter-spacing:.02em;color:var(--muted)}
.avatar{position:relative;width:88px;height:88px;margin:0 auto 16px;border-radius:30%;overflow:hidden;background:var(--accent);color:var(--on-accent);display:flex;align-items:center;justify-content:center;font-size:36px;font-weight:700}
.avatar img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
h1{margin:0 0 8px;font-size:28px;line-height:1.2;font-weight:800;letter-spacing:-.01em;overflow-wrap:anywhere}
.meta{margin:0 0 16px;font-size:14px;color:var(--muted)}
.about{margin:0 0 16px;font-size:16px;color:var(--ink);overflow-wrap:anywhere;white-space:pre-line}
.tags{list-style:none;margin:0 0 20px;padding:0;display:flex;flex-wrap:wrap;gap:8px;justify-content:center}
.tags li{background:var(--raised);color:var(--muted);border-radius:999px;padding:4px 12px;font-size:13px;overflow-wrap:anywhere}
.cta{display:flex;align-items:center;justify-content:center;min-height:52px;padding:0 24px;border-radius:999px;background:var(--ink);color:var(--paper);font-size:17px;font-weight:700;text-decoration:none}
.cta:focus-visible{outline:3px solid var(--accent);outline-offset:3px}
.cta:hover{opacity:.9}
.hint{margin:14px 0 0;font-size:13px;color:var(--muted)}
.brand{font-size:14px;font-weight:700;color:var(--muted);letter-spacing:.04em}
.brand a{color:inherit;text-decoration:none}
`.trim();

function initialOf(name: string): string {
  const first = Array.from(name.trim())[0] ?? "#";
  return first.toUpperCase();
}

export interface PageContext {
  lang: Lang;
  kind: PageKind;
  /** The page's own origin, e.g. https://wecord.jokebear.fyi. */
  origin: string;
  /** The slug or invite code the page was asked for (already validated). */
  param: string;
}

function appHref(ctx: PageContext): string {
  // The web app keeps its routes after a '#': /#/invite/<code>, /#/c/<slug>.
  const prefix = ctx.kind === "invite" ? "invite" : "c";
  return `/#/${prefix}/${encodeURIComponent(ctx.param)}`;
}

function canonicalUrl(ctx: PageContext): string {
  const prefix = ctx.kind === "invite" ? "invite" : "c";
  return `${ctx.origin}/${prefix}/${encodeURIComponent(ctx.param)}`;
}

function metaLine(card: Card, lang: Lang): string {
  const parts: string[] = [];
  if (card.category) parts.push(CATEGORY_LABELS[card.category][lang]);
  if (card.language) parts.push(LANGUAGE_NAMES[card.language]);
  if (card.memberLevel !== null) {
    parts.push(
      t(lang, "members", { n: card.memberLevel.toLocaleString("en-US") }),
    );
  }
  return parts.join(" · ");
}

function head(opts: {
  lang: Lang;
  title: string;
  description: string;
  url: string | null;
  image: string | null;
}): string {
  const lines = [
    `<meta charset="utf-8">`,
    `<title>${escapeHtml(opts.title)}</title>`,
    `<meta name="viewport" content="width=device-width, initial-scale=1">`,
    `<meta name="color-scheme" content="light dark">`,
    `<meta name="robots" content="noindex, nofollow">`,
    `<meta name="referrer" content="no-referrer">`,
    `<meta name="description" content="${escapeHtml(opts.description)}">`,
    `<link rel="icon" href="/favicon.png">`,
    `<meta property="og:site_name" content="${
      escapeHtml(t(opts.lang, "siteName"))
    }">`,
    `<meta property="og:type" content="website">`,
    `<meta property="og:title" content="${escapeHtml(opts.title)}">`,
    `<meta property="og:description" content="${
      escapeHtml(opts.description)
    }">`,
    `<meta property="og:locale" content="${
      opts.lang === "zh" ? "zh_CN" : "en_US"
    }">`,
    `<meta name="twitter:card" content="summary">`,
    `<meta name="twitter:title" content="${escapeHtml(opts.title)}">`,
    `<meta name="twitter:description" content="${
      escapeHtml(opts.description)
    }">`,
  ];
  if (opts.url) {
    lines.push(`<meta property="og:url" content="${escapeHtml(opts.url)}">`);
    lines.push(`<link rel="canonical" href="${escapeHtml(opts.url)}">`);
  }
  if (opts.image) {
    lines.push(
      `<meta property="og:image" content="${escapeHtml(opts.image)}">`,
    );
    lines.push(
      `<meta name="twitter:image" content="${escapeHtml(opts.image)}">`,
    );
  }
  lines.push(`<style>${PAGE_CSS}</style>`);
  return lines.join("\n");
}

function document(lang: Lang, headHtml: string, bodyHtml: string): string {
  return `<!doctype html>\n<html lang="${
    lang === "zh" ? "zh-CN" : "en"
  }">\n<head>\n${headHtml}\n</head>\n<body>\n${bodyHtml}\n</body>\n</html>\n`;
}

/** The page for an available circle. */
export function renderCardPage(card: Card, ctx: PageContext): string {
  const { lang } = ctx;
  const isInvite = ctx.kind === "invite";
  const title = `${card.name} · ${t(lang, "siteName")}`;
  const description = card.description
    ? Array.from(card.description.replace(/\s+/g, " ")).slice(0, 200).join("")
    : t(lang, "ogDescription", { name: card.name });
  const image = card.iconUrl ?? `${ctx.origin}/icons/Icon-512.png`;

  // A valid invite always lets you join (or ask to); a circle's own page does
  // only when the circle is open to everybody who signs in.
  const canJoin = isInvite || card.joinMode === "open";
  const cta = card.joinMode === "apply"
    ? t(lang, "joinApply")
    : canJoin
    ? t(lang, "joinOpen")
    : t(lang, "open");
  const hint = card.joinMode === "apply"
    ? t(lang, "hintApply")
    : canJoin
    ? t(lang, "hintJoin")
    : t(lang, "hintOpen");

  const meta = metaLine(card, lang);
  const avatar = `<div class="avatar" aria-hidden="true"><span>${
    escapeHtml(initialOf(card.name))
  }</span>${
    card.iconUrl
      ? `<img src="${
        escapeHtml(card.iconUrl)
      }" alt="" width="88" height="88" referrerpolicy="no-referrer" decoding="async">`
      : ""
  }</div>`;
  const tags = card.tags.length
    ? `<ul class="tags">${
      card.tags.map((tag) => `<li>#${escapeHtml(tag)}</li>`).join("")
    }</ul>`
    : "";
  const body = `<main class="card">
<p class="eyebrow">${
    escapeHtml(t(lang, isInvite ? "invited" : "publicCircle"))
  }</p>
${avatar}
<h1>${escapeHtml(card.name)}</h1>
${meta ? `<p class="meta">${escapeHtml(meta)}</p>` : ""}
${
    card.description
      ? `<p class="about">${escapeHtml(card.description)}</p>`
      : ""
  }
${tags}
<a class="cta" href="${escapeHtml(appHref(ctx))}">${escapeHtml(cta)}</a>
<p class="hint">${escapeHtml(hint)}</p>
</main>
<p class="brand"><a href="/">${escapeHtml(t(lang, "siteName"))}</a></p>`;
  return document(
    lang,
    head({
      lang,
      title,
      description,
      url: canonicalUrl(ctx),
      image,
    }),
    body,
  );
}

/**
 * The one page for everything that is not a shown circle: no such slug or
 * code, a private circle, a circle taken down, an invite that is revoked,
 * expired, used up or paused. It does not depend on why.
 */
export function renderUnavailablePage(lang: Lang, origin: string): string {
  const title = `${t(lang, "unavailableTitle")} · ${t(lang, "siteName")}`;
  const body = `<main class="card">
<h1>${escapeHtml(t(lang, "unavailableTitle"))}</h1>
<p class="about">${escapeHtml(t(lang, "unavailableBody"))}</p>
<a class="cta" href="/">${escapeHtml(t(lang, "unavailableCta"))}</a>
</main>
<p class="brand">${escapeHtml(t(lang, "siteName"))}</p>`;
  return document(
    lang,
    head({
      lang,
      title,
      description: t(lang, "unavailableBody"),
      url: null,
      image: `${origin}/icons/Icon-512.png`,
    }),
    body,
  );
}

/** The page for a lookup that failed (network, database): not a verdict. */
export function renderErrorPage(lang: Lang, origin: string): string {
  const title = `${t(lang, "errorTitle")} · ${t(lang, "siteName")}`;
  const body = `<main class="card">
<h1>${escapeHtml(t(lang, "errorTitle"))}</h1>
<p class="about">${escapeHtml(t(lang, "errorBody"))}</p>
<a class="cta" href="/">${escapeHtml(t(lang, "unavailableCta"))}</a>
</main>
<p class="brand">${escapeHtml(t(lang, "siteName"))}</p>`;
  return document(
    lang,
    head({
      lang,
      title,
      description: t(lang, "errorBody"),
      url: null,
      image: `${origin}/icons/Icon-512.png`,
    }),
    body,
  );
}

/** base64 of the SHA-256 of [value], for a CSP hash source. */
export async function sha256Base64(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  let binary = "";
  for (const byte of new Uint8Array(digest)) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

/**
 * Headers every page carries. The CSP allows no script at all, styles only
 * with the hash of PAGE_CSS, and pictures only from https addresses (the
 * circle's own picture); the page can't be framed, makes no requests and
 * sends no referrer.
 */
export async function securityHeaders(): Promise<Record<string, string>> {
  const hash = await sha256Base64(PAGE_CSS);
  return {
    "Content-Security-Policy": [
      "default-src 'none'",
      `style-src 'sha256-${hash}'`,
      "img-src https:",
      "base-uri 'none'",
      "form-action 'none'",
      "frame-ancestors 'none'",
    ].join("; "),
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "X-Robots-Tag": "noindex, nofollow",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Permissions-Policy":
      "interest-cohort=(), geolocation=(), camera=(), microphone=()",
  };
}
