// Fetches Open Graph metadata for a link so chat messages can show a preview
// card. Only signed-in users may call it; private and internal addresses are
// refused at every redirect hop; results are cached in public.link_previews.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  charsetFromContentType,
  extractPreviewMeta,
  isHtmlContentType,
  type PreviewMeta,
} from "./html_meta.ts";
import { assessRedirect, type LinkRisk } from "./link_risk.ts";
import {
  bareHostname,
  isBlockedAddress,
  isIpLiteral,
  normalizePreviewUrl,
} from "./ip_guard.ts";

const FETCH_TIMEOUT_MS = 5_000;
const MAX_BODY_BYTES = 512 * 1024;
const MAX_REDIRECTS = 3;
const FRESH_MS = 24 * 60 * 60 * 1000;
const FAILURE_FRESH_MS = 60 * 60 * 1000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type PreviewStatus = "ok" | "error" | "blocked" | "unsupported";

interface PreviewRow extends PreviewMeta {
  url: string;
  status: PreviewStatus;
  fetched_at: string;
  /// Where the link ended after its redirects, when that is somewhere else.
  final_url?: string | null;
}

/// What the app gets: the row without its internals and the link's risk
/// (see link_risk.ts), worked out from the address alone.
function respond(row: PreviewRow): Response {
  const { final_url: finalUrl, ...rest } = row;
  const risk: LinkRisk = assessRedirect(row.url, finalUrl);
  return json({
    ...rest,
    risk: { level: risk.level, reasons: risk.reasons },
    final_host: finalUrl ? hostOf(finalUrl) : null,
  });
}

function hostOf(url: string): string | null {
  try {
    return new URL(url).hostname.toLowerCase().replace(/^www\./, "");
  } catch {
    return null;
  }
}

class PreviewFailure extends Error {
  constructor(readonly status: Exclude<PreviewStatus, "ok">, message: string) {
    super(message);
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "not_configured" }, 500);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (token === "" || token === authorization) {
    return json({ error: "unauthorized" }, 401);
  }
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(
    token,
  );
  if (userError || !userData?.user) {
    return json({ error: "unauthorized" }, 401);
  }

  let rawUrl: unknown;
  try {
    rawUrl = (await request.json())?.url;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (typeof rawUrl !== "string") {
    return json({ error: "invalid_url" }, 400);
  }
  const checked = normalizePreviewUrl(rawUrl);
  if (!checked.ok) {
    if (checked.reason === "invalid") {
      return json({ error: "invalid_url" }, 400);
    }
    // Refused before any lookup; nothing worth caching.
    return respond(emptyRow(rawUrl.trim(), checked.reason));
  }
  const url = checked.url.href;

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: cached } = await admin
    .from("link_previews")
    .select(
      "url,title,description,image_url,site_name,status,fetched_at,final_url",
    )
    .eq("url", url)
    .maybeSingle<PreviewRow>();
  if (cached && isFresh(cached)) {
    return respond(cached);
  }

  let row: PreviewRow;
  try {
    const { meta, finalUrl } = await fetchPreview(checked.url);
    row = {
      url,
      status: "ok",
      fetched_at: new Date().toISOString(),
      final_url: finalUrl !== url ? finalUrl : null,
      ...meta,
    };
  } catch (error) {
    const status = error instanceof PreviewFailure ? error.status : "error";
    row = emptyRow(url, status);
  }

  const { error: upsertError } = await admin.from("link_previews").upsert(row);
  if (upsertError) {
    console.error("link_previews upsert failed", upsertError.message);
  }
  return respond(row);
});

function emptyRow(url: string, status: PreviewStatus): PreviewRow {
  return {
    url,
    status,
    title: null,
    description: null,
    image_url: null,
    site_name: null,
    fetched_at: new Date().toISOString(),
  };
}

function isFresh(row: PreviewRow): boolean {
  const age = Date.now() - new Date(row.fetched_at).getTime();
  return age >= 0 && age < (row.status === "ok" ? FRESH_MS : FAILURE_FRESH_MS);
}

/** Every address the host resolves to must be public. */
async function assertPublicHost(url: URL): Promise<void> {
  const host = bareHostname(url.hostname);
  if (isIpLiteral(host)) {
    if (isBlockedAddress(host)) {
      throw new PreviewFailure("blocked", "private address");
    }
    return;
  }
  const lookups = await Promise.allSettled([
    Deno.resolveDns(host, "A"),
    Deno.resolveDns(host, "AAAA"),
  ]);
  const addresses = lookups.flatMap((lookup) =>
    lookup.status === "fulfilled" ? lookup.value : []
  );
  if (addresses.length === 0) {
    throw new PreviewFailure("error", "host did not resolve");
  }
  if (addresses.some(isBlockedAddress)) {
    throw new PreviewFailure("blocked", "host resolves to a private address");
  }
}

async function fetchPreview(
  start: URL,
): Promise<{ meta: PreviewMeta; finalUrl: string }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    let current = start;
    for (let hop = 0;; hop++) {
      await assertPublicHost(current);
      const response = await fetch(current, {
        redirect: "manual",
        signal: controller.signal,
        headers: {
          "User-Agent":
            "Mozilla/5.0 (compatible; WeCordLinkPreview/1.0; +https://wecord.app)",
          "Accept": "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1",
          "Accept-Language": "en,zh;q=0.8,*;q=0.5",
        },
      });

      if (response.status >= 300 && response.status < 400) {
        await response.body?.cancel();
        const location = response.headers.get("Location");
        if (location === null || hop >= MAX_REDIRECTS) {
          throw new PreviewFailure("error", "too many redirects");
        }
        const next = normalizePreviewUrl(location, current.href);
        if (!next.ok) {
          throw new PreviewFailure(
            next.reason === "invalid" ? "error" : next.reason,
            "redirect target refused",
          );
        }
        current = next.url;
        continue;
      }

      if (!response.ok) {
        await response.body?.cancel();
        throw new PreviewFailure("error", `status ${response.status}`);
      }
      const contentType = response.headers.get("Content-Type");
      if (!isHtmlContentType(contentType)) {
        await response.body?.cancel();
        throw new PreviewFailure("unsupported", "not html");
      }
      const html = await readLimitedText(
        response,
        charsetFromContentType(contentType ?? ""),
      );
      return {
        meta: extractPreviewMeta(html, current.href),
        finalUrl: current.href,
      };
    }
  } finally {
    clearTimeout(timer);
  }
}

async function readLimitedText(
  response: Response,
  charset: string | null,
): Promise<string> {
  const reader = response.body?.getReader();
  if (!reader) {
    return "";
  }
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (total < MAX_BODY_BYTES) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    const remaining = MAX_BODY_BYTES - total;
    const chunk = value.byteLength > remaining
      ? value.subarray(0, remaining)
      : value;
    chunks.push(chunk);
    total += chunk.byteLength;
  }
  await reader.cancel().catch(() => {});

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let decoder: TextDecoder;
  try {
    decoder = new TextDecoder(charset ?? "utf-8");
  } catch {
    decoder = new TextDecoder("utf-8");
  }
  return decoder.decode(bytes);
}
