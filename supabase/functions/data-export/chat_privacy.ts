// Advanced chat privacy (roadmap G6) in the data export: what a restricted
// chat leaves out of the archive. No network here.
//
// The export holds the messages the person sent. In a chat that has advanced
// chat privacy on, the words and files stay in the chat: the archive keeps the
// fact that a message was sent and when (so counts and dates are right) and
// says why the rest is missing. The person can turn the chat's restriction off
// (in a group an admin does) and take a new export if they want the text.

import type { ExportMessage } from "./export_builder.ts";

/** A message of a restricted chat: its text and file removed, marked. */
export function withholdMessage(message: ExportMessage): ExportMessage {
  return { ...message, body: "", attachment: null, withheld: true };
}

/**
 * [messages] with the ones in [restricted] chats withheld. Messages the
 * person already deleted carry no text anyway and are left as they are.
 */
export function withholdRestricted(
  messages: ExportMessage[],
  restricted: ReadonlySet<string>,
): ExportMessage[] {
  if (restricted.size === 0) return messages;
  return messages.map((message) =>
    restricted.has(message.conversationId) && message.recalledAt === null
      ? withholdMessage(message)
      : message
  );
}

/** Whether [error] says the database function is not there (yet). */
export function isMissingFunction(error: unknown): boolean {
  if (typeof error !== "object" || error === null) return false;
  const code = (error as { code?: unknown }).code;
  return code === "PGRST202" || code === "42883";
}
