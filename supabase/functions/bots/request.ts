// Request parsing for the `bots` Edge Function, kept apart from
// Deno.serve so it can be tested.

export const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type BotsRequest =
  | {
    ok: true;
    action: "create";
    circleId: string;
    name: string;
    roleId: string | null;
  }
  | { ok: true; action: "delete"; botId: string }
  | { ok: false; status: number; error: string };

/// Reads what the caller asked for. POST with {circle_id, name, role_id?}
/// creates a bot; POST with {action: "delete", bot_id} or DELETE with
/// {bot_id} (or ?bot_id=) deletes one.
export function parseBotsRequest(
  method: string,
  body: unknown,
  query: URLSearchParams = new URLSearchParams(),
): BotsRequest {
  if (method !== "POST" && method !== "DELETE") {
    return { ok: false, status: 405, error: "method_not_allowed" };
  }
  const fields =
    typeof body === "object" && body !== null && !Array.isArray(body)
      ? body as Record<string, unknown>
      : null;
  if (fields === null && !(method === "DELETE" && query.has("bot_id"))) {
    return { ok: false, status: 400, error: "invalid_json" };
  }

  const action = fields?.action ?? (method === "DELETE" ? "delete" : "create");
  if (method === "DELETE" && action !== "delete") {
    return { ok: false, status: 400, error: "invalid_request" };
  }

  if (action === "delete") {
    const botId = fields?.bot_id ?? query.get("bot_id");
    if (typeof botId !== "string" || !uuidPattern.test(botId)) {
      return { ok: false, status: 400, error: "invalid_request" };
    }
    return { ok: true, action: "delete", botId: botId.toLowerCase() };
  }

  if (action !== "create") {
    return { ok: false, status: 400, error: "invalid_request" };
  }
  const circleId = fields?.circle_id;
  const name = typeof fields?.name === "string" ? fields.name.trim() : "";
  const roleId = fields?.role_id ?? null;
  if (
    typeof circleId !== "string" || !uuidPattern.test(circleId) ||
    name.length < 1 || name.length > 32 ||
    (roleId !== null &&
      (typeof roleId !== "string" || !uuidPattern.test(roleId)))
  ) {
    return { ok: false, status: 400, error: "invalid_request" };
  }
  return {
    ok: true,
    action: "create",
    circleId,
    name,
    roleId: roleId as string | null,
  };
}

/// The HTTP status for an error from create_circle_bot / delete_circle_bot.
export function statusForRpcError(code: string | undefined): number {
  switch (code) {
    case "42501":
      return 403;
    case "22023":
    case "54000":
      return 400;
    case "P0002":
      return 404;
    default:
      return 500;
  }
}

/// Whether an auth user is a bot login the `bots` function made: provider
/// 'bot' in its app metadata, which only the service role can set. Only
/// those are ever deleted here.
export function isBotLogin(
  user: { app_metadata?: Record<string, unknown> } | null | undefined,
): boolean {
  return user?.app_metadata?.provider === "bot";
}
