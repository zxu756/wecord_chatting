// The bot API: programs drive a circle's bot account with its token.
//
//   Authorization: Bot <token>
//
//   GET  /functions/v1/bot-api/me
//   GET  /functions/v1/bot-api/channels
//   GET  /functions/v1/bot-api/channels/{id}/messages?limit=50&before=<ISO time>
//   POST /functions/v1/bot-api/channels/{id}/messages   {"content", "reply_to"?}
//   PUT  /functions/v1/bot-api/messages/{id}/reactions/{emoji}
//   GET  /functions/v1/bot-api/commands
//   PUT  /functions/v1/bot-api/commands   [{"name", "description"}]
//   GET  /functions/v1/bot-api/interactions?limit=25
//   POST /functions/v1/bot-api/interactions/{id}/respond   {"content"}
//
// Public on purpose (verify_jwt = false): bots authenticate with their
// token, which the bot_api_* database functions check against its stored
// hash before acting as the bot with the bot's own circle permissions.
// See docs/bot-api.md.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  isJsonContentType,
  matchRoute,
  MAX_BODY_BYTES,
  parseBotAuthorization,
  type Route,
  statusForRpcError,
  validateCommands,
  validateMessageBody,
} from "./request.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/// The JSON body, at most MAX_BODY_BYTES; an error response otherwise.
async function readJson(
  request: Request,
): Promise<{ ok: true; body: unknown } | { ok: false; response: Response }> {
  if (!isJsonContentType(request.headers.get("Content-Type"))) {
    return {
      ok: false,
      response: json({ error: "content_type_must_be_json" }, 400),
    };
  }
  const declared = Number(request.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    return { ok: false, response: json({ error: "body_too_large" }, 413) };
  }
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) {
    return { ok: false, response: json({ error: "body_too_large" }, 413) };
  }
  try {
    return { ok: true, body: JSON.parse(text) };
  } catch {
    return { ok: false, response: json({ error: "invalid_json" }, 400) };
  }
}

type Rpc = (
  name: string,
  params: Record<string, unknown>,
) => Promise<
  { data: unknown; error: { code?: string; message: string } | null }
>;

/// 201 with the new message's id; AutoMod refuses messages quietly, which
/// comes back as a null id.
function created(data: unknown): Response {
  if (data === null || data === undefined) {
    return json(
      { error: "blocked", message: "The circle's AutoMod blocked the message" },
      403,
    );
  }
  return json({ id: data }, 201);
}

async function handle(
  route: Route,
  request: Request,
  token: string,
  rpc: Rpc,
): Promise<Response> {
  const call = async (
    name: string,
    params: Record<string, unknown>,
    success: (data: unknown) => Response,
  ) => {
    const { data, error } = await rpc(name, { bot_token: token, ...params });
    if (error) {
      const mapped = statusForRpcError(error.code);
      if (mapped.status === 500) {
        console.error(name, "failed", error.code, error.message);
      }
      return json(
        {
          error: mapped.error,
          message: mapped.status === 500 ? undefined : error.message,
        },
        mapped.status,
      );
    }
    return success(data);
  };

  switch (route.name) {
    case "me":
      return call("bot_api_me", {}, (data) => json(data));
    case "channels":
      return call("bot_api_list_channels", {}, (data) => json(data));
    case "list_messages":
      return call(
        "bot_api_list_messages",
        {
          target_channel_id: route.channelId,
          max_count: route.limit,
          before_time: route.before,
        },
        (data) => json(data),
      );
    case "send_message": {
      const read = await readJson(request);
      if (!read.ok) return read.response;
      const checked = validateMessageBody(read.body);
      if (!checked.ok) return json({ error: checked.error }, 400);
      return call(
        "bot_api_send_message",
        {
          target_channel_id: route.channelId,
          content: checked.value.content,
          reply_to_message_id: checked.value.replyTo,
        },
        created,
      );
    }
    case "add_reaction":
      return call(
        "bot_api_add_reaction",
        { target_message_id: route.messageId, emoji: route.emoji },
        () => new Response(null, { status: 204 }),
      );
    case "list_commands":
      return call("bot_api_list_commands", {}, (data) => json(data));
    case "set_commands": {
      const read = await readJson(request);
      if (!read.ok) return read.response;
      const checked = validateCommands(read.body);
      if (!checked.ok) return json({ error: checked.error }, 400);
      return call(
        "bot_api_set_commands",
        { commands: checked.value },
        (data) => json(data),
      );
    }
    case "poll_interactions":
      return call(
        "bot_api_poll_interactions",
        { max_count: route.limit },
        (data) => json(data),
      );
    case "respond_interaction": {
      const read = await readJson(request);
      if (!read.ok) return read.response;
      const checked = validateMessageBody(read.body);
      if (!checked.ok) return json({ error: checked.error }, 400);
      return call(
        "bot_api_respond_interaction",
        {
          target_interaction_id: route.interactionId,
          content: checked.value.content,
        },
        created,
      );
    }
  }
}

Deno.serve(async (request) => {
  const matched = matchRoute(request.method, new URL(request.url));
  if (!matched.ok) {
    return json({ error: matched.error }, matched.status);
  }

  const token = parseBotAuthorization(request.headers.get("Authorization"));
  if (token === null) {
    return json({ error: "invalid_token" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "not_configured" }, 500);
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return await handle(
    matched.route,
    request,
    token,
    (name, params) => admin.rpc(name, params) as unknown as ReturnType<Rpc>,
  );
});
