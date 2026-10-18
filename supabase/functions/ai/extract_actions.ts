// The `extract_actions` action (roadmap F4): to-dos and events found in
// messages a person chose, as structured items they confirm in the app.
// The @WeCord AI assistant (assistant.ts) uses the same prompt pieces and the
// same item rules for "list the to-dos". No network or database of its own:
// the handler passes in everything (see ActionStore).
//
// What an item is: {title, assignee, due, due_has_time, due_text, kind,
// source_message_id}.
//  * assignee is a member's id and nothing else. The model is shown a numbered
//    list of the conversation's members and answers with a number; a number
//    outside the list, a name nobody has, an id that is not a member's, or a
//    name two members share all become null. Nobody who is not in the
//    conversation can be assigned, whatever the chat says or the model writes.
//  * due is the instant in UTC, resolved from a wall-clock date and time the
//    model writes in the REQUESTER's time zone ("2026-10-23T15:00" in
//    Asia/Shanghai is 07:00 UTC) with today's date given in that zone. A date
//    with no time of day has due_has_time false. due_text is the words of the
//    chat the date came from; the app runs its own time phrase parser
//    (lib/features/chats/time_tokens/time_phrase_parser.dart, the one behind
//    time tokens) over it and prefers that result, so both read "tomorrow 8pm"
//    the same way. A date more than a day in the past is dropped.
//  * kind is "task", or "event" when there is a gathering at a time; an event
//    with no usable time is a task.
// Messages that are recalled, expired, held by the AI guard or not text are
// never read, even if their ids are sent.

import type { AiConfig } from "./config.ts";
import { cleanText, messageLine, type SourceMessage } from "./chat.ts";
import type { AiDeps } from "./handler.ts";
import { type ChatMessage, DATA_RULES } from "./prompts.ts";
import { complete, ProviderError } from "./provider.ts";
import type { AiRequest } from "./request.ts";

/// Messages one request may carry.
export const MAX_EXTRACT_MESSAGES = 50;
/// Items one answer may hold.
export const MAX_ACTION_ITEMS = 20;
const MAX_TITLE_CHARS = 120;
const MAX_MEMBERS_IN_PROMPT = 200;

/// A member of the conversation, as the model is shown them.
export interface ConversationMember {
  id: string;
  name: string;
  username?: string | null;
}

export interface ActionItem {
  title: string;
  /// A conversation member's id, or null.
  assignee: string | null;
  /// ISO instant in UTC, or null.
  due: string | null;
  dueHasTime: boolean;
  /// The words the date came from, or null.
  dueText: string | null;
  kind: "task" | "event";
  /// A chosen message the item came from, or null.
  sourceMessageId: string | null;
}

/// A message read as the caller for extraction.
export interface ActionMessage extends SourceMessage {
  recalledAt: string | null;
  expiresAt: string | null;
  /// messages.review_state: null for an ordinary message.
  reviewState: string | null;
}

/// What extraction needs from the database (index.ts wires the real one).
export interface ActionStore {
  /// The person's copy of the "AI features" switch; null when never copied,
  /// which counts as on.
  aiEnabled: (userId: string) => Promise<boolean | null>;
  /// The messages with [ids] in [conversationId], read as the caller (row
  /// level security decides which exist).
  loadMessages: (
    userId: string,
    conversationId: string,
    ids: string[],
  ) => Promise<ActionMessage[]>;
  /// The conversation's members, read as the caller.
  loadMembers: (
    userId: string,
    conversationId: string,
  ) => Promise<ConversationMember[]>;
}

// ------------------------------------------------------------------ time zones

/// [zone] when the runtime knows it, else "UTC".
export function safeZone(zone: string | null | undefined): string {
  const name = zone?.trim();
  if (!name || !/^[A-Za-z0-9_+./-]{1,64}$/.test(name)) {
    return "UTC";
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: name });
    return name;
  } catch {
    return "UTC";
  }
}

