// Pure Open Graph / <title> extraction for the link-preview function.

export interface PreviewMeta {
  title: string | null;
  description: string | null;
  image_url: string | null;
  site_name: string | null;
}

const MAX_TITLE = 300;
const MAX_DESCRIPTION = 500;
const MAX_SITE_NAME = 100;
const MAX_IMAGE_URL = 2048;

const metaTagPattern = /<meta\b[^>]*>/gi;
const attributePattern =
  /([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/g;
const titlePattern = /<title\b[^>]*>([\s\S]*?)<\/title\s*>/i;

/** Reads preview metadata from [html]; relative images resolve on [pageUrl]. */
export function extractPreviewMeta(html: string, pageUrl: string): PreviewMeta {
  const meta = new Map<string, string>();
  for (const match of html.matchAll(metaTagPattern)) {
    const attributes = parseAttributes(match[0]);
    const key = (attributes.get("property") ?? attributes.get("name") ?? "")
      .trim()
      .toLowerCase();
    const content = attributes.get("content");
    if (key === "" || content === undefined || meta.has(key)) {
      continue;
    }
    meta.set(key, content);
  }

  const first = (...keys: string[]): string | null => {
    for (const key of keys) {
      const value = meta.get(key);
      if (value !== undefined && cleanText(value) !== "") {
        return value;
      }
    }
    return null;
  };

  const titleTag = html.match(titlePattern)?.[1] ?? null;
  const title = first("og:title", "twitter:title") ?? titleTag;
  const description = first(
    "og:description",
    "twitter:description",
    "description",
  );
  const image = first(
    "og:image",
    "og:image:url",
    "og:image:secure_url",
    "twitter:image",
    "twitter:image:src",
  );
  const siteName = first("og:site_name", "application-name");

  return {
    title: limit(title, MAX_TITLE),
    description: limit(description, MAX_DESCRIPTION),
    image_url: resolveImageUrl(image, pageUrl),
    site_name: limit(siteName, MAX_SITE_NAME),
  };
}

export function parseAttributes(tag: string): Map<string, string> {
  const attributes = new Map<string, string>();
  for (const match of tag.matchAll(attributePattern)) {
    const name = match[1].toLowerCase();
    if (!attributes.has(name)) {
      attributes.set(name, match[2] ?? match[3] ?? match[4] ?? "");
    }
  }
  return attributes;
}

/** Only absolute http(s) images are kept. */
export function resolveImageUrl(
  value: string | null,
  pageUrl: string,
): string | null {
  if (value === null) {
    return null;
  }
  try {
    const url = new URL(decodeEntities(value).trim(), pageUrl);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return null;
    }
    if (url.username !== "" || url.password !== "") {
      return null;
    }
    return url.href.length > MAX_IMAGE_URL ? null : url.href;
  } catch {
    return null;
  }
}

function limit(value: string | null, max: number): string | null {
  if (value === null) {
    return null;
  }
  const text = cleanText(value);
  if (text === "") {
    return null;
  }
  const chars = Array.from(text);
  return chars.length > max ? `${chars.slice(0, max - 1).join("")}…` : text;
}

/** Decodes entities, drops tags and collapses whitespace. */
export function cleanText(value: string): string {
  return decodeEntities(value.replace(/<[^>]*>/g, " "))
    .replace(/\s+/g, " ")
    .trim();
}

const namedEntities: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
  ndash: "–",
  mdash: "—",
  hellip: "…",
  lsquo: "‘",
  rsquo: "’",
  ldquo: "“",
  rdquo: "”",
  middot: "·",
  copy: "©",
  reg: "®",
  trade: "™",
};

export function decodeEntities(value: string): string {
  return value.replace(
    /&(#x[0-9a-f]+|#\d+|[a-z]+);/gi,
    (entity, body: string) => {
      if (body[0] === "#") {
        const code = body[1] === "x" || body[1] === "X"
          ? parseInt(body.slice(2), 16)
          : parseInt(body.slice(1), 10);
        if (!Number.isFinite(code) || code <= 0 || code > 0x10ffff) {
          return entity;
        }
        if (code >= 0xd800 && code <= 0xdfff) {
          return entity;
        }
        return String.fromCodePoint(code);
      }
      return namedEntities[body.toLowerCase()] ?? entity;
    },
  );
}

/** The charset named in a Content-Type header, if any. */
export function charsetFromContentType(contentType: string): string | null {
  const match = contentType.match(/charset\s*=\s*"?([^";\s]+)"?/i);
  return match ? match[1].toLowerCase() : null;
}

export function isHtmlContentType(contentType: string | null): boolean {
  if (contentType === null) {
    return false;
  }
  return contentType.split(";")[0].trim().toLowerCase() === "text/html";
}
