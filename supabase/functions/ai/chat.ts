// Turns chat messages into the plain lines the model reads, and keeps
// them within the input limits. The chat is untrusted: it is cleaned so it
// cannot close the data block it sits in or pose as a chat template. No
// network.

/// The most one message contributes, so a single long post cannot crowd
/// out the rest.
export const MAX_MESSAGE_CHARS = 1_200;

export interface SourceMessage {
  id: string;
  /// Who wrote it, as shown in the app.
  sender: string;
  type: string;
  body: string;
  attachment?: Record<string, unknown> | null;
  webhookName?: string | null;
  createdAt: string;
}

// Control characters, zero-width and bidirectional formatting characters.
const CONTROL_CHARS = new RegExp(
  "[\\u0000-\\u0008\\u000b\\u000c\\u000e-\\u001f\\u007f-\\u009f" +
    "\\u200b-\\u200f\\u202a-\\u202e\\u2066-\\u2069\\ufeff]",
  "g",
);
/// Chat-template markers such as <|im_start|> or [INST].
const TEMPLATE_TOKENS = /<\|[^|>\n]{0,40}\|>|\[\/?INST\]|<<\/?SYS>>/gi;
/// The tags the prompts use to fence data.
const FENCE_TAGS =
  /<\s*\/?\s*(chat_log|text_to_process|source_text|system|assistant|user)\b/gi;

/// [text] without control and bidi characters, template tokens and the
/// prompts' own fence tags, so it stays data.
export function cleanText(text: string): string {
  return text
    .replace(CONTROL_CHARS, "")
    .replace(TEMPLATE_TOKENS, "")
    .replace(FENCE_TAGS, (match) => match.replace("<", "< "));
}

/// One line of [text]: newlines become a visible marker so a message
/// cannot start a line that looks like another sender's.
export function flattenText(text: string): string {
  return cleanText(text).replace(/\s*\n+\s*/g, " ⏎ ").replace(/[ \t]+/g, " ")
    .trim();
}

function clip(text: string, max: number): string {
  const chars = Array.from(text);
  return chars.length <= max ? text : `${chars.slice(0, max).join("")}…`;
}

/// What a message reads as in the log: its text, or a note for pictures,
/// files and the like.
export function describeMessage(message: SourceMessage): string {
  const body = flattenText(message.body ?? "");
  switch (message.type) {
    case "image":
      return body ? `[image] ${body}` : "[image]";
    case "file": {
      const name = typeof message.attachment?.name === "string"
        ? flattenText(message.attachment.name)
        : "";
      const note = name ? `[file: ${name}]` : "[file]";
      return body ? `${note} ${body}` : note;
    }
    case "voice":
      return "[voice message]";
    case "poll":
      return "[poll]";
    case "sticker":
      return "[sticker]";
    case "system":
      return body ? `[notice] ${body}` : "[notice]";
    default:
      return body;
  }
}

/// The log line for [message], or null for messages with nothing to say.
export function messageLine(message: SourceMessage): string | null {
  const text = clip(describeMessage(message), MAX_MESSAGE_CHARS);
  if (text === "") {
    return null;
  }
  const sender = message.webhookName
    ? `${flattenText(message.webhookName)} (bot)`
    : flattenText(message.sender);
  return `${clip(sender || "Someone", 60)}: ${text}`;
}

export interface Selection {
  /// Oldest first.
  lines: string[];
  /// Messages left out, the oldest ones.
  omitted: number;
}

/// The newest lines of [messages] (oldest first) that fit in [maxChars]
/// and [maxMessages]; older ones are dropped first.
export function selectNewest(
  messages: SourceMessage[],
  maxChars: number,
  maxMessages: number,
): Selection {
  const lines: string[] = [];
  let used = 0;
  let omitted = 0;
  for (let index = messages.length - 1; index >= 0; index--) {
    const line = messageLine(messages[index]);
    if (line === null) {
      continue;
    }
    // +1 for the newline between lines.
    const cost = Array.from(line).length + 1;
    if (lines.length >= maxMessages || used + cost > maxChars) {
      omitted = index + 1;
      break;
    }
    lines.push(line);
    used += cost;
  }
  lines.reverse();
  return { lines, omitted };
}
