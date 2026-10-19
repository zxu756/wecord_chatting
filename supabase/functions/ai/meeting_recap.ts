// The `meeting_recap` action (roadmap E1): the minutes of a call whose
// captions were on - the key points, the decisions and the to-dos - from the
// sentences the people in it chose to share.
//
// Where the words come from: each person's own device recognized their own
// microphone and sent the sentences to the room as text; the person who
// turned captions on holds the transcript in memory and sends it here when
// they ask for a recap. Only people who agreed to share their captions are in
// it (their devices never sent anything otherwise). Nothing is recorded or
// stored: this function answers and forgets, and counts only the request in
// the day's usage.
//
// What it checks, before anything is sent to the model:
//  * the conversation's circle may have turned AI off (ai_disabled_in_circle)
//    and the person may have turned AI off for themselves
//    (ai_disabled_for_user);
//  * the caller is a member of the conversation (the member list is read as
//    the caller; a conversation they are not in is "not found");
//  * every call that reaches the model counts against the person's daily
//    limit (AI_DAILY_LIMIT_PER_USER, shared with the other AI features) and
//    is given back when the model fails.
//
// Names come from the database, never from the app: a sentence carries the
// speaker's user id, and the function writes the member's own name in front
// of it ("Someone" for an id that is no member). The transcript is untrusted
// data - people say anything, and speech recognition mishears - so it is
// cleaned of control characters and of the prompts' own fence tags, put
// between <transcript> tags, and the system prompt says to ignore
// instructions inside it (DATA_RULES).
//
// The answer is JSON: {title, summary: [...], decisions: [...], action_items:
// [...]}. Each to-do has the shape of extract_actions (F4): an assignee that
// is a member of the conversation or nothing, a due date resolved in the
// caller's time zone, task or event - so the app opens the same review sheet
// for them. Everything is cut to a sensible size.
//
// A transcript longer than AI_MAX_INPUT_CHARS keeps its beginning and its end
// (the middle is left out and `truncated` says so).

import type { AiConfig } from "./config.ts";
import type { AiDeps } from "./handler.ts";
import { cleanText } from "./chat.ts";
import {
  type ActionItem,
  type ConversationMember,
  extractJson,
  ITEM_RULES,
  itemJson,
  localNowText,
  memberLines,
  normalizeItems,
  resolveZone,
} from "./extract_actions.ts";
import { type ChatMessage, DATA_RULES } from "./prompts.ts";
import { complete, ProviderError } from "./provider.ts";
import { LANGUAGES } from "./request.ts";
import type {
  MeetingRecapRequest,
  RecapEntry,
} from "./meeting_recap_request.ts";

const MAX_TITLE_CHARS = 80;
const MAX_POINTS = 8;
const MAX_DECISIONS = 10;
const MAX_POINT_CHARS = 300;

export interface MeetingRecapResult {
  status: number;
  body: Record<string, unknown>;
}

/// The tags this prompt fences data with, in addition to the ones chat.ts
/// neutralizes.
const TRANSCRIPT_TAGS = /<\s*\/?\s*(transcript|members|requester)\b/gi;

/// [text] cleaned like any untrusted content, and without this prompt's own
/// fence tags.
export function cleanForRecap(text: string): string {
  return cleanText(text).replace(
    TRANSCRIPT_TAGS,
    (match) => match.replace("<", "< "),
  );
}

/// "m:ss" (or "h:mm:ss") for [seconds].
export function clock(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const two = (value: number) => String(value).padStart(2, "0");
  return h > 0 ? `${h}:${two(m)}:${two(s)}` : `${m}:${two(s)}`;
}

