// Reading a feed from the web, safely (roadmap I6).
//
// The address is the one a circle's manager typed, so it is treated like any
// address from outside:
//
//  * https on the default port only, a real host name, no user name or
//    password, and every address the name resolves to must be public
//    (supabase/functions/_shared/ssrf.ts, the same check the bots' event and
//    callback sends use) - before the first request and again before every
//    redirect, which are followed by hand, at most 3, never to another
//    scheme;
//  * 8 seconds for the whole read (the answer and its body), no cookies, no
//    credentials, one request at a time per web site (the claim in the
//    database picks one feed per site);
//  * the body is read as a stream and stops at 512 KB, however it is
//    compressed (what counts is what is read after decompression);
//  * a feed that sends an ETag or Last-Modified is asked "has it changed?"
//    the next time, so an unchanged feed costs almost nothing.
//
// A name could resolve to something else between the check and the request
// (DNS rebinding). The answer is only ever parsed for a handful of text fields
// and never passed on, so the most that can happen is one GET to a public
// address the manager chose... or, with a rebinding trick, to an inner one
// whose answer is not a feed and is dropped without being shown to anyone.
import { type Resolver, resolveSafeUrl } from "../_shared/ssrf.ts";

export const FETCH_TIMEOUT_MS = 8000;
export const MAX_BODY_BYTES = 512 * 1024;
export const MAX_REDIRECTS = 3;
export const USER_AGENT = "WeCord-Feeds/1 (+https://wecord.jokebear.fyi)";

export type Deps = {
  resolve: Resolver;
  fetch: typeof fetch;
  /** Milliseconds since 1970. */
  now: () => number;
};

export type Conditional = {
  etag: string | null;
  lastModified: string | null;
};

export type FetchResult =
  | {
    kind: "ok";
    text: string;
    /** The address the body came from (after redirects). */
    finalUrl: string;
    etag: string | null;
    lastModified: string | null;
    status: number;
  }
  | { kind: "not_modified"; status: 304 }
  | {
    kind: "error";
    /** A short code from a fixed list, never anything the server said. */
    code: string;
    status: number | null;
    /** True when trying again later cannot help. */
    permanent: boolean;
  };

// Reasons the address check gives that no later read can fix.
const PERMANENT_REASONS = new Set([
  "bad_url",
  "not_https",
  "credentials_in_url",
  "port_not_allowed",
  "ip_address",
  "inner_name",
  "bad_host",
  "inner_address",
]);

const REFUSED_TYPES =
  /^(image|video|audio|font)\/|^application\/(pdf|zip|gzip|x-gzip)/i;

function failure(
  code: string,
  status: number | null,
  permanent = false,
): FetchResult {
  return { kind: "error", code, status, permanent };
}

/** Reads at most [limit] bytes; null when the body is longer. */
async function readLimited(
  response: Response,
  limit: number,
): Promise<Uint8Array | null> {
  const reader = response.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > limit) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

/** The text of [bytes], in the encoding the XML declaration names (UTF-8 if none). */
export function decodeBody(bytes: Uint8Array): string {
  const head = new TextDecoder("latin1").decode(bytes.slice(0, 200));
  const declared = /<\?xml[^>]*encoding\s*=\s*["']([A-Za-z0-9_.:-]+)["']/i
    .exec(head)?.[1];
  if (declared !== undefined && !/^utf-?8$/i.test(declared)) {
    try {
      return new TextDecoder(declared.toLowerCase()).decode(bytes);
    } catch {
      // An encoding the runtime does not know: read it as UTF-8.
    }
  }
  return new TextDecoder("utf-8").decode(bytes);
}

/** One safe read of the feed at [startUrl]. Never throws. */
export async function fetchFeed(
  startUrl: string,
  conditional: Conditional,
  deps: Deps,
): Promise<FetchResult> {
  const signal = AbortSignal.timeout(FETCH_TIMEOUT_MS);
  let current = startUrl;
  try {
    for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
      const safe = await resolveSafeUrl(current, deps.resolve);
      if (!safe.ok) {
        // An address the manager typed that can never be used is final; a
        // redirect to one may be a passing mistake of the site.
        return failure(
          safe.reason,
          null,
          hop === 0 && PERMANENT_REASONS.has(safe.reason),
        );
      }

      const headers: Record<string, string> = {
        "User-Agent": USER_AGENT,
        "Accept":
          "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.5",
      };
      // The cache headers belong to the address the person gave, not to where
      // a redirect led.
      if (hop === 0) {
        if (conditional.etag) headers["If-None-Match"] = conditional.etag;
        if (conditional.lastModified) {
          headers["If-Modified-Since"] = conditional.lastModified;
        }
      }
      const response = await deps.fetch(safe.url, {
        method: "GET",
        headers,
        redirect: "manual",
        credentials: "omit",
        signal,
      });

      if (response.status === 304 && hop === 0) {
        await response.body?.cancel();
        return { kind: "not_modified", status: 304 };
      }
      if (response.status >= 300 && response.status < 400) {
        await response.body?.cancel();
        const location = response.headers.get("Location");
        if (!location || hop === MAX_REDIRECTS) {
          return failure("too_many_redirects", response.status);
        }
        try {
          current = new URL(location, safe.url).toString();
        } catch {
          return failure("bad_redirect", response.status);
        }
        continue;
      }
      if (response.status === 410) {
        await response.body?.cancel();
        return failure("http_410", 410, true);
      }
      if (response.status === 429 || response.status === 503) {
        await response.body?.cancel();
        return failure("rate_limited", response.status);
      }
      if (response.status !== 200) {
        await response.body?.cancel();
        return failure(`http_${response.status}`, response.status);
      }

      const type = response.headers.get("Content-Type") ?? "";
      if (REFUSED_TYPES.test(type.trim())) {
        await response.body?.cancel();
        return failure("not_a_feed", 200, true);
      }
      const declared = Number(response.headers.get("Content-Length"));
      if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
        await response.body?.cancel();
        return failure("too_big", 200);
      }
      const bytes = await readLimited(response, MAX_BODY_BYTES);
      if (bytes === null) {
        return failure("too_big", 200);
      }
      return {
        kind: "ok",
        text: decodeBody(bytes),
        finalUrl: safe.url.toString(),
        etag: response.headers.get("ETag"),
        lastModified: response.headers.get("Last-Modified"),
        status: 200,
      };
    }
    return failure("too_many_redirects", null);
  } catch (error) {
    if (error instanceof DOMException && error.name === "TimeoutError") {
      return failure("timeout", null);
    }
    if (error instanceof DOMException && error.name === "AbortError") {
      return failure("timeout", null);
    }
    return failure("network", null);
  }
}
