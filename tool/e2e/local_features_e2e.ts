// End-to-end checks of WeCord features against the LOCAL Supabase stack:
// real Auth (GoTrue), PostgREST, Postgres triggers/RLS and Edge Functions.
// Everything is called the way the app calls it (as signed-in users
// through supabase-js); the service role only creates and deletes the test
// users and circles, reads rows to verify, and calls what only the server
// calls (claim_push_delivery, as the push function does).
//
// Run from the repo root with the local stack up and the functions served:
//   supabase start
//   supabase functions serve        # in another terminal
//   deno run -A tool/e2e/local_features_e2e.ts
//
// Keys come from `supabase status -o env` (local development keys), or
// from SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY. It
// refuses to run against anything but 127.0.0.1 / localhost. Everything it
// creates (users, circles, profiles, storage objects) is removed at the
// end; auth audit log rows of its users are removed with psql when
// available (DB_URL, the local database).
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

// ---------------------------------------------------------------- setup

function localEnv(): Record<string, string> {
  const env: Record<string, string> = {};
  try {
    const out = new Deno.Command("supabase", {
      args: ["status", "-o", "env"],
      stderr: "null",
    }).outputSync();
    for (const line of new TextDecoder().decode(out.stdout).split("\n")) {
      const match = /^([A-Z_]+)="(.*)"$/.exec(line.trim());
      if (match) env[match[1]] = match[2];
    }
  } catch {
    // Fall back to the environment below.
  }
  return env;
}

const status = localEnv();
const apiUrl = Deno.env.get("SUPABASE_URL") ?? status.API_URL;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? status.ANON_KEY;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  status.SERVICE_ROLE_KEY;
const dbUrl = Deno.env.get("DB_URL") ?? status.DB_URL;
if (!apiUrl || !anonKey || !serviceKey) {
  console.error("Local Supabase keys not found; is `supabase start` up?");
  Deno.exit(2);
}
if (!/^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(apiUrl)) {
  console.error(`Refusing to run against ${apiUrl}: local stack only.`);
  Deno.exit(2);
}
const functionsUrl = `${apiUrl}/functions/v1`;

const clientOptions = {
  auth: { persistSession: false, autoRefreshToken: false },
} as const;
const admin = createClient(apiUrl, serviceKey, clientOptions);

// ---------------------------------------------------------------- helpers

type DbError = { code?: string; message: string; details?: string | null };

class CheckError extends Error {}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new CheckError(message);
}

function describe(error: DbError | null | undefined): string {
  if (!error) return "no error";
  return `${error.code ?? "?"} ${error.message}${
    error.details ? ` (${error.details})` : ""
  }`;
}

/// Calls an RPC and returns its data; throws on an error.
async function rpc<T = unknown>(
  client: SupabaseClient,
  name: string,
  params: Record<string, unknown> = {},
): Promise<T> {
  const { data, error } = await client.rpc(name, params);
  if (error) throw new CheckError(`${name}: ${describe(error)}`);
  return data as T;
}

/// Calls an RPC that must fail; returns its error.
async function rpcError(
  client: SupabaseClient,
  name: string,
  params: Record<string, unknown> = {},
): Promise<DbError> {
  const { error } = await client.rpc(name, params);
  if (!error) throw new CheckError(`${name} unexpectedly succeeded`);
  return error;
}

function random(length = 8): string {
  return crypto.randomUUID().replace(/-/g, "").slice(0, length);
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

type User = {
  id: string;
  email: string;
  password: string;
  name: string;
  client: SupabaseClient;
  accessToken: string;
};

const created = {
  users: [] as string[],
  circles: [] as string[],
  storage: [] as { bucket: string; path: string }[],
};

/// A confirmed user signed in with a password, with the profile the app's
/// bootstrap inserts after sign-up.
async function newUser(label: string): Promise<User> {
  const email = `e2e-${random()}@example.test`;
  const password = `E2e-${random(16)}`;
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error || !data.user) throw new Error(`createUser: ${error?.message}`);
  created.users.push(data.user.id);
  const client = createClient(apiUrl, anonKey, clientOptions);
  const { data: signedIn, error: signInError } = await client.auth
    .signInWithPassword({ email, password });
  if (signInError || !signedIn.session) {
    throw new Error(`signIn: ${signInError?.message}`);
  }
  const name = `E2E ${label}`;
  const { error: profileError } = await client.from("profiles").insert({
    id: data.user.id,
    username: `e2e_${random(10)}`,
    display_name: name,
    bio: "",
  });
  if (profileError) throw new Error(`profile: ${describe(profileError)}`);
  return {
    id: data.user.id,
    email,
    password,
    name,
    client,
    accessToken: signedIn.session.access_token,
  };
}

type Channel = {
  id: string;
  name: string;
  kind: string;
  conversation_id: string;
  category_id: string | null;
};

type Detail = {
  channels: Channel[];
  categories: { id: string; name: string }[];
  roles: {
    id: string;
    name: string;
    is_default: boolean;
    permissions: number;
  }[];
  members: { profile: { id: string } }[];
};

async function circleDetail(user: User, circleId: string): Promise<Detail> {
  return await rpc<Detail>(user.client, "get_circle_detail", {
    target_circle_id: circleId,
  });
}

async function createCircle(user: User, name: string): Promise<string> {
  const id = await rpc<string>(user.client, "create_circle", {
    circle_name: name,
    member_ids: [],
  });
  created.circles.push(id);
  return id;
}

function channelNamed(detail: Detail, name: string, kind?: string): Channel {
  const channel = detail.channels.find((c) =>
    c.name === name && (kind === undefined || c.kind === kind)
  );
  assert(channel, `channel ${name} not found`);
  return channel;
}

/// Sends text the way the app does without mentions: a REST insert that
/// returns the id, or null when AutoMod dropped the row quietly.
async function insertText(
  user: User,
  conversationId: string,
  body: string,
): Promise<{ id: string | null; error: DbError | null }> {
  const { data, error } = await user.client.from("messages").insert({
    conversation_id: conversationId,
    sender_id: user.id,
    type: "text",
    body,
  }).select("id");
  if (error) return { id: null, error };
  return { id: data.length === 0 ? null : data[0].id as string, error: null };
}

