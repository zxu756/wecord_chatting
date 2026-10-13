// Posts a message into a circle channel through one of its webhooks.
//
//   POST /functions/v1/webhook/{id}/{token}
//   Content-Type: application/json
//   {"content": "…", "username": "…"?, "avatar_url": "https://…"?}
//
// Public on purpose (verify_jwt = false): external services authenticate
// with the secret token in the URL, which post_webhook_message checks
// against its stored hash. Answers 204 on success, 400 for bad requests,
// 401 for a wrong token, 403 when the webhook's creator can no longer post,
// 404 for unknown webhooks, 413 for bodies over 16 KB and 429 when the
// webhook sent 30 messages in the current minute.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  isDeclaredTooLarge,
  isJsonContentType,
  MAX_BODY_BYTES,
  parseWebhookPath,
  statusForRpcError,
  validatePayload,
} from "./request.ts";

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/// Reads at most MAX_BODY_BYTES of the body; null when it is longer.
async function readLimitedBody(request: Request): Promise<string | null> {
  const reader = request.body?.getReader();
  if (!reader) {
    return "";
  }
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    total += value.byteLength;
    if (total > MAX_BODY_BYTES) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const path = parseWebhookPath(new URL(request.url).pathname);
  if (!path.ok) {
    return json(
      { error: path.status === 404 ? "unknown_webhook" : "invalid_token" },
      path.status,
    );
  }

  if (isDeclaredTooLarge(request.headers.get("Content-Length"))) {
    return json({ error: "body_too_large" }, 413);
  }
  if (!isJsonContentType(request.headers.get("Content-Type"))) {
    return json({ error: "content_type_must_be_json" }, 400);
  }

  const text = await readLimitedBody(request);
  if (text === null) {
    return json({ error: "body_too_large" }, 413);
  }
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const checked = validatePayload(body);
  if (!checked.ok) {
    return json({ error: checked.error }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "not_configured" }, 500);
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { error } = await admin.rpc("post_webhook_message", {
    target_webhook_id: path.id,
    webhook_token: path.token,
    content: checked.payload.content,
    username: checked.payload.username,
    avatar_url: checked.payload.avatarUrl,
  });
  if (error) {
    const mapped = statusForRpcError(error.code);
    if (mapped.status === 500) {
      console.error("post_webhook_message failed", error.code, error.message);
    }
    return json({ error: mapped.error }, mapped.status);
  }
  return new Response(null, { status: 204 });
});
