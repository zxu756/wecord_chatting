// Builds the "Download my data" archive from what the data-export function
// collected: JSON files for programs, a readable HTML index and one page per
// conversation for people, in a ZIP. Pure functions, no network, so they are
// easy to test.
import { strToU8, zipSync } from "npm:fflate@0.8.2";

export const EXPORT_WINDOW_MS = 24 * 60 * 60 * 1000;
export const EXPORT_LIFETIME_MS = 7 * 24 * 60 * 60 * 1000;

export type Json = Record<string, unknown>;

export interface ExportUser {
  id: string;
  email: string | null;
  createdAt: string | null;
  lastSignInAt: string | null;
}

export interface ExportFriend {
  id: string;
  username: string;
  displayName: string;
  /** What the person calls them, if they set a remark. */
  remark: string | null;
  since: string | null;
}

export interface ExportConversation {
  id: string;
  /** direct, group, channel or thread. */
  kind: string;
  /** The group's or channel's name; the other person's for direct chats. */
  name: string;
  circleName: string | null;
  joinedAt: string | null;
  role: string | null;
  createdAt: string | null;
}

export interface ExportMessage {
  id: string;
  conversationId: string;
  type: string;
  body: string;
  attachment: Json | null;
  createdAt: string;
  editedAt: string | null;
  recalledAt: string | null;
}

export interface ExportCircle {
  id: string;
  name: string;
  joinedAt: string | null;
  nickname: string | null;
  notificationLevel: string | null;
}

export interface ExportData {
  generatedAt: string;
  user: ExportUser;
  profile: Json | null;
  /** Privacy and notification settings, by name. */
  settings: Record<string, unknown>;
  friends: ExportFriend[];
  friendRequests: Json[];
  blocked: Json[];
  conversations: ExportConversation[];
  messages: ExportMessage[];
  circles: ExportCircle[];
  /** Signed links to the files in messages, by `bucket/path`. */
  attachmentLinks: Record<string, string>;
  /** When the links stop working. */
  linksExpireAt: string;
  /** Parts that could not be read, named. */
  skipped: string[];
}

export interface ExportAttachment {
  kind: string;
  name: string;
  bucket: string;
  path: string;
  size: number | null;
}

/** The file a message carries, if it carries one we can link to. */
export function attachmentOf(message: {
  type: string;
  attachment: Json | null;
}): ExportAttachment | null {
  const attachment = message.attachment;
  if (!attachment || typeof attachment !== "object") return null;
  const bucket = attachment["bucket"];
  const path = attachment["path"];
  if (typeof bucket !== "string" || typeof path !== "string") return null;
  const kind = typeof attachment["kind"] === "string"
    ? attachment["kind"] as string
    : message.type;
  const named = attachment["name"];
  const size = attachment["size"];
  return {
    kind,
    bucket,
    path,
    name: typeof named === "string" && named !== ""
      ? named
      : path.split("/").pop() ?? path,
    size: typeof size === "number" ? size : null,
  };
}

export function attachmentKey(attachment: { bucket: string; path: string }) {
  return `${attachment.bucket}/${attachment.path}`;
}

/** Every distinct file the messages link to, as bucket and path. */
export function attachmentsToSign(
  messages: { type: string; attachment: Json | null }[],
): { bucket: string; path: string }[] {
  const seen = new Map<string, { bucket: string; path: string }>();
  for (const message of messages) {
    const attachment = attachmentOf(message);
    if (attachment) {
      seen.set(attachmentKey(attachment), {
        bucket: attachment.bucket,
        path: attachment.path,
      });
    }
  }
  return [...seen.values()];
}