async function sendText(
  user: User,
  conversationId: string,
  body: string,
): Promise<string> {
  const { id, error } = await insertText(user, conversationId, body);
  if (error) throw new CheckError(`send: ${describe(error)}`);
  assert(id, "send returned no row");
  return id;
}

async function callFunction(
  name: string,
  init: { method?: string; headers?: Record<string, string>; body?: unknown },
  // deno-lint-ignore no-explicit-any
): Promise<{ status: number; body: any }> {
  const response = await fetch(`${functionsUrl}/${name}`, {
    method: init.method ?? "GET",
    headers: {
      ...(init.body !== undefined
        ? { "Content-Type": "application/json" }
        : {}),
      ...init.headers,
    },
    body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
  });
  const text = await response.text();
  let body: unknown = text;
  try {
    body = text === "" ? null : JSON.parse(text);
  } catch {
    // Keep the text.
  }
  return { status: response.status, body };
}

async function auditActions(user: User, circleId: string): Promise<string[]> {
  const rows = await rpc<{ action: string }[]>(
    user.client,
    "list_circle_audit_log",
    { target_circle_id: circleId, before: null, limit_count: 100 },
  );
  return rows.map((row) => row.action);
}

async function botAccountCount(): Promise<number> {
  let count = 0;
  for (let page = 1;; page++) {
    const { data, error } = await admin.auth.admin.listUsers({
      page,
      perPage: 1000,
    });
    if (error) throw new Error(`listUsers: ${error.message}`);
    count += data.users.filter((u) => u.app_metadata?.provider === "bot")
      .length;
    if (data.users.length < 1000) return count;
  }
}

// RFC 6238 TOTP: HMAC-SHA1, 30 second steps, 6 digits.
function base32Decode(input: string): Uint8Array<ArrayBuffer> {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  const clean = input.toUpperCase().replace(/=+$/, "").replace(/\s/g, "");
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const char of clean) {
    const index = alphabet.indexOf(char);
    if (index === -1) throw new Error(`bad base32 character ${char}`);
    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return new Uint8Array(out);
}

async function totp(secret: string, at = Date.now()): Promise<string> {
  const counter = Math.floor(at / 1000 / 30);
  const message = new Uint8Array(8);
  new DataView(message.buffer).setBigUint64(0, BigInt(counter));
  const key = await crypto.subtle.importKey(
    "raw",
    base32Decode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, message));
  const offset = mac[mac.length - 1] & 0x0f;
  const binary = ((mac[offset] & 0x7f) << 24) | (mac[offset + 1] << 16) |
    (mac[offset + 2] << 8) | mac[offset + 3];
  return String(binary % 1_000_000).padStart(6, "0");
}

/// A tiny valid WAV: 0.1 s of 8 kHz 8-bit mono silence.
function tinyWav(): Uint8Array {
  const samples = 800;
  const buffer = new ArrayBuffer(44 + samples);
  const view = new DataView(buffer);
  const ascii = (offset: number, text: string) => {
    for (let i = 0; i < text.length; i++) {
      view.setUint8(offset + i, text.charCodeAt(i));
    }
  };
  ascii(0, "RIFF");
  view.setUint32(4, 36 + samples, true);
  ascii(8, "WAVE");
  ascii(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, 8000, true);
  view.setUint32(28, 8000, true);
  view.setUint16(32, 1, true);
  view.setUint16(34, 8, true);
  ascii(36, "data");
  view.setUint32(40, samples, true);
  new Uint8Array(buffer, 44).fill(128);
  return new Uint8Array(buffer);
}

// ---------------------------------------------------------------- checks

type Result = { name: string; ok: boolean; reason: string };
const results: Result[] = [];

async function check(name: string, run: () => Promise<string>) {
  const started = Date.now();
  try {
    const reason = await run();
    results.push({ name, ok: true, reason });
    console.log(`PASS  ${name} — ${reason} (${Date.now() - started} ms)`);
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    results.push({ name, ok: false, reason });
    console.log(`FAIL  ${name} — ${reason}`);
    if (!(error instanceof CheckError) && error instanceof Error) {
      console.log(error.stack);
    }
  }
}

// Shared state, filled in as the checks go.
let a: User;
let b: User;
let c: User;
let circleId = "";
let general: Channel;
let inviteCode = "";

async function main() {
  a = await newUser("Alice");
  b = await newUser("Bob");
  c = await newUser("Carol");

  circleId = await createCircle(a, `E2E circle ${random(4)}`);
  general = channelNamed(await circleDetail(a, circleId), "general", "text");
  inviteCode = await rpc<string>(a.client, "create_circle_invite", {
    target_circle_id: circleId,
    expires_in_hours: null,
    max_uses: null,
  });
  const joined = await rpc<string>(b.client, "accept_circle_invite", {
    invite_code: inviteCode,
  });
  assert(joined === circleId, "B joined another circle");

  await check("1. Bots: bots function + bot-api", checkBots);
  await check("2. AutoMod: keyword block/alert/timeout", checkAutoMod);
  await check(
    "3. Onboarding: rules gate sending and reacting",
    checkOnboarding,
  );
  await check(
    "4. Announcement channels: follow/publish/edit/delete",
    checkAnnouncements,
  );
  await check("5. Templates: create and use a template code", checkTemplates);
  await check("8a. Presence: DND skips push delivery", checkPresencePush);
  await check("8b. Mentions: @here and @role rows", checkMentions);
  await check("9a. Stage: start, hand raise, invite to speak", checkStage);
  await check("9b. Soundboard: upload, play, 2 s cooldown", checkSoundboard);
  await check(
    "6. Circle tags: display choice cleared on leave",
    checkCircleTags,
  );
  await check("7. Two-step verification (TOTP)", checkTwoFactor);
}