const wallFormatters = new Map<string, Intl.DateTimeFormat>();

function wallFormatter(zone: string): Intl.DateTimeFormat {
  let formatter = wallFormatters.get(zone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: zone,
      hourCycle: "h23",
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
      weekday: "long",
    });
    wallFormatters.set(zone, formatter);
  }
  return formatter;
}

interface Wall {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  weekday: string;
}

function wallOf(epochMs: number, zone: string): Wall {
  const parts = wallFormatter(zone).formatToParts(new Date(epochMs));
  const get = (type: string) =>
    parts.find((part) => part.type === type)?.value ?? "";
  return {
    year: Number(get("year")),
    month: Number(get("month")),
    day: Number(get("day")),
    hour: Number(get("hour")) % 24,
    minute: Number(get("minute")),
    weekday: get("weekday"),
  };
}

/// The zone's offset from UTC at [epochMs], in milliseconds.
function offsetAt(epochMs: number, zone: string): number {
  const wall = wallOf(epochMs, zone);
  const asUtc = Date.UTC(
    wall.year,
    wall.month - 1,
    wall.day,
    wall.hour,
    wall.minute,
    0,
  );
  return asUtc - Math.floor(epochMs / 60_000) * 60_000;
}

/// The instant (ms) at which [zone]'s clock shows the given date and time.
export function wallToInstant(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  zone: string,
): number {
  const guess = Date.UTC(year, month - 1, day, hour, minute);
  let instant = guess - offsetAt(guess, zone);
  const corrected = guess - offsetAt(instant, zone);
  if (corrected !== instant) {
    instant = corrected;
  }
  return instant;
}

/// "2026-10-19 14:30 (Monday)" in [zone]: what the model is told "now" is.
export function localNowText(epochMs: number, zone: string): string {
  const wall = wallOf(epochMs, zone);
  const two = (value: number) => String(value).padStart(2, "0");
  return `${wall.year}-${two(wall.month)}-${two(wall.day)} ${two(wall.hour)}:${
    two(wall.minute)
  } (${wall.weekday}), time zone ${zone}`;
}

/// The model's date, "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM" (a space also
/// works), as a UTC instant in the requester's [zone]. Null when it is not a
/// real date or is more than a day before [nowMs].
export function parseDue(
  value: unknown,
  zone: string,
  nowMs: number,
): { due: string; hasTime: boolean } | null {
  if (typeof value !== "string") {
    return null;
  }
  const match = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::\d{2})?)?$/
    .exec(value.trim());
  if (!match) {
    return null;
  }
  const [year, month, day] = [match[1], match[2], match[3]].map(Number);
  const hasTime = match[4] !== undefined;
  const hour = hasTime ? Number(match[4]) : 9;
  const minute = hasTime ? Number(match[5]) : 0;
  if (
    year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 ||
    day > 31 || hour > 23 || minute > 59
  ) {
    return null;
  }
  const check = new Date(Date.UTC(year, month - 1, day));
  if (check.getUTCMonth() !== month - 1 || check.getUTCDate() !== day) {
    return null;
  }
  const instant = wallToInstant(year, month, day, hour, minute, zone);
  if (instant < nowMs - 24 * 3_600_000) {
    return null;
  }
  return { due: new Date(instant).toISOString(), hasTime };
}

// ------------------------------------------------------------------ the prompt

/// Tags the extraction and assistant prompts fence data with, in addition to
/// the ones chat.ts neutralizes.
const EXTRA_FENCE_TAGS =
  /<\s*\/?\s*(request|replied_message|members|chat_messages|requester)\b/gi;

/// [text] cleaned like any chat content, and without this module's own fence
/// tags.
export function cleanForPrompt(text: string): string {
  return cleanText(text).replace(
    EXTRA_FENCE_TAGS,
    (match) => match.replace("<", "< "),
  );
}

