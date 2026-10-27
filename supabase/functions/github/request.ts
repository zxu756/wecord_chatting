// Pure helpers of the github function: path parsing, limits, and mapping the
// database's errors to HTTP statuses.

/** GitHub's own limit is 25 MB; a card never needs more than the first part. */
export const MAX_BODY_BYTES = 1024 * 1024;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The events a connection can send (channel_github_hooks.events). */
export const EVENTS = [
  "issue_comment",
  "issues",
  "pull_request",
  "push",
  "release",
  "workflow_run",
] as const;

export type PathResult =
  | { ok: true; id: string }
  | { ok: false };

/// Reads `/…/github/{id}` from a request path.
export function parseGithubPath(pathname: string): PathResult {
  const parts = pathname.split("/").filter((part) => part !== "");
  const index = parts.lastIndexOf("github");
  if (index === -1 || parts.length !== index + 2) {
    return { ok: false };
  }
  let id: string;
  try {
    id = decodeURIComponent(parts[index + 1]);
  } catch {
    return { ok: false };
  }
  return UUID_PATTERN.test(id)
    ? { ok: true, id: id.toLowerCase() }
    : { ok: false };
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

/// The HTTP status and error name for an error code raised by
/// post_github_event.
export function statusForRpcError(
  code: string | undefined,
): { status: number; error: string } {
  switch (code) {
    case "P0002":
      return { status: 404, error: "unknown_connection" };
    case "22023":
      return { status: 400, error: "invalid_card" };
    case "42501":
      return { status: 403, error: "cannot_post" };
    case "WH429":
      return { status: 429, error: "rate_limited" };
    default:
      return { status: 500, error: "internal_error" };
  }
}