export function escapeHtml(text: string): string {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

/** `2026-10-17 14:03 UTC`, or the text itself when it is not a date. */
export function readableTime(iso: string | null): string {
  if (!iso) return "";
  const time = new Date(iso);
  if (Number.isNaN(time.getTime())) return iso;
  return `${time.toISOString().slice(0, 16).replace("T", " ")} UTC`;
}

/** A safe file name stem: lowercase letters, digits and dashes, or Chinese. */
export function slugify(text: string): string {
  const slug = text.toLowerCase()
    .replace(/[^a-z0-9一-鿿]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40);
  return slug === "" ? "chat" : slug;
}

/** Where an export lives in the private bucket: `<user>/<timestamp>.zip`. */
export function exportObjectPath(userId: string, now: Date): string {
  const stamp = now.toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  return `${userId}/${stamp}.zip`;
}

export function exportExpiresAt(createdAt: Date): Date {
  return new Date(createdAt.getTime() + EXPORT_LIFETIME_MS);
}

export interface RateLimit {
  allowed: boolean;
  retryAfterSeconds: number;
}

/** One export per 24 hours, counted from the last one that was started. */
export function rateLimit(
  lastStartedAt: Date | null,
  now: Date,
  windowMs = EXPORT_WINDOW_MS,
): RateLimit {
  if (!lastStartedAt) return { allowed: true, retryAfterSeconds: 0 };
  const waitMs = lastStartedAt.getTime() + windowMs - now.getTime();
  if (waitMs <= 0) return { allowed: true, retryAfterSeconds: 0 };
  return { allowed: false, retryAfterSeconds: Math.ceil(waitMs / 1000) };
}

/** The part of the 0-100 bar each step of the export fills. */
export const EXPORT_STAGES = [
  { stage: "queued", progress: 0 },
  { stage: "profile", progress: 8 },
  { stage: "friends", progress: 16 },
  { stage: "conversations", progress: 26 },
  { stage: "messages", progress: 40 },
  { stage: "circles", progress: 68 },
  { stage: "attachments", progress: 76 },
  { stage: "packaging", progress: 88 },
  { stage: "uploading", progress: 95 },
  { stage: "ready", progress: 100 },
] as const;

export type ExportStage = typeof EXPORT_STAGES[number]["stage"];

export function stageProgress(stage: string): number {
  return EXPORT_STAGES.find((entry) => entry.stage === stage)?.progress ?? 0;
}

function pretty(value: unknown): string {
  return JSON.stringify(value, null, 2) + "\n";
}

function messageJson(
  message: ExportMessage,
  links: Record<string, string>,
  expiresAt: string,
): Json {
  const attachment = attachmentOf(message);
  return {
    id: message.id,
    conversation_id: message.conversationId,
    type: message.type,
    text: message.body,
    sent_at: message.createdAt,
    edited_at: message.editedAt,
    deleted_at: message.recalledAt,
    attachment: attachment
      ? {
        kind: attachment.kind,
        name: attachment.name,
        size: attachment.size,
        download_url: links[attachmentKey(attachment)] ?? null,
        download_url_expires_at: expiresAt,
      }
      : null,
  };
}

/** Messages grouped by conversation, oldest first. */
export function groupMessages(
  messages: ExportMessage[],
): Map<string, ExportMessage[]> {
  const groups = new Map<string, ExportMessage[]>();
  for (const message of messages) {
    const list = groups.get(message.conversationId) ?? [];
    list.push(message);
    groups.set(message.conversationId, list);
  }
  for (const list of groups.values()) {
    list.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  }
  return groups;
}

const style = `
body{font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"PingFang SC","Microsoft YaHei",sans-serif;
margin:0;background:#f5f4f1;color:#17171a}
main{max-width:760px;margin:0 auto;padding:32px 20px 64px}
h1{font-size:30px;letter-spacing:-.6px;margin:0 0 4px}
h2{font-size:14px;letter-spacing:.2px;color:#6f6d76;margin:32px 0 10px}
.card{background:#fff;border-radius:18px;padding:6px 18px}
.row{display:flex;justify-content:space-between;gap:16px;padding:12px 0;border-bottom:1px solid #efede8}
.row:last-child{border-bottom:0}.muted{color:#5f5e66;font-size:14px}
a{color:#1f5fe0}.msg{padding:12px 0;border-bottom:1px solid #efede8}
.msg:last-child{border-bottom:0}.when{color:#5f5e66;font-size:13px}
.body{white-space:pre-wrap;word-break:break-word}.tag{display:inline-block;background:#e9f0ff;
color:#1f5fe0;border-radius:8px;padding:0 8px;font-size:13px;margin-top:4px}
@media (prefers-color-scheme:dark){body{background:#111113;color:#f3f2ef}.card{background:#1b1b1e}
.row,.msg{border-color:#242428}.muted,.when,h2{color:#a3a1af}a{color:#9db8ff}.tag{background:#23283a;color:#9db8ff}}
`;

function page(title: string, body: string): string {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title)}</title><style>${style}</style></head>
<body><main>${body}</main></body></html>
`;
}

function field(label: string, value: string | null | undefined): string {
  if (value === null || value === undefined || value === "") return "";
  return `<div class="row"><span>${escapeHtml(label)}</span><span class="muted">${
    escapeHtml(value)
  }</span></div>`;
}

/** The overview page: who you are, how much there is, links to chats. */
export function buildIndexHtml(
  data: ExportData,
  conversationPages: Map<string, string>,
): string {
  const groups = groupMessages(data.messages);
  const profile = data.profile ?? {};
  const text = (key: string) => {
    const value = profile[key];
    return typeof value === "string" ? value : null;
  };
  const conversationRows = data.conversations.map((conversation) => {
    const count = groups.get(conversation.id)?.length ?? 0;
    const href = conversationPages.get(conversation.id);
    const name = escapeHtml(conversation.name || "(unnamed)");
    const label = href && count > 0
      ? `<a href="${escapeHtml(href)}">${name}</a>`
      : name;
    const circle = conversation.circleName
      ? ` <span class="muted">in ${escapeHtml(conversation.circleName)}</span>`
      : "";
    return `<div class="row"><span>${label}${circle}</span><span class="muted">${
      escapeHtml(conversation.kind)
    } · ${count} message${count === 1 ? "" : "s"} from you</span></div>`;
  }).join("");
  const friendRows = data.friends.map((friend) =>
    `<div class="row"><span>${escapeHtml(friend.displayName || friend.username)
    } <span class="muted">@${escapeHtml(friend.username)}</span></span><span class="muted">${
      escapeHtml(friend.remark ? `“${friend.remark}” · ` : "")
    }${escapeHtml(readableTime(friend.since))}</span></div>`
  ).join("");
  const circleRows = data.circles.map((circle) =>
    `<div class="row"><span>${escapeHtml(circle.name)}${
      circle.nickname
        ? ` <span class="muted">as ${escapeHtml(circle.nickname)}</span>`
        : ""
    }</span><span class="muted">joined ${
      escapeHtml(readableTime(circle.joinedAt))
    }</span></div>`
  ).join("");

  return page(
    "Your WeCord data",
    `<h1>Your WeCord data</h1>