async function checkBots(): Promise<string> {
  const before = await botAccountCount();
  const createdBot = await callFunction("bots", {
    method: "POST",
    headers: { Authorization: `Bearer ${a.accessToken}`, apikey: anonKey },
    body: { circle_id: circleId, name: "E2E Bot" },
  });
  assert(
    createdBot.status === 200,
    `bots as manager: ${createdBot.status} ${JSON.stringify(createdBot.body)}`,
  );
  const token = createdBot.body.token as string;
  const botUserId = createdBot.body.user_id as string;
  assert(typeof token === "string" && token.length === 43, "no bot token");
  created.users.push(botUserId);

  const { data: botLogin, error: loginError } = await admin.auth.admin
    .getUserById(botUserId);
  assert(!loginError && botLogin.user, "bot auth user missing");
  const bannedUntil = Date.parse(
    (botLogin.user as { banned_until?: string }).banned_until ?? "",
  );
  assert(
    bannedUntil > Date.now() + 365 * 24 * 3600 * 1000,
    `bot login not banned (banned_until=${
      (botLogin.user as { banned_until?: string }).banned_until
    })`,
  );
  const { data: botProfile } = await admin.from("profiles").select("is_bot")
    .eq("id", botUserId).single();
  assert(botProfile?.is_bot === true, "bot profile missing is_bot");

  // A member without manage_circle: refused, and no login left behind.
  const refused = await callFunction("bots", {
    method: "POST",
    headers: { Authorization: `Bearer ${b.accessToken}`, apikey: anonKey },
    body: { circle_id: circleId, name: "Sneaky Bot" },
  });
  assert(refused.status === 403, `bots as member: ${refused.status}`);
  const after = await botAccountCount();
  assert(after === before + 1, `bot logins ${before} -> ${after} (orphan?)`);

  const bot = (path: string, method = "GET", body?: unknown, auth = token) =>
    callFunction(`bot-api/${path}`, {
      method,
      headers: { Authorization: `Bot ${auth}` },
      body,
    });

  const me = await bot("me");
  assert(me.status === 200, `GET /me: ${me.status} ${JSON.stringify(me.body)}`);
  const channels = await bot("channels");
  assert(channels.status === 200, `GET /channels: ${channels.status}`);
  const botChannel = (channels.body as { id: string; name: string }[]).find((
    ch,
  ) => ch.name === "general");
  assert(
    botChannel,
    `general not in /channels: ${JSON.stringify(channels.body)}`,
  );

  const posted = await bot(`channels/${botChannel.id}/messages`, "POST", {
    content: "Hello from the e2e bot",
  });
  assert(
    posted.status === 201 && posted.body.id,
    `POST message: ${posted.status} ${JSON.stringify(posted.body)}`,
  );
  const { data: botMessage } = await admin.from("messages").select(
    "sender_id, conversation_id",
  ).eq("id", posted.body.id).single();
  assert(
    botMessage?.sender_id === botUserId &&
      botMessage.conversation_id === general.conversation_id,
    "bot message not stored as the bot in general",
  );

  const reacted = await bot(
    `messages/${posted.body.id}/reactions/${encodeURIComponent("👍")}`,
    "PUT",
  );
  assert(reacted.status === 204, `PUT reaction: ${reacted.status}`);
  const { count: reactions } = await admin.from("message_reactions").select(
    "*",
    { count: "exact", head: true },
  ).eq("message_id", posted.body.id).eq("user_id", botUserId);
  assert(reactions === 1, `bot reaction rows: ${reactions}`);

  const commands = await bot("commands", "PUT", [
    { name: "ping", description: "Replies with pong" },
  ]);
  assert(
    commands.status === 200,
    `PUT /commands: ${commands.status} ${JSON.stringify(commands.body)}`,
  );
  const listed = await rpc<{ name: string }[]>(
    b.client,
    "list_circle_bot_commands",
    { target_circle_id: circleId },
  );
  assert(listed.some((cmd) => cmd.name === "ping"), "member can't see /ping");

  const invoked = await rpc<{ bot_name: string; command: string }>(
    b.client,
    "invoke_bot_command",
    {
      target_conversation_id: general.conversation_id,
      command_name: "ping",
      command_options: "loud",
    },
  );
  assert(invoked.command === "ping", `invoke: ${JSON.stringify(invoked)}`);

  const polled = await bot("interactions");
  assert(polled.status === 200, `GET /interactions: ${polled.status}`);
  const interaction = (polled.body as { id: string; command: string }[]).find(
    (i) => i.command === "ping",
  );
  assert(interaction, `no interaction: ${JSON.stringify(polled.body)}`);
  const answered = await bot(
    `interactions/${interaction.id}/respond`,
    "POST",
    { content: "pong" },
  );
  assert(
    answered.status === 201,
    `respond: ${answered.status} ${JSON.stringify(answered.body)}`,
  );
  const { data: reply } = await admin.from("messages").select(
    "body, interaction",
  ).eq("id", answered.body.id).single();
  assert(
    reply?.body === "pong" && reply.interaction?.command === "ping" &&
      reply.interaction?.user_id === b.id,
    `reply: ${JSON.stringify(reply)}`,
  );
  const again = await bot(
    `interactions/${interaction.id}/respond`,
    "POST",
    { content: "pong twice" },
  );
  assert(again.status >= 400, `second respond allowed: ${again.status}`);

  const wrong = await callFunction("bot-api/me", {
    headers: { Authorization: `Bot ${"A".repeat(43)}` },
  });
  assert(wrong.status === 401, `wrong token: ${wrong.status}`);
  const missing = await callFunction("bot-api/me", {});
  assert(missing.status === 401, `no token: ${missing.status}`);

  return "token issued, banned bot login + is_bot profile, member 403 without orphan, " +
    "me/channels/message/reaction/commands/interaction/respond OK, bad token 401";
}

