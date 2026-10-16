// Adds a sound to a circle's soundboard. Clients can't write to the
// circle-sounds bucket (202610160039): their measurement of a clip's
// length could be a lie, so the clip comes here, where its length is read
// from its bytes (audio_duration.ts) and anything over 5.2 seconds, too
// big or not a verifiable MP3, Ogg (Opus or Vorbis) or PCM WAV is refused.
// Then the clip is stored with the service role and create_circle_sound
// runs as the caller (manage_emojis, limits, audit) with the measured
// length; when it refuses, the clip is removed again.
//
//   POST /functions/v1/sound-upload   multipart/form-data:
//     circle_id, name, emoji (optional), file
//   → 200 the sound (as list_circle_sounds returns it), or
//     400 invalid_request | missing_file | malformed | too_long,
//     401, 403 forbidden, 409 name_taken | no_room, 413 too_large,
//     415 unsupported_format, 500.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  checkClip,
  maxSoundBytes,
  readUploadFields,
  refusalForRpcError,
} from "./request.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const bucket = "circle-sounds";

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

  // The form adds a little to the clip; refuse obviously big bodies early.
  const declared = Number(request.headers.get("Content-Length") ?? "0");
  if (declared > maxSoundBytes + 64 * 1024) {
    return json({ error: "too_large" }, 413);
  }
  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return json({ error: "invalid_request" }, 400);
  }
  const fields = readUploadFields({
    circle_id: form.get("circle_id"),
    name: form.get("name"),
    emoji: form.get("emoji"),
  });
  if (!fields.ok) {
    return json({ error: fields.error }, fields.status);
  }
  const file = form.get("file");
  if (!(file instanceof File)) {
    return json({ error: "missing_file" }, 400);
  }
  if (file.size > maxSoundBytes) {
    return json({ error: "too_large" }, 413);
  }
  const bytes = new Uint8Array(await file.arrayBuffer());
  const clip = checkClip(bytes);
  if (!clip.ok) {
    return json({ error: clip.error }, clip.status);
  }

  // Before storing anything: only members who manage emoji add sounds
  // (create_circle_sound checks again).
  const { data: allowed, error: permissionError } = await userClient.rpc(
    "current_user_has_circle_permission",
    { target_circle_id: fields.circleId, permission_name: "manage_emojis" },
  );
  if (permissionError) {
    return json({ error: "lookup_failed" }, 500);
  }
  if (allowed !== true) {
    return json({ error: "forbidden" }, 403);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const path = `${fields.circleId}/${crypto.randomUUID()}.${clip.extension}`;
  const { error: uploadError } = await admin.storage.from(bucket).upload(
    path,
    bytes,
    { contentType: clip.mimeType, upsert: false },
  );
  if (uploadError) {
    return json({ error: "upload_failed" }, 500);
  }

  const { data: sound, error: rpcError } = await userClient.rpc(
    "create_circle_sound",
    {
      target_circle_id: fields.circleId,
      sound_name: fields.name,
      sound_emoji: fields.emoji,
      storage_path: path,
      mime_type: clip.mimeType,
      duration_ms: clip.durationMs,
    },
  );
  if (rpcError) {
    // The clip is useless without its row.
    await admin.storage.from(bucket).remove([path]);
    const refusal = refusalForRpcError(rpcError.code);
    return json(
      { error: refusal.error, message: rpcError.message },
      refusal.status,
    );
  }
  return json(sound);
});