<p class="muted">Collected ${escapeHtml(readableTime(data.generatedAt))}. The
<code>data</code> folder has the same information as JSON files. Links to files
you sent work until ${escapeHtml(readableTime(data.linksExpireAt))}.</p>
<h2>Account</h2><div class="card">${field("Email", data.user.email)}${
      field("Username", text("username"))
    }${field("Display name", text("display_name"))}${
      field("Bio", text("bio"))
    }${field("Account created", readableTime(data.user.createdAt))}${
      field("Last sign-in", readableTime(data.user.lastSignInAt))
    }</div>
<h2>Friends (${data.friends.length})</h2><div class="card">${
      friendRows || '<div class="row muted">No friends yet.</div>'
    }</div>
<h2>Conversations (${data.conversations.length})</h2><div class="card">${
      conversationRows || '<div class="row muted">No conversations.</div>'
    }</div>
<h2>Circles (${data.circles.length})</h2><div class="card">${
      circleRows || '<div class="row muted">No circles.</div>'
    }</div>
<h2>Totals</h2><div class="card">${
      field("Messages you sent", String(data.messages.length))
    }${field("People you blocked", String(data.blocked.length))}${
      field("Friend requests", String(data.friendRequests.length))
    }</div>${
      data.skipped.length > 0
        ? `<h2>Not included</h2><div class="card"><div class="row muted">${
          escapeHtml(data.skipped.join(", "))
        } could not be read for this export.</div></div>`
        : ""
    }`,
  );
}

/** One page with the messages you sent in a conversation. */
export function buildConversationHtml(
  conversation: ExportConversation,
  messages: ExportMessage[],
  links: Record<string, string>,
): string {
  const rows = messages.map((message) => {
    const attachment = attachmentOf(message);
    const url = attachment ? links[attachmentKey(attachment)] : undefined;
    const attachmentHtml = attachment
      ? `<div><span class="tag">${escapeHtml(attachment.kind)}</span> ${
        url
          ? `<a href="${escapeHtml(url)}">${escapeHtml(attachment.name)}</a>`
          : escapeHtml(attachment.name)
      }</div>`
      : "";
    const state = message.recalledAt
      ? ` · deleted ${escapeHtml(readableTime(message.recalledAt))}`
      : message.editedAt
      ? ` · edited ${escapeHtml(readableTime(message.editedAt))}`
      : "";
    return `<div class="msg"><div class="when">${
      escapeHtml(readableTime(message.createdAt))
    }${state}</div>${
      message.body !== ""
        ? `<div class="body">${escapeHtml(message.body)}</div>`
        : ""
    }${attachmentHtml}</div>`;
  }).join("");
  return page(
    `${conversation.name} — your messages`,
    `<p><a href="../index.html">← Your WeCord data</a></p>
