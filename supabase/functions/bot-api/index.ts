// The bot API: programs drive a circle's bot account with its token.
//
//   Authorization: Bot <token>
//
//   GET  /functions/v1/bot-api/me
//   GET  /functions/v1/bot-api/channels
//   GET  /functions/v1/bot-api/channels/{id}/messages?limit=50&before=<ISO time>
//   POST /functions/v1/bot-api/channels/{id}/messages   {"content", "reply_to"?, "components"?}
//   PATCH /functions/v1/bot-api/messages/{id}            {"content"?, "components"?}
//   DELETE /functions/v1/bot-api/messages/{id}
//   PUT  /functions/v1/bot-api/messages/{id}/reactions/{emoji}
//   DELETE /functions/v1/bot-api/messages/{id}/reactions/{emoji}
//   POST /functions/v1/bot-api/messages/{id}/thread      {"title"?}
//   GET  /functions/v1/bot-api/chats
//   GET  /functions/v1/bot-api/chats/{id}/messages?limit=50&before=<ISO time>
//   POST /functions/v1/bot-api/chats/{id}/messages       {"content", "reply_to"?, "components"?}
//   POST /functions/v1/bot-api/chats/{id}/files          multipart: file, caption?
//   POST /functions/v1/bot-api/chats/{id}/polls          {"question", "options", "multiple"?, "duration_hours"?, "anonymous"?}
//   GET  /functions/v1/bot-api/chats/{id}/members?limit=100&after=<user id>
//   GET  /functions/v1/bot-api/chats/{id}/members/{user}
//   GET  /functions/v1/bot-api/commands
//   PUT  /functions/v1/bot-api/commands   [{"name", "description"}]
//   GET  /functions/v1/bot-api/interactions?limit=25
//   POST /functions/v1/bot-api/interactions/{id}/respond
//        {"type"?: "message"|"ephemeral"|"update"|"ack", "content"?, "components"?}
//
// Public on purpose (verify_jwt = false): bots authenticate with their
// token, which the bot_api_* database functions check against its stored
// hash before acting as the bot with the bot's own circle permissions.
// See docs/bot-api.md.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  cleanFileName,
  isJsonContentType,
  matchRoute,
  MAX_BODY_BYTES,
  MAX_CAPTION_LENGTH,
  MAX_FILE_BYTES,
  parseBotAuthorization,
  type Route,
  routeTemplate,
  statusForRpcError,
  storageFileName,
  validateCommands,
  validateEditBody,
  validateMessageBody,
  validatePollBody,
  validateRespondBody,
  validateThreadBody,
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

type RpcError = { code?: string; message: string };

/// What the function needs besides the database functions: the file store.
type Backend = {
  rpc: Rpc;
  /// Stores a file in chat-files; the error text, or null when it worked.
  upload(
    path: string,
    bytes: Uint8Array,
    contentType: string,
  ): Promise<string | null>;
  /// Removes stored files, quietly.
  remove(bucket: string, paths: string[]): Promise<void>;
};

