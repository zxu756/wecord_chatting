// Reading an RSS or Atom feed, for the feed-fetch function (roadmap I6).
//
// A small, strict reader written for one job: pull the few fields a card
// needs out of a document from a server nobody vouches for. It never builds
// anything from the document but plain strings:
//
//  * a document with a DOCTYPE or an ENTITY declaration is refused outright
//    (no external or recursive entities, no "billion laughs");
//  * only the five XML entities and numeric references are decoded (plus a
//    few common HTML ones in the descriptions); nothing is fetched or run;
//  * the element tree is limited in depth and size, and only the first 50
//    items are read;
//  * only these fields are kept: the feed's title, and per item its id, title,
//    link, summary and date. Links must be https; texts are turned into plain
//    text (tags dropped, entities decoded, spaces tidied, cut short).
//
// The texts are escaped where they are drawn (the app draws every card text as
// plain text, never as markdown or HTML), and the database cleans them again.

export const MAX_ITEMS = 50;
const MAX_DEPTH = 24;
const MAX_NODES = 30000;
const MAX_TITLE = 200;
const MAX_SUMMARY = 400;
const MAX_LINK = 500;

export class FeedError extends Error {
  constructor(readonly code: "doctype_refused" | "not_a_feed" | "bad_xml") {
    super(code);
  }
}

export type FeedItem = {
  /** What identifies the item: its id, else its link, else title and date. */
  id: string;
  title: string;
  link: string | null;
  summary: string;
  /** ISO 8601, or null when the feed gives none we can read. */
  published: string | null;
};

export type ParsedFeed = {
  title: string;
  items: FeedItem[];
};

type XmlNode = {
  /** Lower-case name with its prefix: "content:encoded". */
  name: string;
  /** Lower-case name without the prefix. */
  local: string;
  attrs: Record<string, string>;
  children: XmlNode[];
  text: string;
};

const NAMED_ENTITIES: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
};

// A few that show up in HTML inside descriptions.
const HTML_ENTITIES: Record<string, string> = {
  ...NAMED_ENTITIES,
  nbsp: " ",
  hellip: "…",
  mdash: "—",
  ndash: "–",
  lsquo: "‘",
  rsquo: "’",
  ldquo: "“",
  rdquo: "”",
  copy: "©",
  laquo: "«",
  raquo: "»",
  middot: "·",
  bull: "•",
};

function codePointText(value: number): string {
  if (
    !Number.isFinite(value) || value < 0 || value > 0x10ffff ||
    (value >= 0xd800 && value <= 0xdfff)
  ) {
    return "";
  }
  return String.fromCodePoint(value);
}