/// The member list as numbered lines.
export function memberLines(members: ConversationMember[]): string {
  return members.slice(0, MAX_MEMBERS_IN_PROMPT).map((member, index) => {
    const name = cleanForPrompt(member.name).replace(/\s+/g, " ").trim();
    const username = member.username
      ? ` (@${cleanForPrompt(member.username).trim()})`
      : "";
    return `${index + 1}. ${name || "Someone"}${username}`;
  }).join("\n");
}

/// The shape and rules of an item, shared by extract_actions and the
/// assistant's to-do lists.
export const ITEM_RULES =
  'Each item is {"title": "<what has to be done, at most 80 characters, in the language of the messages, no names of days or times in it>", ' +
  '"assignee": <the number of the member who has to do it, from the numbered member list, or null>, ' +
  '"due": "<YYYY-MM-DD or YYYY-MM-DDTHH:MM in the requester\'s time zone, or null>", ' +
  '"due_text": "<the words in the chat the date came from, or null>", ' +
  '"kind": "task" or "event", "source": <the number in brackets of the chat line it came from, or null>}. ' +
  "Rules: list only things people asked, agreed or promised to do (task), or a gathering, appointment or deadline at a time (event). Never invent items, people or dates. " +
  'Give an assignee only when the chat makes it clear: someone was asked by name, or said "I will" (then it is that line\'s sender), and that person is in the member list; otherwise null. Never write a name, only the number. ' +
  "Resolve relative dates (tomorrow, next Friday, the 25th) from the current date and time given; if a day has no time of day, give just the date. " +
  "If the chat gives no date, due is null. A deadline is a due date, not an event. " +
  "Skip jokes, questions nobody answered, and things already done. Merge duplicates. At most 20 items; an empty list is a good answer.";

/// The extraction prompt: [lines] are the chosen messages, numbered, oldest
/// first.
export function extractActionsPrompt(options: {
  lines: string[];
  members: ConversationMember[];
  nowText: string;
}): ChatMessage[] {
  const system =
    "You find to-dos and events in a group chat for one of its members. " +
    DATA_RULES +
    "Reply with one JSON object and nothing else: " +
    '{"items": [ ... ]}. ' + ITEM_RULES;
  const user = `Current date and time for the requester: ${options.nowText}\n` +
    `<members>\n${memberLines(options.members)}\n</members>\n` +
    `<chat_log>\n${options.lines.join("\n")}\n</chat_log>\n` +
    'Each chat line is "[number] Name: text". Extract the items from the chat log as JSON.';
  return [
    { role: "system", content: system },
    { role: "user", content: user },
  ];
}

// ------------------------------------------------------------------ the answer

/// The JSON in [answer]: bare, in a code fence, or inside other words.
export function extractJson(answer: string): unknown {
  const text = answer.trim();
  const candidates = [text];
  const fenced = /```(?:json)?\s*([\s\S]*?)```/i.exec(text);
  if (fenced) {
    candidates.push(fenced[1].trim());
  }
  const firstObject = text.indexOf("{");
  const lastObject = text.lastIndexOf("}");
  if (firstObject >= 0 && lastObject > firstObject) {
    candidates.push(text.slice(firstObject, lastObject + 1));
  }
  const firstArray = text.indexOf("[");
  const lastArray = text.lastIndexOf("]");
  if (firstArray >= 0 && lastArray > firstArray) {
    candidates.push(text.slice(firstArray, lastArray + 1));
  }
  for (const candidate of candidates) {
    try {
      return JSON.parse(candidate);
    } catch {
      // Try the next reading.
    }
  }
  return undefined;
}

