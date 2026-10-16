// Creates and deletes circle bots.
//
// Creating: the login comes from the Auth admin API (service role):
// banned, with a placeholder address and a random password, so it can
// never sign in. Then create_circle_bot runs as the caller, checking their
// circle permissions and turning that login into the bot; when it refuses,
// the login is deleted again.
//
// Deleting: delete_circle_bot runs as the caller (manage_circle), which
// removes the bot from its circle; then its login is deleted with the
// service role, since SQL may not delete auth.users on hosted projects.
// The profile stays (it no longer cascades from auth.users,
// 202610140005), so the bot's messages keep their author.
//
//   POST   /functions/v1/bots  {"circle_id", "name", "role_id"?}
//   → 200 the bot with its token (shown once), or 400/401/403/500.
//   POST   /functions/v1/bots  {"action": "delete", "bot_id"}
//   DELETE /functions/v1/bots  {"bot_id"}  (or ?bot_id=)
//   → 200 {"deleted": true, "login_deleted": bool}, or 400/401/403/500.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isBotLogin, parseBotsRequest, statusForRpcError } from "./request.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, DELETE, OPTIONS",
};

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
  if (request.method !== "POST" && request.method !== "DELETE") {
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

  let body: unknown = null;
  try {
    const text = await request.text();
    body = text.trim() === "" ? null : JSON.parse(text);
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const parsed = parseBotsRequest(
    request.method,
    body,
    new URL(request.url).searchParams,
  );
  if (!parsed.ok) {
    return json({ error: parsed.error }, parsed.status);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (parsed.action === "delete") {
    // Looked up first: once deleted, nothing says which login was the
    // bot's. The caller can't read circle_bots, so the service role does.
    const { data: botRow } = await admin
      .from("circle_bots")
      .select("user_id")
      .eq("id", parsed.botId)
      .maybeSingle();

    const { error: rpcError } = await userClient.rpc("delete_circle_bot", {
      target_bot_id: parsed.botId,
    });
    if (rpcError) {
      return json(
        { error: rpcError.message, code: rpcError.code },
        statusForRpcError(rpcError.code),
      );
    }

    let loginDeleted = false;
    const botUserId = botRow?.user_id as string | undefined;
    if (botUserId) {
      const { data: login } = await admin.auth.admin.getUserById(botUserId);
      if (isBotLogin(login?.user)) {
        const { error: deleteError } = await admin.auth.admin.deleteUser(
          botUserId,
        );
        loginDeleted = !deleteError;
        if (deleteError) {
          console.error("bot login not deleted", botUserId, deleteError);
        }
      }
    }
    return json({ deleted: true, login_deleted: loginDeleted });
  }

  const { circleId, name, roleId } = parsed;
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
    // 404 isn't something creation can mean; keep 500 for it.
    const status = statusForRpcError(rpcError.code);
    return json(
      { error: rpcError.message, code: rpcError.code },
      status === 404 ? 500 : status,
    );
  }
  return json(bot);
});