function failure(name: string, error: RpcError): Response {
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

function blocked(message: string): Response {
  return json({ error: "blocked", message }, 403);
}

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

/// Like readJson, but an empty body is fine (it comes back as null).
async function readOptionalJson(
  request: Request,
): Promise<{ ok: true; body: unknown } | { ok: false; response: Response }> {
  const declared = Number(request.headers.get("Content-Length") ?? "0");
  const hasType = request.headers.get("Content-Type") !== null;
  if (!hasType && (!Number.isFinite(declared) || declared === 0)) {
    return { ok: true, body: null };
  }
  return await readJson(request);
}

/// POST /chats/{id}/files: a multipart form with `file` (at most 8 MB) and
/// an optional `caption`. The bytes are stored under the bot's own folder of
/// the chat, then the database function posts the message; if it refuses,
/// the file is taken out again.
async function sendFile(
  chatId: string,
  request: Request,
  token: string,
  backend: Backend,
): Promise<Response> {
  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.toLowerCase().startsWith("multipart/form-data")) {
    return json({ error: "content_type_must_be_multipart" }, 400);
  }
  const declared = Number(request.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(declared) && declared > MAX_FILE_BYTES + 256 * 1024) {
    return json({ error: "file_too_large" }, 413);
  }
  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return json({ error: "invalid_form" }, 400);
  }
  const file = form.get("file");
  if (!(file instanceof File)) {
    return json({ error: "file_required" }, 400);
  }
  if (file.size < 1) {
    return json({ error: "file_empty" }, 400);
  }
  if (file.size > MAX_FILE_BYTES) {
    return json({ error: "file_too_large" }, 413);
  }
  const captionValue = form.get("caption");
  if (captionValue !== null && typeof captionValue !== "string") {
    return json({ error: "invalid_caption" }, 400);
  }
  const caption = (captionValue ?? "").trim();
  if ([...caption].length > MAX_CAPTION_LENGTH) {
    return json({ error: "caption_too_long" }, 400);
  }

  // Who the bot is, and whether it may use this chat, before anything is
  // stored.
  const me = await backend.rpc("bot_api_me", { bot_token: token });
  if (me.error) return failure("bot_api_me", me.error);
  const botUserId = (me.data as { user_id?: unknown } | null)?.user_id;
  if (typeof botUserId !== "string") {
    return json({ error: "internal_error" }, 500);
  }
  const probe = await backend.rpc("bot_api_list_chat_messages", {
    bot_token: token,
    target_chat_id: chatId,
    max_count: 1,
    before_time: null,
  });
  if (probe.error) return failure("bot_api_list_chat_messages", probe.error);

  const name = cleanFileName(file.name);
  const path = `${chatId}/${botUserId}/${crypto.randomUUID()}-${
    storageFileName(name)
  }`;
  const mime = file.type !== "" ? file.type : "application/octet-stream";
  const stored = await backend.upload(
    path,
    new Uint8Array(await file.arrayBuffer()),
    mime,
  );
  if (stored !== null) {
    console.error("bot file upload failed", stored);
    return json({ error: "storage_failed" }, 500);
  }

  const sent = await backend.rpc("bot_api_send_file_message", {
    bot_token: token,
    target_chat_id: chatId,
    file_path: path,
    file_name: name,
    file_size: file.size,
    file_mime: mime,
    caption: caption === "" ? null : caption,
  });
  if (sent.error || sent.data === null || sent.data === undefined) {
    await backend.remove("chat-files", [path]);
    if (sent.error) return failure("bot_api_send_file_message", sent.error);
    return blocked("The circle's AutoMod blocked the message");
  }
  return created(sent.data);
}

