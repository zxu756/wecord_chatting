// Turns an Office file sent in a chat (Word, Excel, PowerPoint,
// OpenDocument, RTF, iWork) into a PDF for the web app's viewer, which has
// no Quick Look.
//
// POST {message_id} with the user's session. The message is read with the
// caller's JWT, so row level security decides whether they may see it. The
// file is fetched with the service role, converted by a Gotenberg server
// (POST <GOTENBERG_URL>/forms/libreoffice/convert with
// `Authorization: Basic base64(GOTENBERG_USERNAME:GOTENBERG_PASSWORD)`),
// kept in the private file-previews bucket at <message id>/preview.pdf and
// returned as a one-hour signed URL: {status: "ok", url, cached}.
//
// Without GOTENBERG_URL, GOTENBERG_USERNAME and GOTENBERG_PASSWORD it
// answers 503 {error: "preview_not_configured"}; the app then offers the
// download. See docs/file-preview-converter.md.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  conversionFileName,
  corsHeaders,
  errorResponse,
  fileAttachmentOf,
  jsonResponse,
  looksLikePdf,
  MAX_SOURCE_BYTES,
  officeExtension,
  parsePreviewRequest,
  previewObjectPath,
  readGotenbergConfig,
} from "./preview_helpers.ts";

const BUCKET = "file-previews";
const SIGNED_URL_SECONDS = 60 * 60;
const CONVERT_TIMEOUT_MS = 110_000;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return errorResponse("method_not_allowed");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return errorResponse("not_configured");
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (token === "" || token === authorization) {
    return errorResponse("unauthorized");
  }
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(
    token,
  );
  if (userError || !userData?.user) {
    return errorResponse("unauthorized");
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse("invalid_body");
  }
  const parsed = parsePreviewRequest(body);
  if (!parsed.ok) {
    return errorResponse(parsed.error);
  }

  // As the caller: no row unless they can see the message.
  const { data: message, error: messageError } = await userClient
    .from("messages")
    .select("id, type, attachment, recalled_at")
    .eq("id", parsed.messageId)
    .maybeSingle();
  if (messageError || !message) {
    return errorResponse("not_found");
  }
  const file = fileAttachmentOf(message);
  if (!file) {
    return errorResponse("not_found");
  }
  const extension = officeExtension(file.name, file.mimeType);
  if (!extension) {
    return errorResponse("unsupported_type");
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const objectPath = previewObjectPath(parsed.messageId);
  const previews = admin.storage.from(BUCKET);

  sweepStalePreviews(admin);

  // Converted before: hand it out again.
  const cached = await previews.createSignedUrl(objectPath, SIGNED_URL_SECONDS);
  if (!cached.error && cached.data?.signedUrl) {
    return jsonResponse({
      status: "ok",
      url: cached.data.signedUrl,
      cached: true,
    });
  }

  const gotenberg = readGotenbergConfig((name) => Deno.env.get(name));
  if (!gotenberg) {
    return errorResponse("preview_not_configured");
  }
  if (file.size > MAX_SOURCE_BYTES) {
    return errorResponse("file_too_large");
  }

  const source = await admin.storage.from(file.bucket).download(file.path);
  if (source.error || !source.data) {
    console.error(
      "office-preview: source download failed",
      source.error?.message,
    );
    return errorResponse("not_found");
  }
  if (source.data.size > MAX_SOURCE_BYTES) {
    return errorResponse("file_too_large");
  }

  let pdf: Uint8Array;
  try {
    pdf = await convert(gotenberg, source.data, conversionFileName(extension));
  } catch (error) {
    console.error("office-preview: conversion failed", String(error));
    return errorResponse("conversion_failed");
  }

  const upload = await previews.upload(objectPath, pdf, {
    contentType: "application/pdf",
    upsert: true,
  });
  if (upload.error) {
    console.error("office-preview: upload failed", upload.error.message);
    return errorResponse("storage_failed");
  }
  const signed = await previews.createSignedUrl(objectPath, SIGNED_URL_SECONDS);
  if (signed.error || !signed.data?.signedUrl) {
    return errorResponse("storage_failed");
  }
  return jsonResponse({
    status: "ok",
    url: signed.data.signedUrl,
    cached: false,
  });
});

async function convert(
  gotenberg: { convertUrl: string; authorization: string },
  file: Blob,
  fileName: string,
): Promise<Uint8Array> {
  const form = new FormData();
  form.append("files", file, fileName);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), CONVERT_TIMEOUT_MS);
  try {
    const response = await fetch(gotenberg.convertUrl, {
      method: "POST",
      headers: { Authorization: gotenberg.authorization },
      body: form,
      signal: controller.signal,
    });
    if (!response.ok) {
      const detail = (await response.text()).slice(0, 300);
      throw new Error(`gotenberg ${response.status}: ${detail}`);
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (!looksLikePdf(bytes)) {
      throw new Error("gotenberg returned something other than a PDF");
    }
    return bytes;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Removes a few previews whose message was deleted (Storage objects can't
 * be deleted from SQL). Runs after the response where the runtime allows.
 */
// deno-lint-ignore no-explicit-any
function sweepStalePreviews(admin: any): void {
  const sweep = (async () => {
    const { data, error } = await admin.rpc("stale_file_previews", {
      max_rows: 20,
    });
    if (error || !Array.isArray(data) || data.length === 0) {
      return;
    }
    const names = data
      .map((row: { object_name?: unknown }) => row.object_name)
      .filter((name: unknown): name is string => typeof name === "string");
    if (names.length > 0) {
      await admin.storage.from(BUCKET).remove(names);
    }
  })().catch((error) =>
    console.error("office-preview: sweep failed", String(error))
  );
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(sweep);
  }
}