async function checkAutoMod(): Promise<string> {
  const alerts = await rpc<string>(a.client, "create_circle_channel", {
    target_circle_id: circleId,
    channel_name: "mod-alerts",
  });
  const alertChannel = channelNamed(
    await circleDetail(a, circleId),
    "mod-alerts",
  );
  assert(alertChannel.id === alerts, "alert channel id mismatch");

  const ruleId = await rpc<string>(a.client, "save_circle_automod_rule", {
    target_circle_id: circleId,
    rule: {
      name: "E2E keywords",
      kind: "keyword",
      enabled: true,
      keywords: ["zorblax"],
      regex_patterns: [],
      mention_limit: null,
      message_limit: null,
      window_seconds: null,
      block_message: true,
      block_reason: "No zorblax here",
      alert_channel_id: alertChannel.id,
      timeout_seconds: 60,
      exempt_role_ids: [],
      exempt_channel_ids: [],
    },
  });
  const rules = await rpc<{ id: string }[]>(
    a.client,
    "list_circle_automod_rules",
    { target_circle_id: circleId },
  );
  assert(rules.some((r) => r.id === ruleId), "rule not listed");

  // REST insert, as the app sends plain text.
  const blocked = await insertText(
    b,
    general.conversation_id,
    "I say Zorblax!",
  );
  assert(!blocked.error, `blocked insert errored: ${describe(blocked.error)}`);
  assert(blocked.id === null, "blocked message was stored");
  const notice = await rpc<{ reason?: string } | null>(
    b.client,
    "take_automod_notice",
    { target_conversation_id: general.conversation_id },
  );
  assert(
    notice?.reason === "No zorblax here",
    `notice: ${JSON.stringify(notice)}`,
  );
  const second = await rpc(b.client, "take_automod_notice", {
    target_conversation_id: general.conversation_id,
  });
  assert(second === null, "notice was not taken once");

  const { count: stored } = await admin.from("messages").select("*", {
    count: "exact",
    head: true,
  }).eq("conversation_id", general.conversation_id).ilike("body", "%zorblax%");
  assert(stored === 0, `blocked text stored ${stored} times`);
  const { data: alertRows } = await admin.from("messages").select(
    "type, body, attachment",
  ).eq("conversation_id", alertChannel.conversation_id);
  assert(
    (alertRows ?? []).length === 1,
    `alert messages: ${JSON.stringify(alertRows)}`,
  );
  const { data: membership } = await admin.from("circle_members").select(
    "timed_out_until",
  ).eq("circle_id", circleId).eq("user_id", b.id).single();
  assert(
    membership?.timed_out_until &&
      Date.parse(membership.timed_out_until) > Date.now(),
    "member was not timed out",
  );
  const actions = await auditActions(a, circleId);
  for (
    const action of [
      "automod_rule_create",
      "automod_block",
      "automod_alert",
      "automod_timeout",
    ]
  ) {
    assert(
      actions.includes(action),
      `audit lacks ${action}: ${actions.join(",")}`,
    );
  }

  // Timed out: even a clean message is refused until the timeout ends.
  const whileTimedOut = await insertText(b, general.conversation_id, "hello?");
  assert(whileTimedOut.error, "timed-out member could send");
  await rpc(a.client, "timeout_circle_member", {
    target_circle_id: circleId,
    target_user_id: b.id,
    duration_seconds: 0,
  });

  // send_text_message (the app's path when there are mentions) too.
  const viaRpc = await rpc<string | null>(b.client, "send_text_message", {
    target_conversation_id: general.conversation_id,
    body: `@${a.name} zorblax`,
    reply_to_message_id: null,
    reply_preview: null,
    mentions: [{
      user_id: a.id,
      display_name: a.name,
      start: 0,
      end: a.name.length + 1,
      kind: "user",
    }],
  });
  assert(viaRpc === null, "send_text_message stored a blocked message");
  const rpcNotice = await rpc<{ reason?: string } | null>(
    b.client,
    "take_automod_notice",
    { target_conversation_id: general.conversation_id },
  );
  assert(rpcNotice?.reason === "No zorblax here", "no notice via RPC path");
  await rpc(a.client, "timeout_circle_member", {
    target_circle_id: circleId,
    target_user_id: b.id,
    duration_seconds: 0,
  });

  const clean = await insertText(b, general.conversation_id, "a clean message");
  assert(!clean.error && clean.id, `clean message: ${describe(clean.error)}`);

  // Keep later checks free of the timeout action.
  await rpc(a.client, "delete_circle_automod_rule", { target_rule_id: ruleId });
  return "REST insert + send_text_message blocked quietly, notice taken once, " +
    "1 alert, timeout + audit (block/alert/timeout), clean message sent";
}

async function checkOnboarding(): Promise<string> {
  await rpc(a.client, "set_circle_onboarding", {
    target_circle_id: circleId,
    is_enabled: true,
    rule_list: ["Be kind", "No spam"],
    welcome: "Welcome to the e2e circle!",
  });
  // B was already a member, so counts as having accepted.
  const bOnboarding = await rpc<Record<string, unknown>>(
    b.client,
    "get_circle_onboarding",
    { target_circle_id: circleId },
  );

  const joined = await rpc<string>(c.client, "accept_circle_invite", {
    invite_code: inviteCode,
  });
  assert(joined === circleId, "C joined another circle");
  const target = await sendText(a, general.conversation_id, "React to me");

  const refusedSend = await insertText(c, general.conversation_id, "hi all");
  assert(
    refusedSend.error?.code === "42501" &&
      refusedSend.error.details === "rules_not_accepted",
    `send before accepting: ${describe(refusedSend.error)}`,
  );
  const refusedReact = await rpcError(c.client, "toggle_message_reaction", {
    target_message_id: target,
    target_emoji: "👍",
  });
  assert(
    refusedReact.code === "42501",
    `react before accepting: ${describe(refusedReact)}`,
  );
  const bSend = await insertText(b, general.conversation_id, "old member here");
  assert(
    !bSend.error && bSend.id,
    `existing member blocked: ${describe(bSend.error)}`,
  );

  const accepted = await rpc<{ welcome_message?: string }>(
    c.client,
    "accept_circle_rules",
    { target_circle_id: circleId },
  );
  assert(
    accepted?.welcome_message === "Welcome to the e2e circle!",
    `accept: ${JSON.stringify(accepted)}`,
  );
  await sendText(c, general.conversation_id, "hi all, rules accepted");
  const reacted = await rpc<boolean>(c.client, "toggle_message_reaction", {
    target_message_id: target,
    target_emoji: "👍",
  });
  assert(reacted === true, "reaction after accepting not added");
  return `new member refused (42501 rules_not_accepted) for send + react, existing member unaffected` +
    ` (${
      JSON.stringify(Object.keys(bOnboarding ?? {}))
    }), accepted → welcome + send + react OK`;
}

