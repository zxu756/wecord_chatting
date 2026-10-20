// The "wecord" Cloudflare Worker (wrangler.jsonc). The web app is static
// assets; this Worker runs first for two paths only (assets.run_worker_first)
// and draws them as HTML on the server, so a link pasted into a chat app shows
// a card (Open Graph) instead of a bare address:
//
//   /c/<slug>      a public circle's page
//   /invite/<code> an invite to a public circle
//
// Everything else goes straight to the assets without running this code. The
// data comes from the two anon-callable database functions
// get_public_circle_card and get_public_invite_card and nothing else (see
// supabase/migrations/202610260510_public_circle_card.sql); the pages are
// built by render.ts. No DNS or domain setting is involved: the Worker already
// serves the custom domain.

import {
  isInviteCode,
  isSlug,
  type Lang,
  type PageKind,
  parseCard,
  pickLanguage,
  renderCardPage,
  renderErrorPage,
  renderUnavailablePage,
  securityHeaders,
} from "./render.ts";

export interface Env {
  ASSETS: { fetch(request: Request): Promise<Response> };
  /** https://<project>.supabase.co */
  SUPABASE_URL?: string;
  /** The project's anon key (public: it ships in the web app too). */
  SUPABASE_ANON_KEY?: string;
}

interface Context {
  waitUntil(promise: Promise<unknown>): void;
}

export interface Deps {
  fetch: typeof fetch;
  cache: {
    match(key: Request): Promise<Response | undefined>;
    put(key: Request, response: Response): Promise<void>;
  } | null;
}

const LOOKUP_TIMEOUT_MS = 4000;
// How long a page may be served from the edge cache or the browser. Short, so
// a revoked invite or a circle that went private stops showing soon.
const CACHE_SECONDS = 60;

export interface Route {
  kind: PageKind;
  param: string;
}

/**
 * The page a path stands for: /c/<slug> or /invite/<code> (one optional
 * trailing slash). Returns "other" for any path the Worker does not own and
 * "invalid" for one of its paths with a value that can't be a slug or code
 * (those get the unavailable page without asking the database).
 */
export function routeFor(pathname: string): Route | "invalid" | "other" {
  const match = /^\/(c|invite)\/([^/]*)\/?$/.exec(pathname);
  if (!match) return "other";
  let value: string;
  try {
    value = decodeURIComponent(match[2]).toLowerCase();
  } catch {
    return "invalid";
  }
  if (match[1] === "c") {
    return isSlug(value) ? { kind: "circle", param: value } : "invalid";
  }
  return isInviteCode(value) ? { kind: "invite", param: value } : "invalid";
}

type Lookup =
  | { status: "card"; raw: unknown }
  | { status: "error" };

async function lookup(
  route: Route,
  env: Env & { SUPABASE_URL: string; SUPABASE_ANON_KEY: string },
  deps: Deps,
): Promise<Lookup> {
  const fn = route.kind === "circle"
    ? "get_public_circle_card"
    : "get_public_invite_card";
  const body = route.kind === "circle"
    ? { card_slug: route.param }
    : { invite_code: route.param };
  try {
    const base = env.SUPABASE_URL.replace(/\/+$/, "");
    const response = await deps.fetch(`${base}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        apikey: env.SUPABASE_ANON_KEY,
        authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(LOOKUP_TIMEOUT_MS),
    });
    if (!response.ok) return { status: "error" };
    return { status: "card", raw: await response.json() };
  } catch {
    return { status: "error" };
  }
}

async function html(
  body: string,
  status: number,
  request: Request,
  cacheable: boolean,
): Promise<Response> {
  const headers = new Headers(await securityHeaders());
  headers.set("Content-Type", "text/html; charset=utf-8");
  headers.set(
    "Cache-Control",
    cacheable ? `public, max-age=${CACHE_SECONDS}` : "no-store",
  );
  // The language comes from the request, so caches must not mix them.
  headers.set("Vary", "Accept-Language");
  return new Response(request.method === "HEAD" ? null : body, {
    status,
    headers,
  });
}

function cacheKey(url: URL, route: Route, lang: Lang): Request {
  // One entry per page and language; the query string is not part of it.
  return new Request(
    `${url.origin}/__public_pages__/${route.kind}/${route.param}?l=${lang}`,
  );
}

export async function handleRequest(
  request: Request,
  env: Env,
  ctx: Context,
  deps: Deps,
): Promise<Response> {
  const url = new URL(request.url);
  const route = routeFor(url.pathname);
  if (route === "other") return env.ASSETS.fetch(request);

  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", {
      status: 405,
      headers: { Allow: "GET, HEAD", "Cache-Control": "no-store" },
    });
  }

  const lang = pickLanguage(
    request.headers.get("accept-language"),
    url.searchParams.get("lang"),
  );

  if (route === "invalid") {
    return html(renderUnavailablePage(lang, url.origin), 404, request, true);
  }

  // Not configured (a local `wrangler dev`, or a deploy without the key): let
  // the web app answer, as it did before this Worker existed.
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
    return env.ASSETS.fetch(request);
  }

  const key = cacheKey(url, route, lang);
  if (deps.cache) {
    const hit = await deps.cache.match(key);
    if (hit) {
      const headers = new Headers(hit.headers);
      headers.set("Vary", "Accept-Language");
      return new Response(request.method === "HEAD" ? null : hit.body, {
        status: hit.status,
        headers,
      });
    }
  }

  const result = await lookup(
    route,
    env as Env & { SUPABASE_URL: string; SUPABASE_ANON_KEY: string },
    deps,
  );
  if (result.status === "error") {
    return html(renderErrorPage(lang, url.origin), 503, request, false);
  }

  const card = parseCard(result.raw);
  const response = card
    ? await html(
      renderCardPage(card, {
        lang,
        kind: route.kind,
        origin: url.origin,
        param: route.param,
      }),
      200,
      request,
      true,
    )
    : await html(renderUnavailablePage(lang, url.origin), 404, request, true);

  if (deps.cache && request.method === "GET") {
    // Stored without Vary (the key already holds the language); it is put
    // back when the entry is served.
    const stored = new Response(response.clone().body, response);
    stored.headers.delete("Vary");
    ctx.waitUntil(deps.cache.put(key, stored));
  }
  return response;
}

export default {
  fetch(request: Request, env: Env, ctx: Context): Promise<Response> {
    const edgeCache = (globalThis as unknown as {
      caches?: { default?: Deps["cache"] };
    }).caches?.default ?? null;
    return handleRequest(request, env, ctx, {
      fetch: (input, init) => fetch(input, init),
      cache: edgeCache,
    });
  },
};
