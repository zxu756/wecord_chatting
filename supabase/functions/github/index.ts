// Posts GitHub events into a circle channel as cards (roadmap I6).
//
//   POST /functions/v1/github/{connection id}
//   X-GitHub-Event: push | pull_request | issues | issue_comment | release |
//                   workflow_run | ping
//   X-GitHub-Delivery: <guid>
//   X-Hub-Signature-256: sha256=<hmac of the raw body with the secret>
//   Content-Type: application/json
//
// The repository's owner sets this up in GitHub (Settings -> Webhooks) with
// the payload URL and the secret WeCord showed once when the connection was
// made; no GitHub App, OAuth or token of ours is involved. Public on purpose
// (verify_jwt = false in supabase/config.toml): GitHub sends no WeCord login.
// The signature is checked here, in constant time, against the secret that
// only the service role can read (github_hook_for_delivery), before anything
// in the body is looked at. Answers:
//   200  posted, a duplicate delivery, blocked by AutoMod, or `ping`
//   202  an event or action this connection does not report
//   400  not JSON / invalid; 401 wrong or missing signature; 403 the person
//   the connection posts as can no longer post, or the circle is taken down;
//   404 unknown connection; 409 the connection is paused; 413 over 1 MB;
//   415 form-encoded (set the content type to application/json in GitHub);
//   429 more than 30 messages in the current minute.
// A delivery id seen in the last 10 minutes is not posted twice.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { formatEvent } from "./format.ts";
import {
  EVENTS,
  isDeclaredTooLarge,
  isJsonContentType,
  MAX_BODY_BYTES,
  parseGithubPath,
  statusForRpcError,
} from "./request.ts";
import { verifyGithubSignature } from "./signature.ts";

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/// Reads at most MAX_BODY_BYTES of the body; null when it is longer.
async function readLimitedBody(request: Request): Promise<Uint8Array | null> {
  const reader = request.body?.getReader();
  if (!reader) {
    return new Uint8Array();
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
  return bytes;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const path = parseGithubPath(new URL(request.url).pathname);
  if (!path.ok) {
    return json({ error: "unknown_connection" }, 404);
  }
  if (isDeclaredTooLarge(request.headers.get("Content-Length"))) {
    return json({ error: "body_too_large" }, 413);
  }
  const contentType = request.headers.get("Content-Type");
  if (!isJsonContentType(contentType)) {
    return json({ error: "content_type_must_be_json" }, 415);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "not_configured" }, 500);
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const found = await admin.rpc("github_hook_for_delivery", {
    target_hook_id: path.id,
  });
  if (found.error) {
    console.error("github_hook_for_delivery failed", found.error.code);
    return json({ error: "internal_error" }, 500);
  }
  const hook = found.data as { secret: string; enabled: boolean } | null;
  if (hook === null) {
    return json({ error: "unknown_connection" }, 404);
  }

  const body = await readLimitedBody(request);
  if (body === null) {
    return json({ error: "body_too_large" }, 413);
  }
  if (
    !await verifyGithubSignature(
      hook.secret,
      body,
      request.headers.get("X-Hub-Signature-256"),
    )
  ) {
    return json({ error: "invalid_signature" }, 401);
  }

  const event = (request.headers.get("X-GitHub-Event") ?? "").toLowerCase();
  if (event === "ping") {
    return json({ ok: true, message: "pong" }, 200);
  }
  if (!(EVENTS as readonly string[]).includes(event)) {
    return json({ status: "ignored" }, 202);
  }
  if (!hook.enabled) {
    return json({ error: "connection_paused" }, 409);
  }

  let payload: unknown;
  try {
    payload = JSON.parse(new TextDecoder().decode(body));
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const card = formatEvent(event, payload);
  if (card === null) {
    return json({ status: "ignored" }, 202);
  }

  const { data, error } = await admin.rpc("post_github_event", {
    target_hook_id: path.id,
    delivery: request.headers.get("X-GitHub-Delivery") ?? "",
    event_name: event,
    card,
  });
  if (error) {
    const mapped = statusForRpcError(error.code);
    if (mapped.status === 500) {
      console.error("post_github_event failed", error.code, error.message);
    }
    return json({ error: mapped.error }, mapped.status);
  }
  const status = (data as { status?: string } | null)?.status ?? "posted";
  if (status === "paused") {
    return json({ error: "connection_paused" }, 409);
  }
  if (status === "ignored") {
    return json({ status }, 202);
  }
  return json({ status }, 200);
});
