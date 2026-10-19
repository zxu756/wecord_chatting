// A published note, for people without WeCord (roadmap D5): GET
// /note-public/<token> answers the note as JSON, and the web app draws it
// read-only at https://<site>/n/<token> (lib/features/notes/public/).
//
// Why JSON and not a page of HTML: Supabase serves any HTML an Edge Function
// sends on its own domain as plain text, so a page cannot come from here
// (and DNS and domains are not ours to change). The app draws the blocks with
// its own widgets - text is never parsed as markup anywhere - so there is no
// HTML for a note to inject into. Still, everything is cleaned here:
//
//  * the token is the credential: 192 random bits (48 hex digits). It is
//    looked up inside the database function public_note_by_token, which
//    answers "invalid" for every reason a link can be dead (unknown, withdrawn,
//    note deleted, circle suspended, publisher gone) so that nothing tells
//    one from another. Only the service role may call it;
//  * what leaves is rebuilt from scratch from known kinds, known props and
//    plain text: unknown kinds become paragraphs, a mark is bold, italic,
//    strike, code or a web link (http or https only - no javascript: or data:
//    links), table cells are text, a picture is only a short-lived signed link
//    to a file of this very note (a path anywhere else is dropped), nothing
//    else is passed on;
//  * no comments, no names, no ids of people;
//  * every answer carries a content security policy that allows nothing,
//    nosniff, no referrer and noindex (the page itself asks search engines
//    not to list it unless the author chose to; see allow_indexing);
//  * addresses that keep sending wrong tokens are turned away (20 a minute
//    per running instance).
import { WindowLimiter } from "./limiter.ts";

export { WindowLimiter };

export const BLOCK_KINDS = [
  "paragraph",
  "h1",
  "h2",
  "h3",
  "bullet",
  "numbered",
  "todo",
  "quote",
  "code",
  "divider",
  "image",
  "table",
] as const;
export type BlockKind = (typeof BLOCK_KINDS)[number];

export type PublicMark = [number, number, string];

export type PublicBlock = {
  id: string;
  kind: BlockKind;
  text: string;
  marks: PublicMark[];
  props: Record<string, unknown>;
};

export type PublicNote = {
  title: string;
  icon: string;
  updated_at: string | null;
  allow_indexing: boolean;
  blocks: PublicBlock[];
};

/** What public_note_by_token answers. */
export type LookupResult =
  | {
    status: "ok";
    note_id: string;
    title: string;
    icon: string;
    updated_at: string | null;
    allow_indexing: boolean;
    blocks: unknown[];
  }
  | { status: "invalid" };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const MAX_TEXT = 20_000;
const MAX_BLOCKS = 5_000;
const MAX_MARKS = 1_000;
const MAX_URL = 2_000;
const MAX_CELL = 1_000;
const SIGNED_SECONDS = 3_600;

/** The token in `/note-public/<token>`, or null for any other path. */
export function tokenFromPath(pathname: string): string | null {
  const last = pathname.split("/").filter((part) => part.length > 0).pop() ??
    "";
  return /^[0-9a-f]{48}$/.test(last) ? last : null;
}

/** [value] as plain text without control characters (tab and newline stay). */
export function cleanText(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  // deno-lint-ignore no-control-regex
  return value.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    .slice(0, max);
}

/** Whether [url] is a web link a reader may follow. */
export function isSafeLink(url: string): boolean {
  if (url.length === 0 || url.length > MAX_URL) return false;
  try {
    const parsed = new URL(url);
    return (parsed.protocol === "https:" || parsed.protocol === "http:") &&
      parsed.hostname.length > 0;
  } catch {
    return false;
  }
}

