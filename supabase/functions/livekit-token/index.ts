// Mints a LiveKit access token for a voice channel the caller may connect
// to. The room is the channel id and the participant identity is the user
// id. Returns 503 voice_not_configured until LIVEKIT_URL, LIVEKIT_API_KEY
// and LIVEKIT_API_SECRET are set as function secrets.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  buildClaims,
  parseChannelId,
  readLiveKitConfig,
  signJwt,
} from "./token.ts";

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

interface VoiceAccess {
  channel_id: string;
  channel_name: string;
  circle_id: string;
  display_name: string | null;
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
  // Runs as the caller, so the permission check below sees their rights.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(
    token,
  );
  const user = userData?.user;
  if (userError || !user) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const channelId = parseChannelId(body);
  if (!channelId) {
    return json({ error: "invalid_channel" }, 400);
  }

  const { data: access, error: accessError } = await userClient.rpc(
    "can_current_user_connect_voice",
    { target_channel_id: channelId },
  );
  if (accessError) {
    return json({ error: "lookup_failed" }, 500);
  }
  if (!access) {
    return json({ error: "forbidden" }, 403);
  }

  const config = readLiveKitConfig((name) => Deno.env.get(name));
  if (!config) {
    return json({ error: "voice_not_configured" }, 503);
  }

  const voice = access as VoiceAccess;
  const claims = buildClaims({
    apiKey: config.apiKey,
    identity: user.id,
    name: voice.display_name?.trim() || user.id,
    room: voice.channel_id,
    nowSeconds: Math.floor(Date.now() / 1000),
  });
  return json({
    url: config.url,
    token: await signJwt(claims, config.apiSecret),
  });
});