async function checkAnnouncements(): Promise<string> {
  const newsId = await rpc<string>(a.client, "create_circle_channel", {
    target_circle_id: circleId,
    channel_name: "news",
  });
  await rpc(a.client, "set_channel_announcement", {
    target_channel_id: newsId,
    enabled: true,
  });
  const news = channelNamed(await circleDetail(a, circleId), "news");
  assert(news.kind === "announcement", `news kind: ${news.kind}`);

  const otherCircle = await createCircle(a, `E2E follower ${random(4)}`);
  const followerChannel = channelNamed(
    await circleDetail(a, otherCircle),
    "general",
    "text",
  );
  const targets = await rpc<{ channel_id: string }[]>(
    a.client,
    "list_follow_targets",
    { source_channel_id: newsId },
  );
  assert(
    targets.some((t) => t.channel_id === followerChannel.id),
    "follower channel not offered as a target",
  );
  await rpc(a.client, "follow_announcement_channel", {
    source_channel_id: newsId,
    target_channel_id: followerChannel.id,
  });
  const follows = await rpc<unknown[]>(a.client, "list_channel_follows", {
    target_channel_id: followerChannel.id,
  });
  assert(follows.length === 1, `follows: ${JSON.stringify(follows)}`);

  // A member cannot follow into a channel where they lack manage_webhooks.
  const memberFollow = await rpcError(b.client, "follow_announcement_channel", {
    source_channel_id: newsId,
    target_channel_id: general.id,
  });
  assert(
    memberFollow.code === "42501",
    `member follow: ${describe(memberFollow)}`,
  );

  const original = await sendText(a, news.conversation_id, "Big news today");
  const published = await rpc<number>(a.client, "publish_message", {
    target_message_id: original,
  });
  assert(published === 1, `published to ${published} channels`);
  const republish = await rpcError(a.client, "publish_message", {
    target_message_id: original,
  });

  const copies = async () => {
    const { data, error } = await a.client.from("messages").select(
      "id, body, crosspost, recalled_at",
    ).eq("conversation_id", followerChannel.conversation_id).not(
      "crosspost",
      "is",
      null,
    );
    if (error) throw new CheckError(`read copies: ${describe(error)}`);
    return data;
  };
  let copy = await copies();
  assert(
    copy.length === 1 && copy[0].body === "Big news today" &&
      copy[0].crosspost?.source_message_id === original,
    `copy: ${JSON.stringify(copy)}`,
  );

  await rpc(a.client, "edit_message", {
    target_message_id: original,
    body: "Big news today (edited)",
  });
  copy = await copies();
  assert(
    copy[0]?.body === "Big news today (edited)",
    `edit not propagated: ${JSON.stringify(copy)}`,
  );

  await rpc(a.client, "recall_message", { target_message_id: original });
  copy = await copies();
  assert(
    copy.length === 0 || copy.every((m) => m.recalled_at !== null),
    `delete not propagated: ${JSON.stringify(copy)}`,
  );
  return `published to 1 follower (republish refused: ${republish.code}), ` +
    "edit and delete propagated, member follow refused 42501";
}

async function checkTemplates(): Promise<string> {
  // Give the circle some layout worth copying.
  const categoryId = await rpc<string>(a.client, "create_channel_category", {
    target_circle_id: circleId,
    category_name: "Info",
  });
  await rpc(a.client, "create_circle_channel", {
    target_circle_id: circleId,
    channel_name: "rules",
    target_category_id: categoryId,
  });
  await rpc(a.client, "create_circle_role", {
    target_circle_id: circleId,
    role_name: "Helpers",
    role_color: 0x3366ff,
    role_permissions: 0,
    role_hoist: true,
  });

  const template = await rpc<{ code: string }>(
    a.client,
    "create_circle_template",
    {
      target_circle_id: circleId,
      template_name: "E2E template",
      template_description: "From the e2e script",
    },
  );
  assert(/^[a-z0-9]{10}$/.test(template.code), `code: ${template.code}`);
  const preview = await rpc<Record<string, unknown>>(
    c.client,
    "preview_circle_template",
    { template_code: template.code },
  );
  assert(preview, "preview empty");

  const newCircle = await rpc<string>(c.client, "create_circle_from_template", {
    template_code: template.code,
    circle_name: `E2E from template ${random(4)}`,
  });
  created.circles.push(newCircle);

  const source = await circleDetail(a, circleId);
  const copy = await circleDetail(c, newCircle);
  const layout = (detail: Detail) => {
    const categories = new Map(detail.categories.map((x) => [x.id, x.name]));
    return {
      categories: detail.categories.map((x) => x.name).sort(),
      channels: detail.channels.map((ch) =>
        `${
          ch.category_id ? categories.get(ch.category_id) : "-"
        }/${ch.name}:${ch.kind}`
      ).sort(),
      roles: detail.roles.map((r) =>
        `${r.is_default ? "@everyone" : r.name}:${r.permissions}`
      ).sort(),
    };
  };
  const expected = layout(source);
  const actual = layout(copy);
  const same = JSON.stringify(expected) === JSON.stringify(actual);
  assert(
    same,
    `layout differs:\n  source ${JSON.stringify(expected)}\n  copy   ${
      JSON.stringify(actual)
    }`,
  );
  return `code ${template.code}: ${actual.categories.length} categories, ` +
    `${actual.channels.length} channels, ${actual.roles.length} roles match`;
}

