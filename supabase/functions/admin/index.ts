// Admin console actions that need the service role (K1).
//
// POST {action, ...} with a signed-in admin's token:
//   suspend_user    {user_id, reason, until?, report_id?}
//                   The admin_suspend_user RPC runs as the caller (it checks
//                   is_app_admin(), the role, writes the audit log and closes
//                   the report), then the account is banned in Auth
//                   (auth.admin.updateUserById({ban_duration})) and every
//                   session of it is deleted, so a signed-in device stops
//                   working at its next refresh.
//   unsuspend_user  {user_id, reason?}  Lifts both.
//   attachment_url  {report_id}  A 5-minute link to the picture of the
//                   reported post, taken from the report's snapshot.
// Keep verify_jwt = true (supabase/config.toml): the function checks the
// caller is an admin again, in the database, before doing anything.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, handleAdminRequest } from "./handler.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "not_configured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  const authorization = request.headers.get("Authorization") ?? "";
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const service = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return await handleAdminRequest(request, {
    authenticate: async (header) => {
      const { data, error } = await userClient.auth.getUser(
        header.replace(/^Bearer\s+/i, ""),
      );
      return error || !data?.user ? null : data.user.id;
    },
    callRpc: async (name, args) => {
      const { data, error } = await userClient.rpc(name, args ?? {});
      return { data, error };
    },
    setBan: async (userId, banDuration) => {
      const { error } = await service.auth.admin.updateUserById(userId, {
        ban_duration: banDuration,
      });
      return error ? error.message : null;
    },
    revokeSessions: async (userId) => {
      const { data, error } = await service.rpc("delete_all_user_sessions", {
        owner_id: userId,
      });
      return {
        count: typeof data === "number" ? data : 0,
        error: error ? error.message : null,
      };
    },
    signedUrl: async (bucket, path, seconds) => {
      const { data, error } = await service.storage.from(bucket)
        .createSignedUrl(path, seconds);
      return error || !data ? null : data.signedUrl;
    },
    now: () => new Date(),
  });
});
