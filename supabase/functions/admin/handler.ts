// The admin function's request handling with everything it touches passed
// in, so the checks and the error mapping can be tested without a network
// or a database. index.ts wires the real thing.
//
// What needs the service role is done here, after the database has agreed:
//   suspend_user    {user_id, reason, until?, report_id?}
//   unsuspend_user  {user_id, reason?}
//   attachment_url  {report_id}
// The database half of a suspension is the admin_suspend_user RPC, called as
// the caller (it checks is_app_admin() and the role, writes the audit log
// and closes the report); only then is the account banned in Auth and its
// sessions ended. attachment_url signs a short link to the picture of a
// reported post, so an admin can see what was reported, and nothing else.

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/// GoTrue takes the ban as a duration. A hundred years is "for good".
export const PERMANENT_BAN = "876000h";
const MAX_REASON = 500;
const SIGNED_URL_SECONDS = 300;
/// The buckets a circle post's picture can be in.
const POST_BUCKETS = ["chat-media", "chat-images"];

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface RpcResult {
  data: unknown;
  error: { code?: string; message?: string } | null;
}

export interface AdminDeps {
  /// The signed-in user of the Authorization header, or null.
  authenticate(authorization: string): Promise<string | null>;
  /// An RPC called as the caller (their token, so auth.uid() is theirs).
  callRpc(name: string, args?: Record<string, unknown>): Promise<RpcResult>;
  /// Bans (a duration like "72h") or unbans ("none") the Auth user.
  setBan(userId: string, banDuration: string): Promise<string | null>;
  /// Ends every session of the user (service role). Returns the count.
  revokeSessions(
    userId: string,
  ): Promise<{ count: number; error: string | null }>;
  /// A link to a private file, or null.
  signedUrl(
    bucket: string,
    path: string,
    seconds: number,
  ): Promise<string | null>;
  now(): Date;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/// The status an RPC error maps to.
export function rpcErrorResponse(error: RpcResult["error"]): Response {
  switch (error?.code) {
    case "42501":
      return json({ error: "forbidden", message: error?.message }, 403);
    case "22023":
      return json({ error: "bad_request", message: error?.message }, 400);
    case "P0002":
      return json({ error: "not_found", message: error?.message }, 404);
    default:
      return json({ error: "rpc_failed" }, 500);
  }
}

/// How long a ban lasts until [until] (null: for good), as GoTrue takes it.
export function banDuration(until: Date | null, now: Date): string {
  if (until === null) {
    return PERMANENT_BAN;
  }
  const hours = Math.ceil((until.getTime() - now.getTime()) / 3_600_000);
  return `${Math.max(hours, 1)}h`;
}

function cleanReason(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const reason = value.trim();
  return reason.length === 0 || reason.length > MAX_REASON ? null : reason;
}

export async function handleAdminRequest(
  request: Request,
  deps: AdminDeps,
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
  const callerId = await deps.authenticate(authorization);
  if (callerId === null) {
    return json({ error: "unauthorized" }, 401);
  }

  // The caller must be an admin; the RPCs check it again with the role.
  const roleResult = await deps.callRpc("admin_my_role");
  if (roleResult.error) {
    return json({ error: "rpc_failed" }, 500);
  }
  const role = roleResult.data;
  if (role !== "owner" && role !== "moderator" && role !== "support") {
    return json({ error: "forbidden" }, 403);
  }

  let body: Record<string, unknown>;
  try {
    const parsed = await request.json();
    if (
      parsed === null || typeof parsed !== "object" || Array.isArray(parsed)
    ) {
      return json({ error: "bad_request" }, 400);
    }
    body = parsed as Record<string, unknown>;
  } catch (_) {
    return json({ error: "bad_request" }, 400);
  }

  switch (body.action) {
    case "suspend_user":
      return await suspendUser(body, role, callerId, deps);
    case "unsuspend_user":
      return await unsuspendUser(body, role, deps);
    case "attachment_url":
      return await attachmentUrl(body, deps);
    default:
      return json({ error: "unknown_action" }, 400);
  }
}

async function suspendUser(
  body: Record<string, unknown>,
  role: string,
  callerId: string,
  deps: AdminDeps,
): Promise<Response> {
  if (role === "support") {
    return json({ error: "forbidden" }, 403);
  }
  const userId = body.user_id;
  if (typeof userId !== "string" || !uuidPattern.test(userId)) {
    return json({ error: "bad_request", message: "user_id" }, 400);
  }
  if (userId === callerId) {
    return json({ error: "forbidden", message: "yourself" }, 403);
  }
  const reason = cleanReason(body.reason);
  if (reason === null) {
    return json({ error: "bad_request", message: "reason" }, 400);
  }
  let until: Date | null = null;
  if (body.until !== undefined && body.until !== null) {
    if (typeof body.until !== "string") {
      return json({ error: "bad_request", message: "until" }, 400);
    }
    until = new Date(body.until);
    if (
      Number.isNaN(until.getTime()) || until.getTime() <= deps.now().getTime()
    ) {
      return json({ error: "bad_request", message: "until" }, 400);
    }
  }
  const reportId = body.report_id ?? null;
  if (
    reportId !== null &&
    (typeof reportId !== "string" || !uuidPattern.test(reportId))
  ) {
    return json({ error: "bad_request", message: "report_id" }, 400);
  }

  // The database first: it checks the role, refuses admins, and records it.
  const suspended = await deps.callRpc("admin_suspend_user", {
    target_user_id: userId,
    until: until?.toISOString() ?? null,
    reason,
    report_id: reportId,
  });
  if (suspended.error) {
    return rpcErrorResponse(suspended.error);
  }

  const banError = await deps.setBan(userId, banDuration(until, deps.now()));
  if (banError !== null) {
    // The suspension is in the database (so what the database checks is
    // enforced); sending the same request again retries the ban.
    return json({ error: "ban_failed", suspended: true }, 502);
  }
  const sessions = await deps.revokeSessions(userId);
  if (sessions.error !== null) {
    return json(
      { error: "sessions_failed", suspended: true, banned: true },
      502,
    );
  }
  return json({
    suspended: true,
    banned: true,
    sessions_revoked: sessions.count,
    until: until?.toISOString() ?? null,
  });
}

async function unsuspendUser(
  body: Record<string, unknown>,
  role: string,
  deps: AdminDeps,
): Promise<Response> {
  if (role === "support") {
    return json({ error: "forbidden" }, 403);
  }
  const userId = body.user_id;
  if (typeof userId !== "string" || !uuidPattern.test(userId)) {
    return json({ error: "bad_request", message: "user_id" }, 400);
  }
  const reason = typeof body.reason === "string"
    ? body.reason.trim().slice(0, MAX_REASON)
    : "";
  const lifted = await deps.callRpc("admin_unsuspend_user", {
    target_user_id: userId,
    reason,
  });
  if (lifted.error) {
    return rpcErrorResponse(lifted.error);
  }
  const banError = await deps.setBan(userId, "none");
  if (banError !== null) {
    return json({ error: "unban_failed", suspended: false }, 502);
  }
  return json({ suspended: false, banned: false });
}

async function attachmentUrl(
  body: Record<string, unknown>,
  deps: AdminDeps,
): Promise<Response> {
  const reportId = body.report_id;
  if (typeof reportId !== "string" || !uuidPattern.test(reportId)) {
    return json({ error: "bad_request", message: "report_id" }, 400);
  }
  // As the caller: the RPC checks the role. Only the picture that was in
  // the snapshot of the report can be opened this way.
  const detail = await deps.callRpc("admin_get_report", {
    target_report_id: reportId,
  });
  if (detail.error) {
    return rpcErrorResponse(detail.error);
  }
  const snapshot = (detail.data as { report?: { snapshot?: unknown } } | null)
    ?.report?.snapshot as Record<string, unknown> | undefined;
  const attachment = snapshot?.attachment as
    | Record<string, unknown>
    | null
    | undefined;
  const bucket = attachment?.bucket;
  const path = attachment?.path;
  if (
    typeof bucket !== "string" || typeof path !== "string" ||
    !POST_BUCKETS.includes(bucket) || path.includes("..")
  ) {
    return json({ error: "no_attachment" }, 404);
  }
  const url = await deps.signedUrl(bucket, path, SIGNED_URL_SECONDS);
  if (url === null) {
    return json({ error: "not_found" }, 404);
  }
  return json({ url, expires_in: SIGNED_URL_SECONDS });
}