async function checkPresencePush(): Promise<string> {
  for (const user of [b, c]) {
    await rpc(user.client, "register_push_subscription", {
      target_endpoint: `https://push.example.test/e2e/${random(16)}`,
      target_p256dh:
        "BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4YfYCA_0QTpQtUbVlUls0VJXg7A8u-Ts1XbjhazAkj7I99e8QcYP7DkM",
      target_auth: "tBHItJI5svbpez7KI4CCXg",
      target_user_agent: "e2e",
    });
  }
  const status = await rpc<string>(b.client, "set_presence_status", {
    new_status: "dnd",
  });
  assert(status === "dnd", `status ${status}`);

  const claim = async (messageId: string) => {
    const { data, error } = await admin.rpc("claim_push_delivery", {
      target_message_id: messageId,
      caller_id: a.id,
    });
    if (error) throw new CheckError(`claim_push_delivery: ${describe(error)}`);
    const { data: subs } = await admin.from("push_subscriptions").select(
      "id, user_id",
    ).in(
      "id",
      (data as { subscription_id: string }[]).map((r) => r.subscription_id),
    );
    return new Set((subs ?? []).map((s) => s.user_id as string));
  };

  const first = await claim(
    await sendText(a, general.conversation_id, "ping everyone"),
  );
  assert(!first.has(b.id), "DND member would get a push");
  assert(
    first.has(c.id),
    `online member would not get a push (got ${[
      ...first,
    ]}; b=${b.id} c=${c.id})`,
  );

  await rpc(b.client, "set_presence_status", { new_status: "online" });
  const second = await claim(
    await sendText(a, general.conversation_id, "ping again"),
  );
  assert(second.has(b.id) && second.has(c.id), "online B not pushed");
  const again = await claim(await sendText(a, general.conversation_id, "x"));
  assert(again.size === 2, "unexpected recipients");

  // Members who can't see a private channel get no push from it.
  const staffId = await rpc<string>(a.client, "create_circle_channel", {
    target_circle_id: circleId,
    channel_name: "staff",
  });
  await rpc(a.client, "set_channel_privacy", {
    target_channel_id: staffId,
    private: true,
    read_only: false,
  });
  const staff = channelNamed(await circleDetail(a, circleId), "staff");
  const hidden = await claim(
    await sendText(a, staff.conversation_id, "secret"),
  );
  assert(hidden.size === 0, `private channel pushed to ${[...hidden]}`);

  return "DND member left out of claim_push_delivery, included again once online; " +
    "private channel not pushed to non-viewers";
}

async function checkMentions(): Promise<string> {
  const roleId = await rpc<string>(a.client, "create_circle_role", {
    target_circle_id: circleId,
    role_name: "Pingable",
    role_color: null,
    role_permissions: 0,
    role_hoist: false,
  });
  await rpc(a.client, "set_circle_role_mentionable", {
    target_role_id: roleId,
    is_mentionable: true,
  });
  await rpc(a.client, "set_member_roles", {
    target_circle_id: circleId,
    target_user_id: b.id,
    role_ids: [roleId],
  });

  // @here reaches members with a recent presence heartbeat (202610160038),
  // whatever list the sender sends: B has one, C doesn't. touch_presence
  // (202610160041) writes it in the app; the service role stands in here.
  await admin.from("presence_heartbeats").delete().in("user_id", [b.id, c.id]);
  const { error: heartbeatError } = await admin.from("presence_heartbeats")
    .upsert({ user_id: b.id, seen_at: new Date().toISOString() });
  assert(!heartbeatError, `heartbeat: ${describe(heartbeatError)}`);

  const body = "@here @Pingable meeting now";
  const messageId = await rpc<string>(a.client, "send_text_message", {
    target_conversation_id: general.conversation_id,
    body,
    reply_to_message_id: null,
    reply_preview: null,
    mentions: [
      {
        display_name: "here",
        start: 0,
        end: 5,
        kind: "here",
        user_ids: [b.id, c.id],
      },
      {
        display_name: "Pingable",
        start: 6,
        end: 15,
        kind: "role",
        role_id: roleId,
      },
    ],
  });
  assert(messageId, "mention message not sent");
  const { data: rows } = await admin.from("message_mentions").select(
    "user_id, kind",
  ).eq("message_id", messageId);
  const got = new Set((rows ?? []).map((r) => `${r.kind}:${r.user_id}`));
  const want = [`here:${b.id}`, `role:${b.id}`];
  for (const key of want) assert(got.has(key), `missing ${key}: ${[...got]}`);
  assert(
    !got.has(`here:${c.id}`),
    "@here reached a member the sender called online without a heartbeat",
  );
  assert(!got.has(`role:${c.id}`), "role mention reached a member without it");
  assert(
    !got.has(`here:${a.id}`) && !got.has(`role:${a.id}`),
    "sender mentioned",
  );

  // A member without mention_everyone: @here stays plain text.
  const plainId = await rpc<string>(c.client, "send_text_message", {
    target_conversation_id: general.conversation_id,
    body: "@here anyone?",
    reply_to_message_id: null,
    reply_preview: null,
    mentions: [{
      display_name: "here",
      start: 0,
      end: 5,
      kind: "here",
      user_ids: [a.id, b.id],
    }],
  });
  const { count: plainRows } = await admin.from("message_mentions").select(
    "*",
    {
      count: "exact",
      head: true,
    },
  ).eq("message_id", plainId);
  assert(plainRows === 0, `member @here created ${plainRows} rows`);
  return "@here → B (heartbeat) not C (only in the sender's list), " +
    "@Pingable → only B (kind role); member @here ignored";
}

let voiceChannelId = "";
let stageChannelId = "";