/// The member [value] names: a number from the numbered list, or the exact
/// id, name or username of exactly one member. Null for anything else.
export function resolveAssignee(
  value: unknown,
  members: ConversationMember[],
): string | null {
  const listed = members.slice(0, MAX_MEMBERS_IN_PROMPT);
  if (typeof value === "number" && Number.isInteger(value)) {
    return listed[value - 1]?.id ?? null;
  }
  if (typeof value !== "string") {
    return null;
  }
  const text = value.trim().replace(/^@/, "");
  if (text === "") {
    return null;
  }
  if (/^\d{1,3}$/.test(text)) {
    return listed[Number(text) - 1]?.id ?? null;
  }
  const byId = listed.find((member) => member.id === text);
  if (byId) {
    return byId.id;
  }
  const lowered = text.toLowerCase();
  const matches = listed.filter((member) =>
    member.name.trim().toLowerCase() === lowered ||
    member.username?.trim().toLowerCase() === lowered
  );
  // Two people with the same name: better nobody than the wrong one.
  return matches.length === 1 ? matches[0].id : null;
}

export interface ItemContext {
  members: ConversationMember[];
  zone: string;
  nowMs: number;
  /// Chat line number -> message id, for "source".
  sources: Map<number, string>;
}

/// The items in [raw] (a list of the model's objects), checked. Anything
/// that is not an item is dropped; the result has at most MAX_ACTION_ITEMS.
export function normalizeItems(raw: unknown, ctx: ItemContext): ActionItem[] {
  if (!Array.isArray(raw)) {
    return [];
  }
  const items: ActionItem[] = [];
  const seen = new Set<string>();
  for (const entry of raw) {
    if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
      continue;
    }
    const fields = entry as Record<string, unknown>;
    const title = typeof fields.title === "string"
      ? Array.from(
        cleanText(fields.title).replace(/\s+/g, " ").trim(),
      ).slice(0, MAX_TITLE_CHARS).join("")
      : "";
    if (title === "") {
      continue;
    }
    const key = title.toLowerCase();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);

    const due = parseDue(fields.due, ctx.zone, ctx.nowMs);
    const dueText = typeof fields.due_text === "string" && due !== null
      ? Array.from(cleanText(fields.due_text).replace(/\s+/g, " ").trim())
        .slice(0, 60).join("") || null
      : null;
    let kind: "task" | "event" = fields.kind === "event" ? "event" : "task";
    if (kind === "event" && (due === null || !due.hasTime)) {
      kind = "task";
    }
    const source = typeof fields.source === "number"
      ? ctx.sources.get(fields.source) ?? null
      : null;
    items.push({
      title,
      assignee: resolveAssignee(fields.assignee, ctx.members),
      due: due?.due ?? null,
      dueHasTime: due?.hasTime ?? false,
      dueText,
      kind,
      sourceMessageId: source,
    });
    if (items.length >= MAX_ACTION_ITEMS) {
      break;
    }
  }
  return items;
}

/// The items of an extraction answer, or null when it is not JSON with a
/// list of items. `{"items": [...]}` and a bare list both count.
export function parseActionItems(
  answer: string,
  ctx: ItemContext,
): ActionItem[] | null {
  const json = extractJson(answer);
  const list = Array.isArray(json)
    ? json
    : json !== null && typeof json === "object"
    ? (json as Record<string, unknown>).items
    : undefined;
  if (!Array.isArray(list)) {
    return null;
  }
  return normalizeItems(list, ctx);
}

/// An item as the app reads it.
export function itemJson(item: ActionItem): Record<string, unknown> {
  return {
    title: item.title,
    assignee: item.assignee,
    due: item.due,
    due_has_time: item.dueHasTime,
    due_text: item.dueText,
    kind: item.kind,
    source_message_id: item.sourceMessageId,
  };
}

// ------------------------------------------------------------------ the action

export interface ExtractResult {
  status: number;
  body: Record<string, unknown>;
}

function usable(message: ActionMessage, now: number): boolean {
  return message.type === "text" && message.recalledAt === null &&
    message.reviewState === null &&
    (message.expiresAt === null || Date.parse(message.expiresAt) > now);
}