/** Decodes numeric references and the entities in [table]; others stay. */
function decodeEntities(
  text: string,
  table: Record<string, string>,
): string {
  return text.replace(
    /&(#x[0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,10});/g,
    (whole, body: string) => {
      if (body[0] === "#") {
        const value = body[1] === "x" || body[1] === "X"
          ? parseInt(body.slice(2), 16)
          : parseInt(body.slice(1), 10);
        return codePointText(value);
      }
      return table[body] ?? whole;
    },
  );
}

/** The elements of [xml], as a tree of plain objects. */
export function parseXml(xml: string): XmlNode {
  if (/<!\s*(doctype|entity)\b/i.test(xml)) {
    throw new FeedError("doctype_refused");
  }
  const root: XmlNode = {
    name: "#root",
    local: "#root",
    attrs: {},
    children: [],
    text: "",
  };
  const stack: XmlNode[] = [root];
  let index = 0;
  let nodes = 0;
  const length = xml.length;

  while (index < length) {
    const open = xml.indexOf("<", index);
    const current = stack[stack.length - 1];
    if (open === -1) {
      current.text += decodeEntities(xml.slice(index), NAMED_ENTITIES);
      break;
    }
    if (open > index) {
      current.text += decodeEntities(xml.slice(index, open), NAMED_ENTITIES);
    }
    if (xml.startsWith("<!--", open)) {
      const end = xml.indexOf("-->", open + 4);
      if (end === -1) throw new FeedError("bad_xml");
      index = end + 3;
    } else if (xml.startsWith("<![CDATA[", open)) {
      const end = xml.indexOf("]]>", open + 9);
      if (end === -1) throw new FeedError("bad_xml");
      // CDATA is literal text: no entity decoding.
      current.text += xml.slice(open + 9, end);
      index = end + 3;
    } else if (xml.startsWith("<?", open)) {
      const end = xml.indexOf("?>", open + 2);
      if (end === -1) throw new FeedError("bad_xml");
      index = end + 2;
    } else if (xml.startsWith("<!", open)) {
      throw new FeedError("doctype_refused");
    } else if (xml.startsWith("</", open)) {
      const end = xml.indexOf(">", open + 2);
      if (end === -1) throw new FeedError("bad_xml");
      const name = xml.slice(open + 2, end).trim().toLowerCase();
      // Close the nearest open element of that name; a stray end tag that
      // matches nothing is ignored (feeds in the wild are not always tidy).
      for (let depth = stack.length - 1; depth > 0; depth--) {
        if (stack[depth].name === name) {
          stack.length = depth;
          break;
        }
      }
      index = end + 1;
    } else {
      const tag = readTag(xml, open);
      if (tag === null) throw new FeedError("bad_xml");
      nodes++;
      if (nodes > MAX_NODES) throw new FeedError("bad_xml");
      const node: XmlNode = {
        name: tag.name,
        local: tag.name.includes(":")
          ? tag.name.slice(tag.name.indexOf(":") + 1)
          : tag.name,
        attrs: tag.attrs,
        children: [],
        text: "",
      };
      current.children.push(node);
      // Past the depth limit an element is kept but not entered, so a pile
      // of unclosed tags inside one description cannot sink the whole feed.
      if (!tag.selfClosing && stack.length < MAX_DEPTH) {
        stack.push(node);
      }
      index = tag.end;
    }
  }
  return root;
}

type Tag = {
  name: string;
  attrs: Record<string, string>;
  selfClosing: boolean;
  end: number;
};

/** Reads `<name a="b" c='d'>` starting at [open]. */
function readTag(xml: string, open: number): Tag | null {
  let index = open + 1;
  const nameStart = index;
  while (index < xml.length && !/[\s/>]/.test(xml[index])) index++;
  const name = xml.slice(nameStart, index).toLowerCase();
  if (!/^[a-z_][a-z0-9_.:-]*$/.test(name)) return null;
  const attrs: Record<string, string> = {};
  let attributeCount = 0;
  while (index < xml.length) {
    while (index < xml.length && /\s/.test(xml[index])) index++;
    if (xml[index] === ">") {
      return { name, attrs, selfClosing: false, end: index + 1 };
    }
    if (xml[index] === "/" && xml[index + 1] === ">") {
      return { name, attrs, selfClosing: true, end: index + 2 };
    }
    const keyStart = index;
    while (index < xml.length && !/[\s=/>]/.test(xml[index])) index++;
    const key = xml.slice(keyStart, index).toLowerCase();
    if (key === "") return null;
    while (index < xml.length && /\s/.test(xml[index])) index++;
    let value = "";
    if (xml[index] === "=") {
      index++;
      while (index < xml.length && /\s/.test(xml[index])) index++;
      const quote = xml[index];
      if (quote === '"' || quote === "'") {
        const end = xml.indexOf(quote, index + 1);
        if (end === -1) return null;
        value = xml.slice(index + 1, end);
        index = end + 1;
      } else {
        const valueStart = index;
        while (index < xml.length && !/[\s>]/.test(xml[index])) index++;
        value = xml.slice(valueStart, index);
      }
    }
    // Eight attributes are plenty for what is read here.
    if (attributeCount++ < 8) {
      attrs[key] = decodeEntities(value, NAMED_ENTITIES);
    }
  }
  return null;
}

function childrenNamed(node: XmlNode, name: string): XmlNode[] {
  return node.children.filter((child) => child.name === name);
}

function firstText(node: XmlNode, ...names: string[]): string {
  for (const name of names) {
    const found = childrenNamed(node, name)[0];
    if (found !== undefined) {
      const text = found.text.trim();
      if (text !== "") return text;
    }
  }
  return "";
}

/** Plain text out of text that may hold HTML: no tags, no scripts, tidy. */
export function plainText(raw: string, max: number): string {
  let text = raw
    .replace(/<(script|style)\b[\s\S]*?<\/\1\s*>/gi, " ")
    .replace(/<br\s*\/?>|<\/(p|div|li|h[1-6]|tr)\s*>/gi, " ")
    .replace(/<[^>]*>/g, " ");
  text = decodeEntities(text, HTML_ENTITIES);
  // Decoding can reveal a tag that was double-escaped: drop those too.
  text = text.replace(/<[^>]*>/g, " ");
  text = text
    .replace(
      // deno-lint-ignore no-control-regex
      /[\u0000-\u001f\u007f​-‏‪-‮⁠-⁤⁦-⁩﻿]/g,
      " ",
    )
    .replace(/\s+/g, " ")
    .trim();
  const chars = [...text];
  return chars.length > max
    ? chars.slice(0, max - 1).join("").trim() + "…"
    : text;
}

/** [raw] as an https address (relative ones resolved on [base]), or null. */
export function safeLink(raw: string, base: string): string | null {
  const trimmed = raw.trim();
  if (trimmed === "" || trimmed.length > MAX_LINK * 2) return null;
  let url: URL;
  try {
    url = new URL(trimmed, base);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.username !== "" || url.password !== "") {
    return null;
  }
  url.hash = "";
  const text = url.toString();
  return text.length <= MAX_LINK ? text : null;
}

/** An ISO time, or null when [raw] is not a time or is far in the future. */
export function readDate(raw: string, now: number): string | null {
  const text = raw.trim();
  if (text === "") return null;
  const time = Date.parse(text);
  if (!Number.isFinite(time) || time > now + 24 * 3600 * 1000 || time < 0) {
    return null;
  }
  return new Date(time).toISOString();
}

function itemLink(item: XmlNode, base: string): string | null {
  for (const link of childrenNamed(item, "link")) {
    const rel = (link.attrs["rel"] ?? "alternate").toLowerCase();
    if (rel !== "alternate") continue;
    const href = link.attrs["href"];
    const found = safeLink(href ?? link.text, base);
    if (found !== null) return found;
  }
  return null;
}

function readItem(item: XmlNode, base: string, now: number): FeedItem | null {
  const title = plainText(firstText(item, "title"), MAX_TITLE);
  const summary = plainText(
    firstText(item, "description", "summary", "content:encoded", "content"),
    MAX_SUMMARY,
  );
  const link = itemLink(item, base);
  if (title === "" && summary === "") return null;
  const published = readDate(
    firstText(item, "pubdate", "published", "updated", "dc:date", "date"),
    now,
  );
  const identifier = firstText(item, "guid", "id");
  return {
    id: identifier !== ""
      ? identifier.slice(0, 500)
      : (link ?? `${title}|${published ?? ""}`),
    title,
    link,
    summary,
    published,
  };
}

function findAll(node: XmlNode, names: Set<string>, found: XmlNode[]): void {
  for (const child of node.children) {
    if (found.length >= MAX_ITEMS) return;
    if (names.has(child.name)) {
      found.push(child);
    } else {
      findAll(child, names, found);
    }
  }
}

/**
 * Reads an RSS 0.9x/2.0, RSS 1.0 (RDF) or Atom 1.0 document. [base] is the
 * address it came from (relative links resolve on it), [now] milliseconds
 * since 1970. Throws a [FeedError].
 */
export function parseFeed(xml: string, base: string, now: number): ParsedFeed {
  const root = parseXml(xml);
  const top = root.children.find((child) =>
    ["rss", "feed", "rdf:rdf", "rdf"].includes(child.name)
  );
  if (top === undefined) {
    throw new FeedError("not_a_feed");
  }

  // The feed's own title: the title right under the channel or the feed.
  const holder = top.name === "rss"
    ? childrenNamed(top, "channel")[0] ?? top
    : top.name.endsWith("rdf") || top.name === "rdf:rdf"
    ? childrenNamed(top, "channel")[0] ?? top
    : top;
  const title = plainText(firstText(holder, "title"), 80);

  const elements: XmlNode[] = [];
  findAll(top, new Set(["item", "entry"]), elements);
  const items: FeedItem[] = [];
  for (const element of elements) {
    const item = readItem(element, base, now);
    if (item !== null) items.push(item);
  }
  return { title, items };
}

/** A short stable key for [item]: 16 hex digits of a SHA-256. */
export async function itemKey(item: FeedItem): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(item.id),
  );
  return [...new Uint8Array(digest).slice(0, 8)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