/// The transcript as lines, oldest first, one per sentence: "[m:ss] Name:
/// text". Sentences by the same person that follow each other are joined
/// into one line, which keeps the transcript short and readable.
export function transcriptLines(
  entries: RecapEntry[],
  members: ConversationMember[],
): { lines: string[]; speakers: number } {
  const names = new Map<string, string>();
  for (const member of members) {
    const name = cleanForRecap(member.name).replace(/\s+/g, " ").trim();
    names.set(member.id.toLowerCase(), name || "Someone");
  }
  const lines: string[] = [];
  const speakers = new Set<string>();
  let lastSpeaker = "";
  let current: { stamp: string; name: string; text: string } | null = null;
  const flush = () => {
    if (current !== null) {
      lines.push(`${current.stamp}${current.name}: ${current.text}`);
      current = null;
    }
  };
  for (const entry of entries) {
    const text = cleanForRecap(entry.text).replace(/\s+/g, " ").trim();
    if (text === "") continue;
    const name = names.get(entry.speakerId) ?? "Someone";
    speakers.add(name === "Someone" ? entry.speakerId : name);
    if (current !== null && lastSpeaker === entry.speakerId) {
      // The same person went on: one line, not a line per breath.
      current.text = `${current.text} ${text}`;
      continue;
    }
    flush();
    lastSpeaker = entry.speakerId;
    current = {
      stamp: entry.atSeconds === null ? "" : `[${clock(entry.atSeconds)}] `,
      name,
      text,
    };
  }
  flush();
  return { lines, speakers: speakers.size };
}

/// [lines] numbered and cut to [maxChars], keeping the beginning and the end
/// when they do not all fit. [truncated] tells whether anything was left out.
export function fitLines(
  lines: string[],
  maxChars: number,
): { lines: string[]; truncated: boolean } {
  const cost = (line: string) => Array.from(line).length + 1;
  const total = lines.reduce((sum, line) => sum + cost(line), 0);
  if (total <= maxChars) {
    return { lines, truncated: false };
  }
  const headBudget = Math.floor(maxChars * 0.4);
  const tailBudget = maxChars - headBudget;
  const head: string[] = [];
  let used = 0;
  for (const line of lines) {
    if (used + cost(line) > headBudget) break;
    head.push(line);
    used += cost(line);
  }
  const tail: string[] = [];
  used = 0;
  for (let index = lines.length - 1; index >= head.length; index--) {
    if (used + cost(lines[index]) > tailBudget) break;
    tail.unshift(lines[index]);
    used += cost(lines[index]);
  }
  return { lines: [...head, ...tail], truncated: true };
}

/// The prompt for the minutes of a meeting.
export function meetingRecapPrompt(options: {
  lines: string[];
  members: ConversationMember[];
  nowText: string;
  language: MeetingRecapRequest["language"];
  truncated: boolean;
}): ChatMessage[] {
  const write = options.language === null
    ? "Write in the language most of the transcript is in."
    : `Write in ${LANGUAGES[options.language]}.`;
  const system =
    "You write the minutes of a voice call for the people who were in it. " +
    DATA_RULES +
    "The transcript was made by speech recognition on each person's own device, so words can be wrong, sentences can be cut, and some people may be missing from it. " +
    "Only write what the transcript supports: never invent facts, people, numbers, dates or decisions, and leave out what you are unsure about. " +
    "Use the names exactly as they appear. " + write + " " +
    "Reply with one JSON object and nothing else: " +
    '{"title": "<a short title for the meeting, at most 60 characters>", ' +
    '"summary": ["<one key point, one sentence>", ...], ' +
    '"decisions": ["<one thing the group decided, one sentence>", ...], ' +
    '"action_items": [ ... ]}. ' +
    `"summary" has 3 to ${MAX_POINTS} points (fewer if the call was short), in the order they came up. ` +
    `"decisions" lists only decisions that were actually made, at most ${MAX_DECISIONS}; an empty list is fine. ` +
    '"action_items" lists the things people agreed or were asked to do. ' +
    ITEM_RULES;
  const note = options.truncated
    ? "The transcript is long: a stretch in the middle is not included.\n"
    : "";
  const user = `Current date and time for the requester: ${options.nowText}\n` +
    `<members>\n${memberLines(options.members)}\n</members>\n${note}` +
    `<transcript>\n${
      options.lines.map((line, index) => `[${index + 1}] ${line}`).join("\n")
    }\n</transcript>\n` +
    'Each transcript line is "[number] [time] Name: what they said". Write the minutes as JSON.';
  return [
    { role: "system", content: system },
    { role: "user", content: user },
  ];
}

function clip(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  return Array.from(cleanText(value).replace(/\s+/g, " ").trim())
    .slice(0, max).join("");
}

