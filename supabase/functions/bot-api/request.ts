// Pure helpers of the bot-api function: the Authorization header, routing,
// body validation and mapping database errors to HTTP statuses.

export const MAX_BODY_BYTES = 32 * 1024;
export const MAX_CONTENT_LENGTH = 2000;
export const MAX_COMMANDS = 25;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// 32 random bytes as base64url without padding, like webhook tokens.
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

const COMMAND_NAME_PATTERN = /^[a-z0-9_-]{1,32}$/;

/// The token of an `Authorization: Bot <token>` header, or null.
export function parseBotAuthorization(header: string | null): string | null {
  const match = /^Bot\s+(\S+)\s*$/i.exec(header ?? "");
  if (!match || !TOKEN_PATTERN.test(match[1])) {
    return null;
  }
  return match[1];
}

export type Route =
  | { name: "me" }
  | { name: "channels" }
  | {
    name: "list_messages";
    channelId: string;
    limit: number;
    before: string | null;
  }
  | { name: "send_message"; channelId: string }
  | { name: "add_reaction"; messageId: string; emoji: string }
  | { name: "edit_message"; messageId: string }
  | { name: "list_commands" }
  | { name: "set_commands" }
  | { name: "poll_interactions"; limit: number }
  | { name: "respond_interaction"; interactionId: string };

export type RouteResult =
  | { ok: true; route: Route }
  | { ok: false; status: 400 | 404 | 405; error: string };

/// Matches a request to an endpoint. Paths are read after the last
/// `bot-api` segment, so `/functions/v1/bot-api/...` and `/bot-api/...`
/// both work.
export function matchRoute(method: string, url: URL): RouteResult {
  const all = url.pathname.split("/").filter((part) => part !== "");
  const start = all.lastIndexOf("bot-api");
  if (start === -1) {
    return { ok: false, status: 404, error: "unknown_endpoint" };
  }
  const parts: string[] = [];
  for (const part of all.slice(start + 1)) {
    const decoded = decodeSegment(part);
    if (decoded === null) {
      return { ok: false, status: 404, error: "unknown_endpoint" };
    }
    parts.push(decoded);
  }
  const verb = method.toUpperCase();
  const wrongMethod = {
    ok: false,
    status: 405,
    error: "method_not_allowed",
  } as const;
  const notFound = {
    ok: false,
    status: 404,
    error: "unknown_endpoint",
  } as const;

  const [first, second, third, fourth] = parts;
  switch (first) {
    case "me":
      if (parts.length !== 1) return notFound;
      return verb === "GET" ? { ok: true, route: { name: "me" } } : wrongMethod;
    case "channels": {
      if (parts.length === 1) {
        return verb === "GET"
          ? { ok: true, route: { name: "channels" } }
          : wrongMethod;
      }
      if (parts.length !== 3 || third !== "messages") return notFound;
      if (!UUID_PATTERN.test(second)) return notFound;
      const channelId = second.toLowerCase();
      if (verb === "POST") {
        return { ok: true, route: { name: "send_message", channelId } };
      }
      if (verb !== "GET") return wrongMethod;
      const limit = parseLimit(url.searchParams.get("limit"), 50, 100);
      if (limit === null) {
        return { ok: false, status: 400, error: "invalid_limit" };
      }
      const before = url.searchParams.get("before");
      if (before !== null && Number.isNaN(Date.parse(before))) {
        return { ok: false, status: 400, error: "invalid_before" };
      }
      return {
        ok: true,
        route: { name: "list_messages", channelId, limit, before },
      };
    }
    case "messages": {
      // PATCH /messages/{id}: change the bot's own message (text, components).
      if (parts.length === 2) {
        if (!UUID_PATTERN.test(second)) return notFound;
        if (verb !== "PATCH") return wrongMethod;
        return {
          ok: true,
          route: { name: "edit_message", messageId: second.toLowerCase() },
        };
      }
      if (parts.length !== 4 || third !== "reactions") return notFound;
      if (!UUID_PATTERN.test(second)) return notFound;
      if (verb !== "PUT") return wrongMethod;
      const emoji = fourth.trim();
      if ([...emoji].length < 1 || emoji.length > 64) {
        return { ok: false, status: 400, error: "invalid_emoji" };
      }
      return {
        ok: true,
        route: { name: "add_reaction", messageId: second.toLowerCase(), emoji },
      };
    }
    case "commands":
      if (parts.length !== 1) return notFound;
      if (verb === "GET") return { ok: true, route: { name: "list_commands" } };
      if (verb === "PUT") return { ok: true, route: { name: "set_commands" } };
      return wrongMethod;
    case "interactions": {
      if (parts.length === 1) {
        if (verb !== "GET") return wrongMethod;
        const limit = parseLimit(url.searchParams.get("limit"), 25, 100);
        if (limit === null) {
          return { ok: false, status: 400, error: "invalid_limit" };
        }
        return { ok: true, route: { name: "poll_interactions", limit } };
      }
      if (parts.length !== 3 || third !== "respond") return notFound;
      if (!UUID_PATTERN.test(second)) return notFound;
      if (verb !== "POST") return wrongMethod;
      return {
        ok: true,
        route: {
          name: "respond_interaction",
          interactionId: second.toLowerCase(),
        },
      };
    }
    default:
      return notFound;
  }
}