async function checkStage(): Promise<string> {
  stageChannelId = await rpc<string>(a.client, "create_circle_channel", {
    target_circle_id: circleId,
    channel_name: "Town hall",
    target_kind: "stage",
  });
  await rpc(a.client, "start_stage", {
    target_channel_id: stageChannelId,
    stage_topic: "E2E talk",
  });
  const stages = await rpc<unknown>(b.client, "list_stage_instances", {
    target_circle_id: circleId,
  });
  assert(
    JSON.stringify(stages).includes("E2E talk"),
    `stages: ${JSON.stringify(stages)}`,
  );

  await rpc(b.client, "join_voice_state", {
    target_channel_id: stageChannelId,
  });
  await rpc(c.client, "join_voice_state", {
    target_channel_id: stageChannelId,
  });
  await rpc(b.client, "set_stage_hand_raised", {
    target_channel_id: stageChannelId,
    raised: true,
  });
  const states = async () => {
    const all = await rpc<Record<string, unknown>[] | Record<string, unknown>>(
      a.client,
      "list_voice_states",
      { target_circle_id: circleId },
    );
    const list = Array.isArray(all) ? all : [];
    return new Map(list.map((s) => [s.user_id as string, s]));
  };
  let byUser = await states();
  assert(
    byUser.get(b.id)?.hand_raised_at,
    `hand not raised: ${JSON.stringify(byUser.get(b.id))}`,
  );

  // B member can't invite.
  const memberInvite = await rpcError(b.client, "invite_stage_speaker", {
    target_channel_id: stageChannelId,
    target_user_id: c.id,
  });

  const bSpeaking = await rpc<boolean>(a.client, "invite_stage_speaker", {
    target_channel_id: stageChannelId,
    target_user_id: b.id,
  });
  assert(bSpeaking === true, "raised hand was not made a speaker at once");
  const cSpeaking = await rpc<boolean>(a.client, "invite_stage_speaker", {
    target_channel_id: stageChannelId,
    target_user_id: c.id,
  });
  assert(cSpeaking === false, "C became a speaker without accepting");
  const accepted = await rpc<boolean>(c.client, "respond_stage_invite", {
    target_channel_id: stageChannelId,
    accept: true,
  });
  assert(accepted === true, "C's acceptance did not make them a speaker");
  byUser = await states();
  assert(
    byUser.get(b.id)?.stage_speaker === true &&
      byUser.get(c.id)?.stage_speaker === true,
    `speakers: ${JSON.stringify([...byUser.values()])}`,
  );
  await rpc(c.client, "set_stage_audience", {
    target_channel_id: stageChannelId,
    target_user_id: c.id,
  });
  byUser = await states();
  assert(byUser.get(c.id)?.stage_speaker === false, "C did not step down");

  const ended = await rpc<string[]>(a.client, "end_stage", {
    target_channel_id: stageChannelId,
  });
  await rpc(b.client, "leave_voice_state", {});
  await rpc(c.client, "leave_voice_state", {});
  return `stage live, hand raised → speaker, invite → accept → speaker, step down, ` +
    `member invite refused (${memberInvite.code}), ended (${
      ended?.length ?? 0
    } speakers)`;
}

async function checkSoundboard(): Promise<string> {
  const detail = await circleDetail(a, circleId);
  voiceChannelId = detail.channels.find((ch) => ch.kind === "voice")?.id ?? "";
  assert(voiceChannelId, "no voice channel");

  const path = `${circleId}/${crypto.randomUUID()}.wav`;
  const { error: uploadError } = await a.client.storage.from("circle-sounds")
    .upload(path, tinyWav(), { contentType: "audio/wav", upsert: false });
  assert(!uploadError, `upload: ${uploadError?.message}`);
  created.storage.push({ bucket: "circle-sounds", path });

  // A member without manage_emojis can't upload.
  const { error: memberUpload } = await b.client.storage.from("circle-sounds")
    .upload(`${circleId}/${crypto.randomUUID()}.wav`, tinyWav(), {
      contentType: "audio/wav",
    });
  assert(memberUpload, "member without manage_emojis could upload a sound");

  const sound = await rpc<{ id: string }>(a.client, "create_circle_sound", {
    target_circle_id: circleId,
    sound_name: "e2e beep",
    sound_emoji: null,
    storage_path: path,
    mime_type: "audio/wav",
    duration_ms: 100,
  });
  assert(sound?.id, "no sound row");

  // Not connected: refused.
  const notConnected = await rpcError(b.client, "play_soundboard_sound", {
    target_channel_id: voiceChannelId,
    target_sound_id: sound.id,
  });
  assert(
    notConnected.code === "42501",
    `unconnected play: ${describe(notConnected)}`,
  );

  await rpc(b.client, "join_voice_state", {
    target_channel_id: voiceChannelId,
  });
  const play = () =>
    b.client.rpc("play_soundboard_sound", {
      target_channel_id: voiceChannelId,
      target_sound_id: sound.id,
    });
  const first = await play();
  assert(!first.error && first.data, `first play: ${describe(first.error)}`);
  const second = await play();
  assert(
    second.error?.code === "P0001" &&
      (second.error.details ?? "").startsWith("soundboard_cooldown_ms="),
    `second play within 2 s: ${describe(second.error)}`,
  );
  await sleep(2100);
  const third = await play();
  assert(!third.error, `play after cooldown: ${describe(third.error)}`);
  await rpc(b.client, "leave_voice_state", {});
  return `wav uploaded + sound created, unconnected 42501, play OK, ` +
    `immediate replay refused (${second.error!.details}), OK after 2.1 s`;
}

async function checkCircleTags(): Promise<string> {
  const tag = await rpc<Record<string, unknown>>(a.client, "set_circle_tag", {
    target_circle_id: circleId,
    circle_tag: "E2E",
    badge: "star",
  });
  assert(tag, "tag not set");
  const tagCircles = await rpc<{ circle_id?: string; id?: string }[]>(
    b.client,
    "list_tag_circles",
  );
  assert(
    JSON.stringify(tagCircles).includes(circleId),
    `list_tag_circles: ${JSON.stringify(tagCircles)}`,
  );
  await rpc(b.client, "set_display_circle_tag", { target_circle_id: circleId });
  const badges = await rpc<{ user_id: string; tag?: string }[]>(
    c.client,
    "list_profile_badges",
    { user_ids: [b.id] },
  );
  assert(
    JSON.stringify(badges).includes("E2E"),
    `others don't see B's tag: ${JSON.stringify(badges)}`,
  );
  // Non-members cannot show the tag.
  const outsider = await newUser("Outsider");
  const refused = await rpcError(outsider.client, "set_display_circle_tag", {
    target_circle_id: circleId,
  });

  await rpc(b.client, "leave_circle", { target_circle_id: circleId });
  const { data: profile } = await admin.from("profiles").select(
    "display_circle_tag_id",
  ).eq("id", b.id).single();
  assert(
    profile && profile.display_circle_tag_id === null,
    `choice not cleared: ${JSON.stringify(profile)}`,
  );
  return `tag set, B shows it (seen by others), outsider refused (${refused.code}), cleared after B left`;
}

