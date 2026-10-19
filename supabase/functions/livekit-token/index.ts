// Mints a LiveKit access token for a voice channel the caller may connect
// to ({channel_id}), or for a call in one of their direct or group chats
// ({call_id}). The room is the channel id, or "call-<call id>"; the
// participant identity is the user id. Returns 503 voice_not_configured until LIVEKIT_URL, LIVEKIT_API_KEY
// and LIVEKIT_API_SECRET are set as function secrets.
//
// Server-muted or server-deafened members get a token that can't publish
// their microphone, and a full voice channel answers 409 channel_full.
//
// On a stage channel only the speakers may publish; the audience's token
// can only subscribe.
//
// {enforce: {channel_id, user_id}}, from a member who can mute, deafen or
// move members (or from the member themselves), makes the channel's
// LiveKit room match the database for that member: removes them when they
// are no longer in the channel (moved or disconnected), otherwise updates
// what they may publish (so a new stage speaker can, without
// reconnecting).
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  buildAdminClaims,
  buildClaims,
  callRoomName,
  canPublishIn,
  enforcementRequest,
  type EnforcementState,
  type LiveKitConfig,
  liveKitHttpUrl,
  parseCallId,
  parseChannelId,
  parseEnforceRequest,
  publishSourcesFor,
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
  full?: boolean;
  server_mute?: boolean;
  server_deaf?: boolean;
  /// "voice" or "stage".
  kind?: string;
  stage_speaker?: boolean;
}

/// Calls LiveKit's RoomService; a participant who already left is fine.
async function enforce(
  config: LiveKitConfig,
  state: EnforcementState,
): Promise<Response> {
  const request = enforcementRequest(state);
  const token = await signJwt(
    buildAdminClaims({
      apiKey: config.apiKey,
      room: state.channel_id,
      nowSeconds: Math.floor(Date.now() / 1000),
    }),
    config.apiSecret,
  );
  const response = await fetch(
    `${liveKitHttpUrl(config.url)}/twirp/livekit.RoomService/${request.method}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(request.body),
    },
  );
  await response.body?.cancel();
  if (!response.ok && response.status !== 404) {
    return json({ error: "enforce_failed", status: response.status }, 502);
  }
  return json({ ok: true, action: request.method });
}

interface CallAccess {
  call_id: string;
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

  const enforceRequest = parseEnforceRequest(body);
  if (enforceRequest) {
    const { data: state, error: stateError } = await userClient.rpc(
      "voice_enforcement_state",
      {
        target_channel_id: enforceRequest.channelId,
        target_user_id: enforceRequest.userId,
      },
    );
    if (stateError) {
      return json({ error: "lookup_failed" }, 500);
    }
    if (!state) {
      return json({ error: "forbidden" }, 403);
    }
    const enforceConfig = readLiveKitConfig((name) => Deno.env.get(name));
    if (!enforceConfig) {
      return json({ error: "voice_not_configured" }, 503);
    }
    return await enforce(enforceConfig, state as EnforcementState);
  }

  const channelId = parseChannelId(body);
  const callId = channelId ? null : parseCallId(body);
  if (!channelId && !callId) {
    return json({ error: "invalid_channel" }, 400);
  }

  const { data: access, error: accessError } = channelId
    ? await userClient.rpc("can_current_user_connect_voice", {
      target_channel_id: channelId,
    })
    : await userClient.rpc("can_current_user_join_direct_call", {
      target_call_id: callId,
    });
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

  const voice = access as VoiceAccess | CallAccess;
  const channel = "channel_id" in voice ? voice : null;
  if (channel?.full) {
    return json({ error: "channel_full" }, 409);
  }
  const serverMute = channel?.server_mute === true;
  const serverDeaf = channel?.server_deaf === true;
  const stage = channel?.kind === "stage";
  const stageSpeaker = channel?.stage_speaker === true;
  // Who may turn captions on (E1) is decided here and written into the
  // signed token, where nobody in the room can fake it. A failed lookup just
  // means no.
  let captionsHost = false;
  {
    const { data: hosts, error: hostError } = await userClient.rpc(
      "can_current_user_host_captions",
      channel
        ? { target_channel_id: channel.channel_id }
        : { target_call_id: (voice as CallAccess).call_id },
    );
    captionsHost = !hostError && hosts === true;
  }
  const claims = buildClaims({
    apiKey: config.apiKey,
    identity: user.id,
    name: voice.display_name?.trim() || user.id,
    room: channel ? channel.channel_id : callRoomName(
      (voice as CallAccess).call_id,
    ),
    nowSeconds: Math.floor(Date.now() / 1000),
    publishSources: publishSourcesFor({ serverMute, serverDeaf }),
    canPublish: canPublishIn({ kind: channel?.kind, stageSpeaker }),
    captionsHost,
  });
  return json({
    url: config.url,
    token: await signJwt(claims, config.apiSecret),
    server_mute: serverMute,
    server_deaf: serverDeaf,
    stage,
    stage_speaker: stageSpeaker,
  });
});