function decodeSegment(segment: string): string | null {
  try {
    return decodeURIComponent(segment);
  } catch {
    return null;
  }
}

/// A whole number between 1 and [max]; [fallback] when absent, null when
/// malformed.
export function parseLimit(
  value: string | null,
  fallback: number,
  max: number,
): number | null {
  if (value === null || value === "") {
    return fallback;
  }
  if (!/^\d+$/.test(value)) {
    return null;
  }
  const limit = Number(value);
  return limit >= 1 && limit <= max ? limit : null;
}

/// Whether a Content-Type header names JSON (parameters allowed).
export function isJsonContentType(contentType: string | null): boolean {
  if (!contentType) {
    return false;
  }
  const mediaType = contentType.split(";")[0].trim().toLowerCase();
  return mediaType === "application/json" || mediaType.endsWith("+json");
}

export type MessageBody = {
  content: string;
  replyTo: string | null;
  /** The components as sent, when the request has any; the database checks them. */
  components?: unknown[];
};

/// The `components` of a body: absent, null or an empty list mean none; a
/// list is passed on (the database function checks every part of it).
function readComponents(
  record: Record<string, unknown>,
): { ok: true; components: unknown[] | null } | { ok: false; error: string } {
  const value = record.components;
  if (value === undefined || value === null) {
    return { ok: true, components: null };
  }
  if (!Array.isArray(value)) {
    return { ok: false, error: "components_must_be_array" };
  }
  return { ok: true, components: value.length === 0 ? null : value };
}

/// Validates `{content, reply_to?, components?}` (content: 1 to 2000
/// characters).
export function validateMessageBody(
  body: unknown,
): { ok: true; value: MessageBody } | { ok: false; error: string } {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, error: "body_must_be_object" };
  }
  const record = body as Record<string, unknown>;
  if (typeof record.content !== "string" || record.content.trim() === "") {
    return { ok: false, error: "content_required" };
  }
  const content = record.content.trim();
  if ([...content].length > MAX_CONTENT_LENGTH) {
    return { ok: false, error: "content_too_long" };
  }
  let replyTo: string | null = null;
  if (record.reply_to !== undefined && record.reply_to !== null) {
    if (
      typeof record.reply_to !== "string" || !UUID_PATTERN.test(record.reply_to)
    ) {
      return { ok: false, error: "invalid_reply_to" };
    }
    replyTo = record.reply_to.toLowerCase();
  }
  const components = readComponents(record);
  if (!components.ok) {
    return components;
  }
  return {
    ok: true,
    value: {
      content,
      replyTo,
      ...(components.components ? { components: components.components } : {}),
    },
  };
}

export type EditBody = {
  /** The new text, or null to leave it. */
  content: string | null;
  /** Whether the components are to be replaced (null then removes them). */
  changeComponents: boolean;
  components: unknown[] | null;
};

/// Validates `{content?, components?}` for editing a bot's own message: at
/// least one of them; `components: null` or `[]` removes the components.
export function validateEditBody(
  body: unknown,
): { ok: true; value: EditBody } | { ok: false; error: string } {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, error: "body_must_be_object" };
  }
  const record = body as Record<string, unknown>;
  let content: string | null = null;
  if (record.content !== undefined && record.content !== null) {
    if (typeof record.content !== "string" || record.content.trim() === "") {
      return { ok: false, error: "content_required" };
    }
    content = record.content.trim();
    if ([...content].length > MAX_CONTENT_LENGTH) {
      return { ok: false, error: "content_too_long" };
    }
  }
  const changeComponents = "components" in record;
  const components = readComponents(record);
  if (!components.ok) {
    return components;
  }
  if (content === null && !changeComponents) {
    return { ok: false, error: "nothing_to_change" };
  }
  return {
    ok: true,
    value: { content, changeComponents, components: components.components },
  };
}