function pointList(value: unknown, most: number): string[] {
  if (!Array.isArray(value)) return [];
  const points: string[] = [];
  const seen = new Set<string>();
  for (const entry of value) {
    const text = clip(
      typeof entry === "string" ? entry : "",
      MAX_POINT_CHARS,
    ).replace(/^[-*•]\s*/, "");
    if (text === "" || seen.has(text.toLowerCase())) continue;
    seen.add(text.toLowerCase());
    points.push(text);
    if (points.length >= most) break;
  }
  return points;
}

export interface ParsedRecap {
  title: string;
  summary: string[];
  decisions: string[];
  actionItems: ActionItem[];
}

/// The minutes in a model's [answer], or null when it is not JSON with at
/// least a summary or a to-do in it.
export function parseRecap(
  answer: string,
  ctx: {
    members: ConversationMember[];
    zone: string;
    nowMs: number;
  },
): ParsedRecap | null {
  const json = extractJson(answer);
  if (json === null || typeof json !== "object" || Array.isArray(json)) {
    return null;
  }
  const fields = json as Record<string, unknown>;
  const summary = pointList(fields.summary, MAX_POINTS);
  const decisions = pointList(fields.decisions, MAX_DECISIONS);
  const actionItems = normalizeItems(fields.action_items, {
    members: ctx.members,
    zone: ctx.zone,
    nowMs: ctx.nowMs,
    // There are no chat messages to point back to.
    sources: new Map(),
  });
  if (
    summary.length === 0 && decisions.length === 0 && actionItems.length === 0
  ) {
    return null;
  }
  return {
    title: clip(fields.title, MAX_TITLE_CHARS),
    summary,
    decisions,
    actionItems,
  };
}

/// The `meeting_recap` action for a signed-in person.
export async function runMeetingRecap(
  parsed: MeetingRecapRequest,
  userId: string,
  config: AiConfig,
  deps: AiDeps,
  nowMs: number = Date.now(),
): Promise<MeetingRecapResult> {
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
  // Read as the caller: a conversation they are not in has no members for
  // them, and does not exist as far as they can tell.
  const members = await store.loadMembers(userId, parsed.conversationId);
  if (!members.some((member) => member.id === userId)) {
    return { status: 404, body: { error: "conversation_not_found" } };
  }

  const { lines: all, speakers } = transcriptLines(parsed.entries, members);
  if (all.length === 0) {
    // Nothing to write about, and nothing to charge for.
    return {
      status: 200,
      body: {
        title: "",
        summary: [],
        decisions: [],
        action_items: [],
        truncated: false,
        line_count: 0,
        speaker_count: 0,
      },
    };
  }
  const fitted = fitLines(all, config.maxInputChars);
  const zone = resolveZone(parsed.timeZone, parsed.utcOffsetMinutes);

  const { allowed, used } = await deps.consume(userId, config.dailyLimit);
  if (!allowed) {
    return {
      status: 429,
      body: { error: "ai_limit_reached", limit: config.dailyLimit, used },
    };
  }
  try {
    const answer = await complete(config, {
      messages: meetingRecapPrompt({
        lines: fitted.lines,
        members,
        nowText: localNowText(nowMs, zone),
        language: parsed.language,
        truncated: fitted.truncated,
      }),
      maxTokens: 1_800,
      temperature: 0.2,
      conversationKey: parsed.conversationId,
      feature: "meeting_recap",
    }, deps.fetch);
    const recap = parseRecap(answer, { members, zone, nowMs });
    if (recap === null) {
      throw new ProviderError("failed");
    }
    return {
      status: 200,
      body: {
        title: recap.title,
        summary: recap.summary,
        decisions: recap.decisions,
        action_items: recap.actionItems.map(itemJson),
        truncated: fitted.truncated,
        line_count: fitted.lines.length,
        speaker_count: speakers,
      },
    };
  } catch (error) {
    await deps.refund(userId).catch(() => {});
    if (error instanceof ProviderError) {
      return error.kind === "busy"
        ? { status: 503, body: { error: "ai_busy" } }
        : { status: 502, body: { error: "ai_failed" } };
    }
    console.error("meeting_recap failed", String(error));
    return { status: 502, body: { error: "ai_failed" } };
  }
}
