// Creates a circle bot. The login comes from the Auth admin API (service
// role): banned, with a placeholder address and a random password, so it
// can never sign in. Then create_circle_bot runs as the caller, checking
// their circle permissions and turning that login into the bot; when it
// refuses, the login is deleted again.
//
//   POST /functions/v1/bots  {"circle_id", "name", "role_id"?}
//   → 200 the bot with its token (shown once), or 400/401/403/500.
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

function randomPassword(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
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

  let body: Record<string, unknown>;
  try {
    const parsed = await request.json();
    if (typeof parsed !== "object" || parsed === null) throw new Error();
    body = parsed as Record<string, unknown>;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const circleId = body.circle_id;
  const name = typeof body.name === "string" ? body.name.trim() : "";
  const roleId = body.role_id ?? null;
  if (
    typeof circleId !== "string" || !uuidPattern.test(circleId) ||
    name.length < 1 || name.length > 32 ||
    (roleId !== null &&
      (typeof roleId !== "string" || !uuidPattern.test(roleId)))
  ) {
    return json({ error: "invalid_request" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const botEmail = `bot-${crypto.randomUUID()}@bots.wecord.invalid`;
  const { data: created, error: createError } = await admin.auth.admin
    .createUser({
      email: botEmail,
      password: randomPassword(),
      email_confirm: true,
      ban_duration: "876000h",
      app_metadata: { provider: "bot", providers: ["bot"] },
      user_metadata: { bot: true, display_name: name },
    });
  const botUserId = created?.user?.id;
  if (createError || !botUserId) {
    return json({ error: "account_failed" }, 500);
  }

  const { data: bot, error: rpcError } = await userClient.rpc(
    "create_circle_bot",
    {
      target_circle_id: circleId,
      bot_name: name,
      target_role_id: roleId,
      bot_user_id: botUserId,
    },
  );
  if (rpcError) {
    await admin.auth.admin.deleteUser(botUserId);
    const status = rpcError.code === "42501"
      ? 403
      : rpcError.code === "22023" || rpcError.code === "54000"
      ? 400
      : 500;
    return json({ error: rpcError.message, code: rpcError.code }, status);
  }
  return json(bot);
});