export type RespondType = "message" | "ephemeral" | "update" | "ack";

export type RespondBody = {
  type: RespondType;
  /** What goes to the database function (only the keys the bot sent). */
  response: Record<string, unknown>;
};

const RESPOND_TYPES: readonly string[] = [
  "message",
  "ephemeral",
  "update",
  "ack",
];

/// Validates the answer to an interaction: `{content}` (as before: a
/// message) or `{type: message|ephemeral|update|ack, content?, components?}`.
export function validateRespondBody(
  body: unknown,
): { ok: true; value: RespondBody } | { ok: false; error: string } {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, error: "body_must_be_object" };
  }
  const record = body as Record<string, unknown>;
  const type = record.type === undefined ? "message" : record.type;
  if (typeof type !== "string" || !RESPOND_TYPES.includes(type)) {
    return { ok: false, error: "invalid_type" };
  }
  const response: Record<string, unknown> = { type };
  if (record.content !== undefined && record.content !== null) {
    if (typeof record.content !== "string" || record.content.trim() === "") {
      return { ok: false, error: "content_required" };
    }
    const content = record.content.trim();
    if ([...content].length > MAX_CONTENT_LENGTH) {
      return { ok: false, error: "content_too_long" };
    }
    response.content = content;
  }
  if ("components" in record) {
    const components = readComponents(record);
    if (!components.ok) {
      return components;
    }
    response.components = components.components;
  }
  const hasContent = "content" in response;
  const hasComponents = "components" in response;
  if ((type === "message" || type === "ephemeral") && !hasContent) {
    return { ok: false, error: "content_required" };
  }
  if (type === "update" && !hasContent && !hasComponents) {
    return { ok: false, error: "nothing_to_change" };
  }
  if (type === "ack" && (hasContent || hasComponents)) {
    return { ok: false, error: "ack_has_no_content" };
  }
  return { ok: true, value: { type: type as RespondType, response } };
}

export type CommandDefinition = { name: string; description: string };

/// Validates `[{name, description}]` or `{commands: [...]}`: at most 25,
/// names of a-z, 0-9, `_` and `-` (up to 32, unique), descriptions of 1 to
/// 100 characters.
export function validateCommands(
  body: unknown,
): { ok: true; value: CommandDefinition[] } | { ok: false; error: string } {
  const list = Array.isArray(body)
    ? body
    : typeof body === "object" && body !== null &&
        Array.isArray((body as Record<string, unknown>).commands)
    ? (body as Record<string, unknown>).commands as unknown[]
    : null;
  if (list === null) {
    return { ok: false, error: "commands_must_be_array" };
  }
  if (list.length > MAX_COMMANDS) {
    return { ok: false, error: "too_many_commands" };
  }
  const seen = new Set<string>();
  const value: CommandDefinition[] = [];
  for (const item of list) {
    if (typeof item !== "object" || item === null || Array.isArray(item)) {
      return { ok: false, error: "invalid_command" };
    }
    const record = item as Record<string, unknown>;
    const name = typeof record.name === "string" ? record.name.trim() : "";
    const description = typeof record.description === "string"
      ? record.description.trim()
      : "";
    if (!COMMAND_NAME_PATTERN.test(name)) {
      return { ok: false, error: "invalid_command_name" };
    }
    if ([...description].length < 1 || [...description].length > 100) {
      return { ok: false, error: "invalid_command_description" };
    }
    if (seen.has(name)) {
      return { ok: false, error: "duplicate_command" };
    }
    seen.add(name);
    value.push({ name, description });
  }
  return { ok: true, value };
}

/// The HTTP status and error name for a database error code.
export function statusForRpcError(
  code: string | undefined,
): { status: number; error: string } {
  switch (code) {
    case "28000":
      return { status: 401, error: "invalid_token" };
    case "42501":
      return { status: 403, error: "forbidden" };
    case "P0002":
      return { status: 404, error: "not_found" };
    case "22023":
    case "22P02":
    case "54000":
      return { status: 400, error: "invalid_request" };
    case "23505":
      return { status: 409, error: "conflict" };
    case "BT429":
      return { status: 429, error: "rate_limited" };
    case "P0001":
      // Raised for slowmode by the send trigger.
      return { status: 429, error: "slowmode" };
    default:
      return { status: 500, error: "internal_error" };
  }
}