/// The numbered lines of [messages] (oldest first) that fit in [maxChars],
/// and which message each number stands for. When they do not all fit, the
/// oldest ones are left out (`keep: "newest"`, the assistant's chat log) or
/// the newest (`keep: "oldest"`, a person's own selection).
export function numberedLines<T extends SourceMessage>(
  messages: T[],
  maxChars: number,
  keep: "oldest" | "newest" = "oldest",
): { lines: string[]; sources: Map<number, string>; used: T[] } {
  const ordered = keep === "newest" ? [...messages].reverse() : messages;
  const chosen: { message: T; line: string }[] = [];
  let total = 0;
  for (const message of ordered) {
    const plain = messageLine(message);
    if (plain === null) {
      continue;
    }
    const line = cleanForPrompt(plain);
    // "[nn] " and the newline between lines.
    const cost = Array.from(line).length + 6;
    if (total + cost > maxChars) {
      break;
    }
    total += cost;
    chosen.push({ message, line });
  }
  if (keep === "newest") {
    chosen.reverse();
  }
  const sources = new Map<number, string>();
  const lines = chosen.map(({ message, line }, index) => {
    sources.set(index + 1, message.id);
    return `[${index + 1}] ${line}`;
  });
  return { lines, sources, used: chosen.map((entry) => entry.message) };
}

/// The `extract_actions` action for a signed-in person.
export async function runExtractActions(
  parsed: Extract<AiRequest, { action: "extract_actions" }>,
  userId: string,
  config: AiConfig,
  deps: AiDeps,
  nowMs: number = Date.now(),
): Promise<ExtractResult> {
  const store = deps.actions;
  if (!store) {
    return { status: 503, body: { error: "ai_not_configured" } };
  }
  // The circle's switch and the person's own come before anything is read.
  if (!(await deps.circleAllows(userId, parsed.conversationId))) {
    return { status: 403, body: { error: "ai_disabled_in_circle" } };
  }
  if ((await store.aiEnabled(userId)) === false) {
    return { status: 403, body: { error: "ai_disabled_for_user" } };
  }

  const loaded = await store.loadMessages(
    userId,
    parsed.conversationId,
    parsed.messageIds,
  );
  const asked = new Set(parsed.messageIds);
  const messages = loaded
    .filter((message) => asked.has(message.id) && usable(message, nowMs))
    .sort((a, b) =>
      a.createdAt === b.createdAt
        ? a.id.localeCompare(b.id)
        : a.createdAt.localeCompare(b.createdAt)
    );
  const { lines, sources } = numberedLines(messages, config.maxInputChars);
  if (lines.length === 0) {
    return { status: 200, body: { items: [], message_count: 0 } };
  }

  const members = await store.loadMembers(userId, parsed.conversationId);
  const zone = safeZone(parsed.timeZone);
  const ctx: ItemContext = { members, zone, nowMs, sources };

  const { allowed, used } = await deps.consume(userId, config.dailyLimit);
  if (!allowed) {
    return {
      status: 429,
      body: { error: "ai_limit_reached", limit: config.dailyLimit, used },
    };
  }
  try {
    const answer = await complete(config, {
      messages: extractActionsPrompt({
        lines,
        members,
        nowText: localNowText(nowMs, zone),
      }),
      maxTokens: 1_200,
      temperature: 0.1,
      conversationKey: parsed.conversationId,
      feature: "extract_actions",
    }, deps.fetch);
    const items = parseActionItems(answer, ctx);
    if (items === null) {
      throw new ProviderError("failed");
    }
    return {
      status: 200,
      body: { items: items.map(itemJson), message_count: lines.length },
    };
  } catch (error) {
    await deps.refund(userId).catch(() => {});
    if (error instanceof ProviderError) {
      return error.kind === "busy"
        ? { status: 503, body: { error: "ai_busy" } }
        : { status: 502, body: { error: "ai_failed" } };
    }
    console.error("extract_actions failed", String(error));
    return { status: 502, body: { error: "ai_failed" } };
  }
}
