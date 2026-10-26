// Gets a signed-in person past a lost authenticator app with one of their
// recovery codes (roadmap G4).
//
// POST {code} with the token of a session that has passed the password (aal1)
// and whose account has two-step verification on:
//   1. the account must have a verified authenticator (Auth Admin API);
//   2. consume_mfa_recovery_code (service role) checks the code against the
//      salted hashes, counts a wrong one, locks after five wrong ones for 30
//      minutes and uses a right one up;
//   3. every authenticator factor of the account is removed with the Auth
//      Admin API, so the session can reach aal2 without a code (two-step
//      verification is off until the person turns it on again);
//   4. finish_mfa_recovery records it in the security record (the person's
//      devices get a push) and erases the other codes. If removing the
//      authenticator failed, the code is given back.
//
// Responses: 200 {recovered: true, remaining}; 400 bad_request / invalid_code
// {attempts_left} / no_codes; 401 unauthorized; 409 not_enabled; 429 locked
// {retry_after_seconds}; 500 on a failure of ours. The code is never logged.

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export interface RpcResult {
  data: unknown;
  error: { message: string } | null;
}

export interface FactorList {
  /** Verified authenticator factors. */
  verified: string[];
  /** Authenticator factors that were never confirmed. */
  unverified: string[];
  error: string | null;
}

export interface RecoveryDeps {
  /** The user id of the bearer token, or null. */
  authenticate: (authorization: string) => Promise<string | null>;
  listFactors: (userId: string) => Promise<FactorList>;
  consume: (userId: string, code: string) => Promise<RpcResult>;
  deleteFactor: (userId: string, factorId: string) => Promise<string | null>;
  finish: (
    userId: string,
    codeId: string,
    succeeded: boolean,
    codesLeft: number,
  ) => Promise<string | null>;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The longest text taken as a code: a code is 10 characters and a dash. */
export const maxCodeLength = 40;

export async function handleRecovery(
  request: Request,
  deps: RecoveryDeps,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  if (!/^Bearer\s+\S+/i.test(authorization)) {
    return json({ error: "unauthorized" }, 401);
  }
  const userId = await deps.authenticate(authorization);
  if (!userId) {
    return json({ error: "unauthorized" }, 401);
  }

  let code: unknown;
  try {
    code = (await request.json())?.code;
  } catch (_) {
    return json({ error: "bad_request" }, 400);
  }
  if (
    typeof code !== "string" || code.trim() === "" ||
    code.length > maxCodeLength
  ) {
    return json({ error: "bad_request" }, 400);
  }

  const factors = await deps.listFactors(userId);
  if (factors.error) {
    console.error("mfa-recovery: listing factors failed");
    return json({ error: "recovery_failed" }, 500);
  }
  if (factors.verified.length === 0) {
    // Nothing to recover from; no code is tried.
    return json({ error: "not_enabled" }, 409);
  }

  const consumed = await deps.consume(userId, code);
  if (consumed.error) {
    console.error("mfa-recovery: consume failed", consumed.error.message);
    return json({ error: "recovery_failed" }, 500);
  }
  const result = (consumed.data ?? {}) as Record<string, unknown>;
  if (result.ok !== true) {
    switch (result.reason) {
      case "locked":
        return json({
          error: "locked",
          retry_after_seconds: Number(result.retry_after_seconds) || 1800,
        }, 429);
      case "no_codes":
        return json({ error: "no_codes" }, 400);
      case "invalid":
        return json({
          error: "invalid_code",
          attempts_left: Number(result.attempts_left) || 0,
        }, 400);
      default:
        return json({ error: "recovery_failed" }, 500);
    }
  }
  const codeId = result.code_id;
  if (typeof codeId !== "string" || !uuidPattern.test(codeId)) {
    return json({ error: "recovery_failed" }, 500);
  }
  const remaining = Number(result.remaining) || 0;

  // The code is used up; now turn the authenticator off. A verified factor
  // that cannot be removed gives the code back so the person can try again.
  for (const factorId of factors.verified) {
    const failed = await deps.deleteFactor(userId, factorId);
    if (failed) {
      console.error("mfa-recovery: removing a factor failed");
      await deps.finish(userId, codeId, false, remaining);
      return json({ error: "recovery_failed" }, 500);
    }
  }
  // Unfinished set-ups go too; failing here changes nothing for the login.
  for (const factorId of factors.unverified) {
    await deps.deleteFactor(userId, factorId);
  }

  const finishing = await deps.finish(userId, codeId, true, remaining);
  if (finishing) {
    // The authenticator is already off; the record is the only thing missed.
    console.error("mfa-recovery: recording the recovery failed");
  }
  return json({ recovered: true, remaining });
}
