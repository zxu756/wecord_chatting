// Pure helpers of the webhook function: path parsing, body validation and
// mapping post_webhook_message errors to HTTP statuses.

export const MAX_BODY_BYTES = 16 * 1024;
export const MAX_CONTENT_LENGTH = 2000;
export const MAX_USERNAME_LENGTH = 80;
export const MAX_AVATAR_URL_LENGTH = 2048;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// 32 random bytes as base64url without padding.
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

export type PathResult =
  | { ok: true; id: string; token: string }
  | { ok: false; status: 401 | 404 };

/// Reads `/…/webhook/{id}/{token}` from a request path. Unknown shapes and
/// malformed ids are 404; malformed tokens are 401.
export function parseWebhookPath(pathname: string): PathResult {
  const parts = pathname.split("/").filter((part) => part !== "");
  const index = parts.lastIndexOf("webhook");
  if (index === -1 || parts.length !== index + 3) {
    return { ok: false, status: 404 };
  }
  const id = decodeSegment(parts[index + 1]);
  const token = decodeSegment(parts[index + 2]);
  if (id === null || !UUID_PATTERN.test(id)) {
    return { ok: false, status: 404 };
  }
  if (token === null || !TOKEN_PATTERN.test(token)) {
    return { ok: false, status: 401 };
  }
  return { ok: true, id: id.toLowerCase(), token };
}

function decodeSegment(segment: string): string | null {
  try {
    return decodeURIComponent(segment);
  } catch {
    return null;
  }
}

/// Whether a Content-Type header names JSON (parameters allowed).
export function isJsonContentType(contentType: string | null): boolean {
  if (!contentType) {
    return false;
  }
  const mediaType = contentType.split(";")[0].trim().toLowerCase();
  return mediaType === "application/json" || mediaType.endsWith("+json");
}

/// Whether a declared Content-Length is over the limit.
export function isDeclaredTooLarge(contentLength: string | null): boolean {
  if (contentLength === null) {
    return false;
  }
  const length = Number(contentLength);
  return Number.isFinite(length) && length > MAX_BODY_BYTES;
}

export interface WebhookPayload {
  content: string;
  username: string | null;
  avatarUrl: string | null;
}

export type PayloadResult =
  | { ok: true; payload: WebhookPayload }
  | { ok: false; error: string };

/// Validates a parsed JSON body `{content, username?, avatar_url?}`.
export function validatePayload(body: unknown): PayloadResult {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, error: "body_must_be_object" };
  }
  const record = body as Record<string, unknown>;
  if (typeof record.content !== "string") {
    return { ok: false, error: "content_required" };
  }
  const content = record.content.trim();
  if (content.length === 0) {
    return { ok: false, error: "content_required" };
  }
  if ([...content].length > MAX_CONTENT_LENGTH) {
    return { ok: false, error: "content_too_long" };
  }

  let username: string | null = null;
  if (record.username !== undefined && record.username !== null) {
    if (typeof record.username !== "string") {
      return { ok: false, error: "invalid_username" };
    }
    const trimmed = record.username.trim();
    if ([...trimmed].length > MAX_USERNAME_LENGTH) {
      return { ok: false, error: "invalid_username" };
    }
    username = trimmed === "" ? null : trimmed;
  }

  let avatarUrl: string | null = null;
  if (record.avatar_url !== undefined && record.avatar_url !== null) {
    if (typeof record.avatar_url !== "string") {
      return { ok: false, error: "invalid_avatar_url" };
    }
    const trimmed = record.avatar_url.trim();
    if (trimmed !== "" && !isHttpUrl(trimmed)) {
      return { ok: false, error: "invalid_avatar_url" };
    }
    avatarUrl = trimmed === "" ? null : trimmed;
  }

  return { ok: true, payload: { content, username, avatarUrl } };
}

export function isHttpUrl(value: string): boolean {
  if (value.length > MAX_AVATAR_URL_LENGTH || /\s/.test(value)) {
    return false;
  }
  try {
    const url = new URL(value);
    return (url.protocol === "http:" || url.protocol === "https:") &&
      url.hostname !== "";
  } catch {
    return false;
  }
}

/// The HTTP status and error name for an error code raised by
/// post_webhook_message.
export function statusForRpcError(
  code: string | undefined,
): { status: number; error: string } {
  switch (code) {
    case "P0002":
      return { status: 404, error: "unknown_webhook" };
    case "28000":
      return { status: 401, error: "invalid_token" };
    case "22023":
      return { status: 400, error: "invalid_message" };
    case "42501":
      return { status: 403, error: "creator_cannot_post" };
    case "WH429":
      return { status: 429, error: "rate_limited" };
    default:
      return { status: 500, error: "internal_error" };
  }
}