async function checkTwoFactor(): Promise<string> {
  const session = createClient(apiUrl, anonKey, clientOptions);
  const { error: signInError } = await session.auth.signInWithPassword({
    email: a.email,
    password: a.password,
  });
  assert(!signInError, `sign in: ${signInError?.message}`);
  const { data: enrolled, error: enrollError } = await session.auth.mfa.enroll({
    factorType: "totp",
    issuer: "WeCord",
    friendlyName: "Authenticator app",
  });
  assert(!enrollError && enrolled, `enroll: ${enrollError?.message}`);
  const secret = enrolled.totp.secret;

  const verify = async (client: SupabaseClient) => {
    // Avoid a code about to roll over.
    if (Date.now() / 1000 % 30 > 27) await sleep(3500);
    const { data: challenge, error: challengeError } = await client.auth.mfa
      .challenge({ factorId: enrolled.id });
    assert(
      !challengeError && challenge,
      `challenge: ${challengeError?.message}`,
    );
    const { error } = await client.auth.mfa.verify({
      factorId: enrolled.id,
      challengeId: challenge.id,
      code: await totp(secret),
    });
    assert(!error, `verify: ${error?.message}`);
  };

  const wrong = await session.auth.mfa.challengeAndVerify({
    factorId: enrolled.id,
    code: (await totp(secret)) === "000000" ? "111111" : "000000",
  });
  assert(wrong.error, "a wrong code was accepted");

  await verify(session);
  const { data: level } = await session.auth.mfa
    .getAuthenticatorAssuranceLevel();
  assert(
    level?.currentLevel === "aal2",
    `after verify: ${JSON.stringify(level)}`,
  );

  const fresh = createClient(apiUrl, anonKey, clientOptions);
  await fresh.auth.signInWithPassword({ email: a.email, password: a.password });
  const { data: freshLevel } = await fresh.auth.mfa
    .getAuthenticatorAssuranceLevel();
  assert(
    freshLevel?.currentLevel === "aal1" && freshLevel.nextLevel === "aal2",
    `new sign-in: ${JSON.stringify(freshLevel)}`,
  );

  // An aal1 session cannot remove a verified factor.
  const weakUnenroll = await fresh.auth.mfa.unenroll({ factorId: enrolled.id });
  assert(weakUnenroll.error, "aal1 session removed the factor");

  // The app's disable: challenge + verify, then unenroll.
  await verify(fresh);
  const { error: unenrollError } = await fresh.auth.mfa.unenroll({
    factorId: enrolled.id,
  });
  assert(!unenrollError, `unenroll: ${unenrollError?.message}`);
  const { data: factors } = await fresh.auth.mfa.listFactors();
  assert((factors?.all ?? []).length === 0, "factor still listed");
  await session.auth.signOut();
  await fresh.auth.signOut();
  return "enroll → challenge/verify → aal2; new sign-in aal1→aal2; wrong code and aal1 unenroll refused; unenroll OK";
}

// ---------------------------------------------------------------- cleanup

async function cleanup() {
  const problems: string[] = [];
  for (const item of created.storage) {
    const { error } = await admin.storage.from(item.bucket).remove([item.path]);
    if (error) problems.push(`storage ${item.path}: ${error.message}`);
  }
  // Circle conversations outlive their channels' rows, so collect them.
  const conversationIds: string[] = [];
  for (const id of created.circles) {
    const { data } = await admin.from("circle_channels").select(
      "conversation_id",
    ).eq("circle_id", id);
    for (const row of data ?? []) conversationIds.push(row.conversation_id);
  }
  // Clips the soundboard put in the circles' folders.
  for (const id of created.circles) {
    const { data } = await admin.storage.from("circle-sounds").list(id);
    if (data && data.length > 0) {
      await admin.storage.from("circle-sounds").remove(
        data.map((f) => `${id}/${f.name}`),
      );
    }
  }
  if (created.circles.length > 0) {
    const { error } = await admin.from("circles").delete().in(
      "id",
      created.circles,
    );
    if (error) problems.push(`circles: ${describe(error)}`);
  }
  if (conversationIds.length > 0) {
    const { error } = await admin.from("conversations").delete().in(
      "id",
      conversationIds,
    );
    if (error) problems.push(`conversations: ${describe(error)}`);
  }
  if (created.users.length > 0) {
    const { error } = await admin.from("profiles").delete().in(
      "id",
      created.users,
    );
    if (error) problems.push(`profiles: ${describe(error)}`);
  }
  for (const id of created.users) {
    const { error } = await admin.auth.admin.deleteUser(id);
    if (error) problems.push(`user ${id}: ${error.message}`);
  }
  if (dbUrl && created.users.length > 0) {
    // GoTrue's own audit log of the test logins.
    const ids = created.users.map((id) => `'${id}'`).join(",");
    const sql = `delete from auth.audit_log_entries
      where payload->>'actor_id' in (${ids})
         or payload->'traits'->>'user_id' in (${ids})
         or payload->>'actor_username' like 'e2e-%@example.test'
         or payload->'traits'->>'user_email' like 'e2e-%@example.test'
         or payload->'traits'->>'user_email' like 'bot-%@bots.wecord.invalid'`;
    try {
      const out = await new Deno.Command("psql", {
        args: [dbUrl, "-qAt", "-c", sql],
        stdout: "null",
        stderr: "piped",
      }).output();
      if (!out.success) {
        problems.push(`audit log: ${new TextDecoder().decode(out.stderr)}`);
      }
    } catch {
      // psql isn't installed; the audit rows stay.
    }
  }
  if (problems.length > 0) {
    console.log(`Cleanup problems:\n  ${problems.join("\n  ")}`);
  } else {
    console.log(
      `Cleaned up ${created.circles.length} circles, ${created.users.length} users.`,
    );
  }
}

try {
  await main();
} catch (error) {
  console.log(`Setup failed: ${error instanceof Error ? error.stack : error}`);
  results.push({ name: "setup", ok: false, reason: String(error) });
} finally {
  await cleanup();
}

console.log("\nSummary");
for (const result of results) {
  console.log(`  ${result.ok ? "PASS" : "FAIL"}  ${result.name}`);
}
const failed = results.filter((r) => !r.ok).length;
console.log(`${results.length - failed} passed, ${failed} failed`);
Deno.exit(failed === 0 ? 0 : 1);
