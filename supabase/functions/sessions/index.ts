// Signs one of the caller's devices out.
//
// POST {session_id} ends that session: the caller must own it (it has to
// be in list_my_sessions, which runs as the caller and lists only their
// own) and it must not be the one making the call (that is "Sign out").
// The session row is then deleted with the service role through
// delete_user_session; the device's refresh token dies with it, and its
// access token stops working when it expires. 404 session_not_found when it
// is not theirs or already gone.
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

interface SessionRow {
  session_id?: unknown;
  is_current?: unknown;
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
  const user = userData?.user;
  if (userError || !user) {
    return json({ error: "unauthorized" }, 401);
  }

  let sessionId: unknown;
  try {
    sessionId = (await request.json())?.session_id;
  } catch (_) {
    return json({ error: "bad_request" }, 400);
  }
  if (typeof sessionId !== "string" || !uuidPattern.test(sessionId)) {
    return json({ error: "bad_request" }, 400);
  }

  // As the caller: only their own sessions are listed.
  const { data: sessions, error: listError } = await userClient.rpc(
    "list_my_sessions",
  );
  if (listError) {
    return json({ error: "list_failed" }, 500);
  }
  const target = ((sessions ?? []) as SessionRow[]).find(
    (row) => row.session_id === sessionId,
  );
  if (!target) {
    return json({ error: "session_not_found" }, 404);
  }
  if (target.is_current === true) {
    return json({ error: "current_session" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: removed, error: removeError } = await admin.rpc(
    "delete_user_session",
    { target_session_id: sessionId, owner_id: user.id },
  );
  if (removeError) {
    return json({ error: "revoke_failed" }, 500);
  }
  if (removed !== true) {
    return json({ error: "session_not_found" }, 404);
  }
  return json({ revoked: true });
});