function cleanMarks(value: unknown, textLength: number): PublicMark[] {
  if (!Array.isArray(value)) return [];
  const marks: PublicMark[] = [];
  for (const mark of value.slice(0, MAX_MARKS)) {
    if (!Array.isArray(mark) || mark.length < 3) continue;
    const [start, end, type] = mark;
    if (
      typeof start !== "number" || typeof end !== "number" ||
      !Number.isInteger(start) || !Number.isInteger(end) ||
      typeof type !== "string"
    ) continue;
    const from = Math.max(0, Math.min(start, textLength));
    const to = Math.max(0, Math.min(end, textLength));
    if (to <= from) continue;
    if (type === "b" || type === "i" || type === "s" || type === "c") {
      marks.push([from, to, type]);
    } else if (type.startsWith("l:") && isSafeLink(type.slice(2))) {
      marks.push([from, to, type]);
    }
    // Mentions (m:<user>) and anything unknown are dropped.
  }
  return marks;
}

function cleanTable(props: Record<string, unknown>): Record<string, unknown> {
  const cols = Array.isArray(props.cols)
    ? props.cols.filter((col): col is string =>
      typeof col === "string" && col.length > 0 && col.length <= 16
    ).slice(0, 12)
    : [];
  const rows: { id: string; c: Record<string, string> }[] = [];
  if (Array.isArray(props.rows)) {
    for (const row of props.rows.slice(0, 200)) {
      if (row === null || typeof row !== "object") continue;
      const source = row as Record<string, unknown>;
      const cells = source.c !== null && typeof source.c === "object"
        ? source.c as Record<string, unknown>
        : {};
      const c: Record<string, string> = {};
      for (const col of cols) {
        const text = cleanText(cells[col], MAX_CELL);
        if (text !== "") c[col] = text;
      }
      rows.push({ id: cleanText(source.id, 16), c });
    }
  }
  return { header: props.header === true, cols, rows };
}

/** The path of a note's picture when it is a file of that note. */
export function imagePathOf(
  noteId: string,
  props: Record<string, unknown>,
): string | null {
  const path = props.path;
  if (typeof path !== "string" || !UUID.test(noteId)) return null;
  const prefix = `${noteId}/`;
  if (!path.startsWith(prefix)) return null;
  const file = path.slice(prefix.length);
  return /^[A-Za-z0-9._-]{1,120}$/.test(file) && !file.includes("..")
    ? path
    : null;
}

/**
 * The blocks of a lookup, rebuilt from known parts. [urls] holds the signed
 * links of the pictures by path.
 */
export function buildBlocks(
  noteId: string,
  raw: unknown[],
  urls: Record<string, string>,
): PublicBlock[] {
  const blocks: PublicBlock[] = [];
  for (const item of raw.slice(0, MAX_BLOCKS)) {
    if (item === null || typeof item !== "object") continue;
    const source = item as Record<string, unknown>;
    const kind = (BLOCK_KINDS as readonly unknown[]).includes(source.kind)
      ? source.kind as BlockKind
      : "paragraph";
    const rawProps = source.props !== null && typeof source.props === "object"
      ? source.props as Record<string, unknown>
      : {};
    const text = kind === "table" || kind === "divider" || kind === "image"
      ? ""
      : cleanText(source.text, MAX_TEXT);
    const block: PublicBlock = {
      id: typeof source.id === "string" && UUID.test(source.id)
        ? source.id
        : "",
      kind,
      text,
      marks: kind === "code" || text === ""
        ? []
        : cleanMarks(source.marks, text.length),
      props: {},
    };
    switch (kind) {
      case "todo":
        block.props = { checked: rawProps.checked === true };
        break;
      case "code": {
        const lang = cleanText(rawProps.lang, 40);
        block.props = lang === "" ? {} : { lang };
        break;
      }
      case "table":
        block.props = cleanTable(rawProps);
        break;
      case "image": {
        const path = imagePathOf(noteId, rawProps);
        const url = path === null ? undefined : urls[path];
        const props: Record<string, unknown> = {
          name: cleanText(rawProps.name, 200),
        };
        if (url !== undefined) props.url = url;
        for (const key of ["width", "height"]) {
          const value = rawProps[key];
          if (typeof value === "number" && Number.isFinite(value)) {
            props[key] = Math.round(Math.max(0, Math.min(value, 20_000)));
          }
        }
        block.props = props;
        break;
      }
    }
    blocks.push(block);
  }
  return blocks;
}

