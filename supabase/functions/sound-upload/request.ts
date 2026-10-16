// Request checks for the `sound-upload` Edge Function, kept apart from
// Deno.serve so they can be tested.
import { measureAudio } from "./audio_duration.ts";

export const maxSoundBytes = 524288;

/// Sounds are at most 5 seconds; a little slack covers encoder padding
/// and frame rounding, and the stored length is capped at 5 seconds.
export const maxSoundSeconds = 5.2;

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type Refusal = { ok: false; status: number; error: string };

export type UploadFields = {
  ok: true;
  circleId: string;
  name: string;
  emoji: string | null;
};

/// The form fields: circle_id, name (1 to 32 characters), emoji (optional).
export function readUploadFields(
  fields: { circle_id?: unknown; name?: unknown; emoji?: unknown },
): UploadFields | Refusal {
  const circleId = fields.circle_id;
  const name = typeof fields.name === "string" ? fields.name.trim() : "";
  const emoji = typeof fields.emoji === "string" && fields.emoji.trim() !== ""
    ? fields.emoji.trim()
    : null;
  if (
    typeof circleId !== "string" || !uuidPattern.test(circleId) ||
    name.length < 1 || [...name].length > 32 ||
    (emoji !== null && [...emoji].length > 16)
  ) {
    return { ok: false, status: 400, error: "invalid_request" };
  }
  return { ok: true, circleId: circleId.toLowerCase(), name, emoji };
}

export type CheckedClip = {
  ok: true;
  mimeType: string;
  extension: string;
  seconds: number;
  durationMs: number;
};

/// Measures the clip and refuses what is too big, too long or can't be
/// verified.
export function checkClip(bytes: Uint8Array): CheckedClip | Refusal {
  if (bytes.length === 0) {
    return { ok: false, status: 400, error: "missing_file" };
  }
  if (bytes.length > maxSoundBytes) {
    return { ok: false, status: 413, error: "too_large" };
  }
  const measured = measureAudio(bytes);
  if (!measured.ok) {
    return measured.error === "unsupported"
      ? { ok: false, status: 415, error: "unsupported_format" }
      : { ok: false, status: 400, error: "malformed" };
  }
  if (!Number.isFinite(measured.seconds) || measured.seconds <= 0) {
    return { ok: false, status: 400, error: "malformed" };
  }
  if (measured.seconds > maxSoundSeconds) {
    return { ok: false, status: 400, error: "too_long" };
  }
  return {
    ok: true,
    mimeType: measured.mimeType,
    extension: measured.extension,
    seconds: measured.seconds,
    durationMs: Math.min(
      5000,
      Math.max(1, Math.round(measured.seconds * 1000)),
    ),
  };
}

/// The HTTP status and error for a create_circle_sound refusal.
export function refusalForRpcError(code: string | undefined): Refusal {
  switch (code) {
    case "42501":
      return { ok: false, status: 403, error: "forbidden" };
    case "23505":
      return { ok: false, status: 409, error: "name_taken" };
    case "54000":
      return { ok: false, status: 409, error: "no_room" };
    case "22023":
      return { ok: false, status: 400, error: "invalid_request" };
    default:
      return { ok: false, status: 500, error: "create_failed" };
  }
}