async function handle(
  route: Route,
  request: Request,
  token: string,
  backend: Backend,
): Promise<Response> {
  const rpc = backend.rpc;
  const call = async (
    name: string,
    params: Record<string, unknown>,
    success: (data: unknown) => Response | Promise<Response>,
  ) => {
    const { data, error } = await rpc(name, { bot_token: token, ...params });
    if (error) {
      return failure(name, error);
    }
    return await success(data);
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
      if (checked.value.components) {
        // Buttons and lists: the database function checks every part.
        return call(
          "bot_api_send_message_with_components",
          {
            target_channel_id: route.channelId,
            content: checked.value.content,
            reply_to_message_id: checked.value.replyTo,
            message_components: checked.value.components,
          },
          created,
        );
      }
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
    case "edit_message": {
      const read = await readJson(request);
      if (!read.ok) return read.response;
      const checked = validateEditBody(read.body);
      if (!checked.ok) return json({ error: checked.error }, 400);
      return call(
        "bot_api_edit_message",
        {
          target_message_id: route.messageId,
          new_content: checked.value.content,
          change_components: checked.value.changeComponents,
          new_components: checked.value.components,
        },
        (data) =>
          data === true ? json({ id: route.messageId }) : json(
            {
              error: "blocked",
              message: "The circle's AutoMod blocked the change",
            },
            403,
          ),
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
    case "delete_message":
      return call(
        "bot_api_delete_message",
        { target_message_id: route.messageId },
        async (data) => {
          // The files that were attached go from storage too.
          const files = Array.isArray(data) ? data : [];
          const byBucket = new Map<string, string[]>();
          for (const file of files) {
            const record = file as { bucket?: unknown; path?: unknown };
            if (
              typeof record.bucket === "string" &&
              typeof record.path === "string"
            ) {
              byBucket.set(record.bucket, [
                ...(byBucket.get(record.bucket) ?? []),
                record.path,
              ]);
            }
          }
          for (const [bucket, paths] of byBucket) {
            await backend.remove(bucket, paths);
          }
          return new Response(null, { status: 204 });
        },
      );
    case "remove_reaction":
      return call(
        "bot_api_remove_reaction",
        { target_message_id: route.messageId, emoji: route.emoji },
        () => new Response(null, { status: 204 }),
      );
    case "create_thread": {
      const read = await readOptionalJson(request);
      if (!read.ok) return read.response;
      const checked = validateThreadBody(read.body);
      if (!checked.ok) return json({ error: checked.error }, 400);
      return call(
        "bot_api_create_thread",
        {
          target_message_id: route.messageId,
          thread_title: checked.value.title,
        },
        (data) =>
          data === null || data === undefined
            ? blocked("The circle's AutoMod blocked the thread title")
            : json(data, 201),
      );
    }
    case "chats":
      return call("bot_api_list_chats", {}, (data) => json(data));
    case "list_chat_messages":
      return call(
        "bot_api_list_chat_messages",
        {
          target_chat_id: route.chatId,
          max_count: route.limit,
          before_time: route.before,
        },
        (data) => json(data),
      );
    case "send_chat_message": {
      const read = await readJson(request);
      if (!read.ok) return read.response;
      const checked = validateMessageBody(read.body);
      if (!checked.ok) return json({ error: checked.error }, 400);
      return call(
        "bot_api_send_chat_message",
        {
          target_chat_id: route.chatId,
          content: checked.value.content,
          reply_to_message_id: checked.value.replyTo,
          message_components: checked.value.components ?? null,
        },
        created,
      );
    }
    case "create_poll": {
      const read = await readJson(request);
      if (!read.ok) return read.response;
      const checked = validatePollBody(read.body);
      if (!checked.ok) return json({ error: checked.error }, 400);
      return call(
        "bot_api_create_poll",
        {
          target_chat_id: route.chatId,
          question: checked.value.question,
          options: checked.value.options,
          multi: checked.value.multi,
          duration_hours: checked.value.durationHours,
          anonymous: checked.value.anonymous,
        },
        created,
      );
    }
    case "list_members":
      return call(
        "bot_api_list_members",
        {
          target_chat_id: route.chatId,
          max_count: route.limit,
          after_user: route.after,
        },
        (data) => json(data),
      );
    case "get_member":
      return call(
        "bot_api_get_member",
        { target_chat_id: route.chatId, target_user_id: route.userId },
        (data) => json(data),
      );
    case "send_chat_file":
      return await sendFile(route.chatId, request, token, backend);
    case "respond_interaction": {
      const read = await readJson(request);
      if (!read.ok) return read.response;
      const checked = validateRespondBody(read.body);
      if (!checked.ok) return json({ error: checked.error }, 400);
      const type = checked.value.type;
      return call(
        "bot_api_respond",
        {
          target_interaction_id: route.interactionId,
          response: checked.value.response,
        },
        (data) => {
          // An ack shows nothing, so it has no id.
          if (type === "ack") return json({ ok: true });
          if (data === null || data === undefined) return created(data);
          // An update changes something that exists: 200, not 201.
          return type === "update" ? json({ id: data }) : created(data);
        },
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

  const backend: Backend = {
    rpc: (name, params) =>
      admin.rpc(name, params) as unknown as ReturnType<Rpc>,
    upload: async (path, bytes, contentType) => {
      const { error } = await admin.storage.from("chat-files").upload(
        path,
        bytes,
        { contentType, upsert: false },
      );
      return error ? error.message : null;
    },
    remove: async (bucket, paths) => {
      try {
        await admin.storage.from(bucket).remove(paths);
      } catch (error) {
        console.error("bot file removal failed", String(error));
      }
    },
  };

  const response = await handle(matched.route, request, token, backend);

  // The developer page shows the latest calls: the method, the endpoint as a
  // template and the status, never an id or a text. An unknown token leaves no
  // trace (the database function checks it).
  const logging = (async () => {
    try {
      await admin.rpc("bot_api_log_call", {
        bot_token: token,
        call_method: request.method.toUpperCase(),
        call_route: routeTemplate(matched.route),
        call_status: response.status,
      });
    } catch (error) {
      console.error("bot call log failed", String(error));
    }
  })();
  const runtime = (globalThis as {
    EdgeRuntime?: { waitUntil?: (promise: Promise<unknown>) => void };
  }).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(logging);
  } else {
    await logging;
  }
  return response;
});