/** The picture paths a lookup wants signed. */
export function imagePathsOf(noteId: string, raw: unknown[]): string[] {
  const paths = new Set<string>();
  for (const item of raw.slice(0, MAX_BLOCKS)) {
    if (item === null || typeof item !== "object") continue;
    const source = item as Record<string, unknown>;
    if (source.kind !== "image") continue;
    const props = source.props !== null && typeof source.props === "object"
      ? source.props as Record<string, unknown>
      : {};
    const path = imagePathOf(noteId, props);
    if (path !== null) paths.add(path);
  }
  return [...paths].slice(0, 200);
}

export type NotePublicDeps = {
  /** public_note_by_token, with the service role. */
  lookup: (token: string) => Promise<LookupResult>;
  /** Signed links (one hour) for files of the `note-files` bucket. */
  sign: (paths: string[]) => Promise<Record<string, string>>;
  now: () => Date;
  /** Wrong tokens per address; guessing is hopeless, this only saves work. */
  badTokens: WindowLimiter;
};

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
};

function headers(extra: Record<string, string> = {}): Headers {
  return new Headers({
    "Cache-Control": "private, no-store",
    "Content-Security-Policy":
      "default-src 'none'; frame-ancestors 'none'; sandbox",
    "Referrer-Policy": "no-referrer",
    "X-Robots-Tag": "noindex, nofollow",
    "X-Content-Type-Options": "nosniff",
    ...corsHeaders,
    ...extra,
  });
}

function json(status: number, body: unknown, extra = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: headers({
      "Content-Type": "application/json; charset=utf-8",
      ...extra,
    }),
  });
}

function clientAddress(request: Request): string {
  return request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    "unknown";
}

export async function handleNotePublicRequest(
  request: Request,
  deps: NotePublicDeps,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: headers() });
  }
  if (request.method !== "GET" && request.method !== "HEAD") {
    return json(405, { error: "method_not_allowed" }, { Allow: "GET, HEAD" });
  }
  const nowMs = deps.now().getTime();
  const missKey = clientAddress(request);
  if (deps.badTokens.isBlocked(missKey, nowMs)) {
    return json(429, { error: "too_many_requests" }, {
      "Retry-After": String(deps.badTokens.retryAfterSeconds(missKey, nowMs)),
    });
  }
  const token = tokenFromPath(new URL(request.url).pathname);
  if (token === null) {
    deps.badTokens.hit(missKey, nowMs);
    return json(404, { error: "not_found" });
  }

  let result: LookupResult;
  try {
    result = await deps.lookup(token);
  } catch {
    return json(503, { error: "try_again_later" }, { "Retry-After": "60" });
  }
  if (
    result === null || typeof result !== "object" || result.status !== "ok" ||
    !Array.isArray(result.blocks)
  ) {
    deps.badTokens.hit(missKey, nowMs);
    // The same answer whatever made the link dead.
    return json(404, { error: "not_found" });
  }

  let urls: Record<string, string> = {};
  const wanted = imagePathsOf(result.note_id, result.blocks);
  if (wanted.length > 0) {
    try {
      urls = await deps.sign(wanted);
    } catch {
      // The pictures are left out; the text is still worth showing.
    }
  }
  const note: PublicNote = {
    title: cleanText(result.title, 200),
    icon: cleanText(result.icon, 16),
    updated_at: typeof result.updated_at === "string"
      ? result.updated_at
      : null,
    allow_indexing: result.allow_indexing === true,
    blocks: buildBlocks(result.note_id, result.blocks, urls),
  };
  if (request.method === "HEAD") {
    return new Response(null, {
      status: 200,
      headers: headers({ "Content-Type": "application/json; charset=utf-8" }),
    });
  }
  return json(200, note);
}

export { SIGNED_SECONDS };
