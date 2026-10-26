// Uses a two-step recovery code to turn two-step verification off after the
// authenticator app was lost (G4). See handler.ts for the whole flow.
// Keep verify_jwt = true (supabase/config.toml): the function also checks
// the token itself and acts only on that person's account.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, handleRecovery } from "./handler.ts";

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
  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const service = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return await handleRecovery(request, {
    authenticate: async (authorization) => {
      const { data, error } = await userClient.auth.getUser(
        authorization.replace(/^Bearer\s+/i, ""),
      );
      return error || !data?.user ? null : data.user.id;
    },
    listFactors: async (userId) => {
      const { data, error } = await service.auth.admin.mfa.listFactors({
        userId,
      });
      if (error || !data) {
        return {
          verified: [],
          unverified: [],
          error: error?.message ?? "none",
        };
      }
      const totp = data.factors.filter((factor) =>
        factor.factor_type === "totp"
      );
      return {
        verified: totp.filter((factor) => factor.status === "verified")
          .map((factor) => factor.id),
        unverified: totp.filter((factor) => factor.status !== "verified")
          .map((factor) => factor.id),
        error: null,
      };
    },
    consume: async (userId, code) => {
      const { data, error } = await service.rpc("consume_mfa_recovery_code", {
        target_user_id: userId,
        submitted_code: code,
      });
      return { data, error };
    },
    deleteFactor: async (userId, factorId) => {
      const { error } = await service.auth.admin.mfa.deleteFactor({
        id: factorId,
        userId,
      });
      return error ? error.message : null;
    },
    finish: async (userId, codeId, succeeded, codesLeft) => {
      const { error } = await service.rpc("finish_mfa_recovery", {
        target_user_id: userId,
        used_code_id: codeId,
        succeeded,
        codes_left: codesLeft,
      });
      return error ? error.message : null;
    },
  });
});