<h1>${escapeHtml(conversation.name || "(unnamed)")}</h1>
<p class="muted">${messages.length} message${
      messages.length === 1 ? "" : "s"
    } you sent, oldest first.</p><div class="card">${rows}</div>`,
  );
}

export interface ExportFile {
  path: string;
  content: string;
}

const readme = `Your WeCord data
================

index.html            Start here: a readable overview with a page for each
                      conversation (messages/).
messages/             Your messages, one page per conversation.
data/profile.json     Your profile and account.
data/settings.json    Your privacy and notification settings.
data/friends.json     Friends, friend requests and people you blocked.
data/conversations.json  The conversations you are in.
data/messages.json    Every message you sent: text, time and file links.
data/circles.json     Circles you belong to.

Links to the files you sent expire when this export does (7 days after it
was made). Download what you want to keep.
`;

/** The text files of the archive, in the order they appear. */
export function buildExportFiles(source: ExportData): ExportFile[] {
  const groups = groupMessages(source.messages);
  // Messages in conversations the person has since left still belong to
  // them, so those conversations get a page too.
  const known = new Set(source.conversations.map((c) => c.id));
  const former: ExportConversation[] = [...groups.keys()]
    .filter((id) => !known.has(id))
    .map((id) => ({
      id,
      kind: "unknown",
      name: "A conversation you left",
      circleName: null,
      joinedAt: null,
      role: null,
      createdAt: null,
    }));
  const data: ExportData = {
    ...source,
    conversations: [...source.conversations, ...former],
  };

  const pages = new Map<string, string>();
  const used = new Set<string>();
  for (const conversation of data.conversations) {
    if ((groups.get(conversation.id)?.length ?? 0) === 0) continue;
    const stem = slugify(conversation.name);
    let file = `messages/${stem}.html`;
    for (let n = 2; used.has(file); n++) {
      file = `messages/${stem}-${n}.html`;
    }
    used.add(file);
    pages.set(conversation.id, file);
  }

  const files: ExportFile[] = [
    { path: "README.txt", content: readme },
    { path: "index.html", content: buildIndexHtml(data, pages) },
    {
      path: "data/profile.json",
      content: pretty({
        exported_at: data.generatedAt,
        account: {
          id: data.user.id,
          email: data.user.email,
          created_at: data.user.createdAt,
          last_sign_in_at: data.user.lastSignInAt,
        },
        profile: data.profile,
      }),
    },
    { path: "data/settings.json", content: pretty(data.settings) },
    {
      path: "data/friends.json",
      content: pretty({
        friends: data.friends,
        friend_requests: data.friendRequests,
        blocked: data.blocked,
      }),
    },
    {
      path: "data/conversations.json",
      content: pretty(
        data.conversations.map((conversation) => ({
          ...conversation,
          messages_from_you: groups.get(conversation.id)?.length ?? 0,
        })),
      ),
    },
    {
      path: "data/messages.json",
      content: pretty(
        data.messages.map((message) =>
          messageJson(message, data.attachmentLinks, data.linksExpireAt)
        ),
      ),
    },
    { path: "data/circles.json", content: pretty(data.circles) },
  ];
  for (const conversation of data.conversations) {
    const path = pages.get(conversation.id);
    const messages = groups.get(conversation.id);
    if (path && messages) {
      files.push({
        path,
        content: buildConversationHtml(
          conversation,
          messages,
          data.attachmentLinks,
        ),
      });
    }
  }
  return files;
}

/** The finished archive. */
export function buildExportZip(data: ExportData): Uint8Array {
  const entries: Record<string, Uint8Array> = {};
  for (const file of buildExportFiles(data)) {
    entries[file.path] = strToU8(file.content);
  }
  return zipSync(entries, { level: 6 });
}
