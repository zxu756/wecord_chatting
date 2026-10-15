// Searches GIPHY for the composer's GIF picker: POST {query?, limit?,
// offset?} gives {gifs: [{id, title, url, preview_url, width, height}]},
// trending GIFs without a query. Signed-in users only. The API key stays
// here; returns 503 gif_not_configured until GIPHY_API_KEY is set as a
// function secret.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  giphyUrl,
  mapGiphyResponse,
  parseGifRequest,
  readGiphyKey,
} from "./giphy.ts";

const FETCH_TIMEOUT_MS = 6_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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
  if (!supabaseUrl || !anonKey) {
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

  let body: unknown;
  try {
    const text = await request.text();
    body = text.trim() === "" ? {} : JSON.parse(text);
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const search = parseGifRequest(body);
  if (!search) {
    return json({ error: "invalid_query" }, 400);
  }

  const apiKey = readGiphyKey((name) => Deno.env.get(name));
  if (!apiKey) {
    return json({ error: "gif_not_configured" }, 503);
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(giphyUrl(apiKey, search), {
      signal: controller.signal,
      headers: { "Accept": "application/json" },
    });
    if (!response.ok) {
      await response.body?.cancel();
      console.error("giphy request failed", response.status);
      return json({ error: "provider_failed" }, 502);
    }
    return json({ gifs: mapGiphyResponse(await response.json()) });
  } catch (error) {
    console.error("giphy request failed", String(error));
    return json({ error: "provider_failed" }, 502);
  } finally {
    clearTimeout(timer);
  }
});
