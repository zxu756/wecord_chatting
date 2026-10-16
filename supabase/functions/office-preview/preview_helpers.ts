// Pure helpers for the office-preview function (tested in
// preview_helpers_test.ts).

/** Files LibreOffice (inside Gotenberg) turns into PDF for the viewer. */
export const OFFICE_EXTENSIONS: ReadonlySet<string> = new Set([
  "doc",
  "docx",
  "docm",
  "dot",
  "dotx",
  "odt",
  "ott",
  "rtf",
  "xls",
  "xlsx",
  "xlsm",
  "xlsb",
  "xlt",
  "xltx",
  "ods",
  "ots",
  "ppt",
  "pptx",
  "pptm",
  "pps",
  "ppsx",
  "pot",
  "potx",
  "odp",
  "otp",
  "pages",
  "numbers",
  "key",
]);

const MIME_EXTENSIONS: Record<string, string> = {
  "application/msword": "doc",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
    "docx",
  "application/vnd.ms-excel": "xls",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
  "application/vnd.ms-powerpoint": "ppt",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation":
    "pptx",
  "application/vnd.oasis.opendocument.text": "odt",
  "application/vnd.oasis.opendocument.spreadsheet": "ods",
  "application/vnd.oasis.opendocument.presentation": "odp",
  "application/rtf": "rtf",
  "text/rtf": "rtf",
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The largest file the function converts (the chat-files limit). */
export const MAX_SOURCE_BYTES = 50 * 1024 * 1024;

export interface FileAttachment {
  bucket: string;
  path: string;
  name: string;
  mimeType: string;
  size: number;
}

export type ParsedRequest =
  | { ok: true; messageId: string }
  | { ok: false; error: "invalid_body" | "invalid_message_id" };

/** Reads `{message_id}` from the request body. */
export function parsePreviewRequest(body: unknown): ParsedRequest {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, error: "invalid_body" };
  }
  const id = (body as Record<string, unknown>).message_id;
  if (typeof id !== "string" || !UUID.test(id.trim())) {
    return { ok: false, error: "invalid_message_id" };
  }
  return { ok: true, messageId: id.trim().toLowerCase() };
}

/** Where a message's converted PDF is kept in the file-previews bucket. */
export function previewObjectPath(messageId: string): string {
  return `${messageId.toLowerCase()}/preview.pdf`;
}

/** The file of a file message row, or null for anything else. */
export function fileAttachmentOf(
  message: { type?: unknown; attachment?: unknown; recalled_at?: unknown },
): FileAttachment | null {
  if (message.type !== "file" || message.recalled_at) {
    return null;
  }
  const a = message.attachment;
  if (a === null || typeof a !== "object") {
    return null;
  }
  const { kind, bucket, path, name, mime_type, size } = a as Record<
    string,
    unknown
  >;
  if (
    (kind !== "file" && kind !== "video") || typeof bucket !== "string" ||
    typeof path !== "string"
  ) {
    return null;
  }
  return {
    bucket,
    path,
    name: typeof name === "string" && name.trim() !== ""
      ? name
      : path.split("/").pop() ?? "file",
    mimeType: typeof mime_type === "string"
      ? mime_type
      : "application/octet-stream",
    size: typeof size === "number" ? size : 0,
  };
}

/** The Office extension of a file (by name, else by MIME type), or null. */
export function officeExtension(name: string, mimeType: string): string | null {
  const base = name.split("/").pop()?.trim().toLowerCase() ?? "";
  const dot = base.lastIndexOf(".");
  const ext = dot > 0 ? base.slice(dot + 1) : "";
  if (OFFICE_EXTENSIONS.has(ext)) {
    return ext;
  }
  return MIME_EXTENSIONS[mimeType.toLowerCase()] ?? null;
}

export interface GotenbergConfig {
  /** `<GOTENBERG_URL>/forms/libreoffice/convert` */
  convertUrl: string;
  /** `Basic base64(GOTENBERG_USERNAME:GOTENBERG_PASSWORD)` */
  authorization: string;
}

/**
 * The converter settings, or null when any of GOTENBERG_URL,
 * GOTENBERG_USERNAME and GOTENBERG_PASSWORD is missing (the function then
 * answers 503 preview_not_configured).
 */
export function readGotenbergConfig(
  env: (name: string) => string | undefined,
): GotenbergConfig | null {
  const url = env("GOTENBERG_URL")?.trim();
  const username = env("GOTENBERG_USERNAME")?.trim();
  const password = env("GOTENBERG_PASSWORD");
  if (!url || !username || !password) {
    return null;
  }
  let base: URL;
  try {
    base = new URL(url);
  } catch {
    return null;
  }
  if (base.protocol !== "https:" && base.protocol !== "http:") {
    return null;
  }
  return {
    convertUrl: gotenbergConvertUrl(base.href),
    authorization: basicAuthorization(username, password),
  };
}

export function gotenbergConvertUrl(base: string): string {
  return `${base.replace(/\/+$/, "")}/forms/libreoffice/convert`;
}

/** An HTTP Basic Authorization value (UTF-8 user and password). */
export function basicAuthorization(username: string, password: string): string {
  const bytes = new TextEncoder().encode(`${username}:${password}`);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return `Basic ${btoa(binary)}`;
}

/**
 * The name the file is uploaded to Gotenberg under: LibreOffice picks the
 * importer from the extension, and plain ASCII avoids multipart quirks.
 */
export function conversionFileName(extension: string): string {
  return `document.${extension.replace(/[^a-z0-9]/gi, "").toLowerCase()}`;
}

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export type PreviewError =
  | "method_not_allowed"
  | "not_configured"
  | "unauthorized"
  | "invalid_body"
  | "invalid_message_id"
  | "not_found"
  | "unsupported_type"
  | "file_too_large"
  | "preview_not_configured"
  | "conversion_failed"
  | "storage_failed";

const STATUS: Record<PreviewError, number> = {
  method_not_allowed: 405,
  not_configured: 500,
  unauthorized: 401,
  invalid_body: 400,
  invalid_message_id: 400,
  not_found: 404,
  unsupported_type: 415,
  file_too_large: 413,
  preview_not_configured: 503,
  conversion_failed: 502,
  storage_failed: 500,
};

export function statusFor(error: PreviewError): number {
  return STATUS[error];
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function errorResponse(error: PreviewError): Response {
  return jsonResponse({ error }, statusFor(error));
}

/** Whether a Gotenberg response looks like a PDF. */
export function looksLikePdf(bytes: Uint8Array): boolean {
  return bytes.length > 4 && bytes[0] === 0x25 && bytes[1] === 0x50 &&
    bytes[2] === 0x44 && bytes[3] === 0x46; // %PDF
}
