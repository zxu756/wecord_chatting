// Speech to text through an OpenAI-compatible `/audio/transcriptions`
// endpoint, named by the optional AI_TRANSCRIBE_* secrets. The audio is
// sent for this one request and never stored. No Supabase here, so it can
// be tested with a fake fetch.

import { normalizeBaseUrl } from "./config.ts";
import { isBusyStatus, ProviderError, USER_AGENT } from "./provider.ts";

export const TRANSCRIBE_TIMEOUT_MS = 90_000;

/// The provider's usual cap on one upload (OpenAI: 25 MB). Longer voice
/// messages are refused before anything is sent.
export const MAX_AUDIO_BYTES = 25 * 1024 * 1024;

export interface TranscribeConfig {
  /// Without a trailing slash, e.g. https://api.openai.com/v1.
  baseUrl: string;
  apiKey: string;
  model: string;
}

type Getter = (name: string) => string | undefined;

/// The transcription provider, or null when the optional secrets
/// AI_TRANSCRIBE_BASE_URL, AI_TRANSCRIBE_API_KEY and AI_TRANSCRIBE_MODEL
/// are not all set (or the base URL is not usable).
export function readTranscribeConfig(get: Getter): TranscribeConfig | null {
  const baseUrl = normalizeBaseUrl(get("AI_TRANSCRIBE_BASE_URL"));
  const apiKey = get("AI_TRANSCRIBE_API_KEY")?.trim();
  const model = get("AI_TRANSCRIBE_MODEL")?.trim();
  if (!baseUrl || !apiKey || !model) {
    return null;
  }
  return { baseUrl, apiKey, model };
}

export function transcriptionsUrl(baseUrl: string): string {
  return `${baseUrl.replace(/\/+$/, "")}/audio/transcriptions`;
}

const EXTENSIONS: Record<string, string> = {
  "audio/wav": "wav",
  "audio/x-wav": "wav",
  "audio/wave": "wav",
  "audio/mpeg": "mp3",
  "audio/mp3": "mp3",
  "audio/mp4": "m4a",
  "audio/m4a": "m4a",
  "audio/x-m4a": "m4a",
  "audio/aac": "m4a",
  "audio/ogg": "ogg",
  "audio/webm": "webm",
  "audio/flac": "flac",
};

/// A file name the provider recognizes the format by.
export function audioFileName(mimeType: string, path: string): string {
  const fromType = EXTENSIONS[mimeType.split(";")[0].trim().toLowerCase()];
  if (fromType) {
    return `voice.${fromType}`;
  }
  const match = /\.([a-z0-9]{2,5})$/i.exec(path);
  return `voice.${match ? match[1].toLowerCase() : "wav"}`;
}

/// The text of a transcription answer (empty for silence), or null when the
/// answer has no text field at all.
export function extractTranscript(body: unknown): string | null {
  if (body === null || typeof body !== "object") {
    return null;
  }
  const text = (body as { text?: unknown }).text;
  return typeof text === "string" ? text.trim() : null;
}

type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

/// Transcribes [audio]; throws [ProviderError].
export async function transcribeAudio(
  config: TranscribeConfig,
  audio: { bytes: Uint8Array; mimeType: string; fileName: string },
  fetchFn: Fetch = fetch,
): Promise<string> {
  const form = new FormData();
  form.append("model", config.model);
  form.append("response_format", "json");
  form.append(
    "file",
    new Blob([audio.bytes as BlobPart], { type: audio.mimeType }),
    audio.fileName,
  );
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TRANSCRIBE_TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetchFn(transcriptionsUrl(config.baseUrl), {
      method: "POST",
      headers: {
        // No Content-Type: fetch sets the multipart boundary itself.
        "Authorization": `Bearer ${config.apiKey}`,
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
      },
      body: form,
      signal: controller.signal,
    });
  } catch (error) {
    clearTimeout(timer);
    console.error("transcribe provider request failed", String(error));
    throw new ProviderError("failed");
  }
  try {
    if (!response.ok) {
      await response.body?.cancel();
      console.error("transcribe provider answered", response.status);
      throw new ProviderError(
        isBusyStatus(response.status) ? "busy" : "failed",
        response.status,
      );
    }
    let json: unknown;
    try {
      json = await response.json();
    } catch {
      throw new ProviderError("failed", response.status);
    }
    const text = extractTranscript(json);
    if (text === null) {
      throw new ProviderError("empty", response.status);
    }
    return text;
  } finally {
    clearTimeout(timer);
  }
}
