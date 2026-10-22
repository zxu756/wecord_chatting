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

/** What export_my_moments returns (migration 202610190023): only mine. */
export interface ExportMoments {
  /** Visible range and cover file, null when never set. */
  settings: Json | null;
  /** Per-friend choices: hide_mine / hide_theirs. */
  friendPrefs: Json[];
  /** Every column of my posts, so columns added later (video) flow through. */
  posts: Json[];
  comments: Json[];
  likes: Json[];
  tags: Json[];
  stars: Json[];
}

/** What export_my_extras returns (migration 202610190023): only mine. */
export interface ExportExtras {
  chains: Json[];
  notes: Json[];
  taskLists: Json[];
  savedMessages: Json[];
  reminders: Json[];
  scheduledMessages: Json[];
  wallpapers: Json[];
}

/** A file of mine from Storage that is put into the ZIP itself. */
export interface ExportBlob {
  /** `bucket/path`, as in attachmentLinks. */
  key: string;
  /** Where it lives in the archive: `files/<bucket>/<name>`. */
  zipPath: string;
  bytes: Uint8Array;
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
  /** Null when it could not be read (then it is in `skipped`). */
  moments: ExportMoments | null;
  extras: ExportExtras | null;
  /**
   * Forms I made or answered (export_my_forms, migration 202610230130); null
   * when it could not be read, absent in older callers.
   */
  forms?: Json[] | null;
  /**
   * The feedback I sent and the replies to it (export_my_feedback, migration
   * 202610240660); null when it could not be read, absent in older callers.
   */
  feedback?: Json[] | null;
  /**
   * The daily digest settings (export_my_ai_digest, migration
   * 202610230540); null when it could not be read, absent in older callers.
   */
  aiDigest?: Json | null;
  /**
   * The comments I wrote on notes, my note templates and the pages I
   * published (export_my_note_extras, migration 202610240340); null when it
   * could not be read, absent in older callers.
   */
  noteExtras?: Json | null;
  /**
   * The dailies still up, my close friends and my reports of dailies
   * (export_my_stories, migration 202610240250); null when it could not be
   * read, absent in older callers.
   */
  stories?: Json | null;
  /**
   * The fields of my task lists, their values on the tasks I made, subtasks
   * and repeat rules (export_my_task_extras, migration 202610250130); null
   * when it could not be read, absent in older callers.
   */
  taskExtras?: Json | null;
  /**
   * My favorites: the folders and everything I kept, with where it is filed,
   * its tags and remark (export_my_saved_items, migration 202610250430);
   * null when it could not be read, absent in older callers.
   */
  favorites?: Json | null;
  /**
   * Moments 2.0: the posts I pinned, the people I reminded to read, the
   * reminders I got and the pictures on my comments (export_my_moments_more,
   * migration 202610260650); null when it could not be read, absent in older
   * callers.
   */
  momentsMore?: Json | null;
  /**
   * The pages I made in circle knowledge bases and the ones I read
   * (export_my_knowledge, migration 202610270130); null when it could not be
   * read, absent in older callers.
   */
  knowledge?: Json | null;
  /**
   * The titles circles gave me, my honors and streaks, and the circles where
   * I stay out of honors (export_my_honors, migration 202610270240); null
   * when it could not be read, absent in older callers.
   */
  honors?: Json | null;
  /**
   * What I made in media and Q&A channels: my picture posts, my questions and
   * the answers of mine that were accepted (export_my_channel_posts, migration
   * 202610270330); null when it could not be read, absent in older callers.
   */
  channelPosts?: Json | null;
  /**
   * What I did with events (export_my_events2, migration 202610270470): the
   * events I signed up to, waited for, checked in to, the pictures I added and
   * the events I made; null when it could not be read, absent in older
   * callers.
   */
  events2?: Json | null;
  /** My own files (photos, videos, covers, wallpapers) inside the ZIP. */
  files: ExportBlob[];
  /**
   * Signed links by `bucket/path`: to the files in messages and to my own
   * files that did not fit into the ZIP.
   */
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

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function objects(value: unknown): Json[] {
  return Array.isArray(value) ? value.filter(isObject) : [];
}

function str(value: unknown): string | null {
  return typeof value === "string" && value !== "" ? value : null;
}

export const MOMENTS_BUCKET = "moments";
export const WALLPAPERS_BUCKET = "wallpapers";

export interface OwnedFile {
  bucket: string;
  path: string;
  /** Bytes, when the database says (a video's size); null when unknown. */
  size: number | null;
}

/**
 * The Storage files of the person's own Moments and wallpapers: the cover,
 * the photos and video of their posts, their wallpaper photos. Only paths in
 * the person's own folder (`<user id>/…`) are returned, whatever the data
 * says, so the export can never fetch somebody else's file. Small and
 * likely-wanted files come first (cover, wallpapers), then the posts' files in
 * the order the database returned them (newest post first).
 */
export function ownedFiles(
  userId: string,
  moments: ExportMoments | null,
  extras: ExportExtras | null,
): OwnedFile[] {
  const found = new Map<string, OwnedFile>();
  const add = (bucket: string, path: unknown, size: unknown = null) => {
    if (typeof path !== "string" || !path.startsWith(`${userId}/`)) return;
    if (path.includes("..") || path.endsWith("/")) return;
    const key = `${bucket}/${path}`;
    if (!found.has(key)) {
      found.set(key, {
        bucket,
        path,
        size: typeof size === "number" && size >= 0 ? size : null,
      });
    }
  };
  add(MOMENTS_BUCKET, moments?.settings?.["cover_path"]);
  for (const wallpaper of extras?.wallpapers ?? []) {
    add(WALLPAPERS_BUCKET, wallpaper["photo_path"]);
  }
  for (const post of moments?.posts ?? []) {
    for (const photo of objects(post["photos"])) {
      add(MOMENTS_BUCKET, photo["path"], photo["size"]);
    }
    const video = post["video"];
    if (isObject(video)) {
      add(MOMENTS_BUCKET, video["path"], video["size"]);
      add(MOMENTS_BUCKET, video["poster"]);
    }
  }
  return [...found.values()];
}

/** `files/moments/<post>-0.jpg` for `moments/<user>/<post>-0.jpg`. */
export function exportFileZipPath(bucket: string, path: string): string {
  const name = path.split("/").slice(1).join("-").replace(
    /[^A-Za-z0-9._-]/g,
    "_",
  );
  return `files/${bucket}/${name === "" ? "file" : name}`;
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
  { stage: "circles", progress: 58 },
  { stage: "moments", progress: 64 },
  { stage: "more", progress: 70 },
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
  return `<div class="row"><span>${
    escapeHtml(label)
  }</span><span class="muted">${escapeHtml(value)}</span></div>`;
}

/** The overview page: who you are, how much there is, links to chats. */
export function buildIndexHtml(
  data: ExportData,
  conversationPages: Map<string, string>,
  sections: { path: string; label: string; summary: string }[] = [],
): string {
  const sectionRows = sections.map((entry) =>
    `<div class="row"><span><a href="${escapeHtml(entry.path)}">${
      escapeHtml(entry.label)
    }</a></span><span class="muted">${escapeHtml(entry.summary)}</span></div>`
  ).join("");
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
    `<div class="row"><span>${
      escapeHtml(friend.displayName || friend.username)
    } <span class="muted">@${
      escapeHtml(friend.username)
    }</span></span><span class="muted">${
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
    }</div>${
      sectionRows
        ? `\n<h2>More of your data</h2><div class="card">${sectionRows}</div>`
        : ""
    }
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

// ---------------------------------------------------------------------
// Moments, tags, chains, notes, lists, saved messages, reminders, scheduled
// messages and wallpapers. What each section holds, and what it leaves out,
// is in docs/data-export.md: everything here is the person's own content, and
// other people appear by name only.
// ---------------------------------------------------------------------

interface FileRef {
  /** Path inside the ZIP, when the file is in it. */
  file: string | null;
  download_url: string | null;
  download_url_expires_at: string | null;
}

function fileRefs(data: ExportData) {
  const inside = new Map(data.files.map((blob) => [blob.key, blob.zipPath]));
  return (bucket: string, path: unknown): FileRef | null => {
    if (typeof path !== "string") return null;
    const key = `${bucket}/${path}`;
    const url = data.attachmentLinks[key] ?? null;
    return {
      file: inside.get(key) ?? null,
      download_url: url,
      download_url_expires_at: url ? data.linksExpireAt : null,
    };
  };
}

function conversationName(data: ExportData, id: unknown): string {
  const found = data.conversations.find((c) => c.id === id);
  return found?.name || "A conversation you left";
}

function personName(person: unknown): string {
  if (!isObject(person)) return "";
  return str(person["display_name"]) ?? str(person["username"]) ?? "Someone";
}

function names(people: unknown): string {
  return objects(people).map(personName).filter((n) => n !== "").join(", ");
}

/** A post with my files resolved to ZIP paths or links. */
function postJson(post: Json, ref: ReturnType<typeof fileRefs>): Json {
  const out: Json = {
    ...post,
    photos: objects(post["photos"]).map((photo) => ({
      ...photo,
      ...ref(MOMENTS_BUCKET, photo["path"]),
    })),
  };
  const video = post["video"];
  if (isObject(video)) {
    out["video"] = {
      ...video,
      ...ref(MOMENTS_BUCKET, video["path"]),
      poster_ref: ref(MOMENTS_BUCKET, video["poster"]),
    };
  }
  return out;
}

export interface SectionJson {
  path: string;
  value: unknown;
}

/** The JSON files of the new sections, only for the parts that were read. */
export function buildSectionJson(data: ExportData): SectionJson[] {
  const ref = fileRefs(data);
  const out: SectionJson[] = [];
  const moments = data.moments;
  if (moments) {
    const cover = moments.settings
      ? ref(MOMENTS_BUCKET, moments.settings["cover_path"])
      : null;
    out.push({
      path: "data/moments.json",
      value: {
        settings: moments.settings ? { ...moments.settings, cover } : null,
        friend_choices: moments.friendPrefs,
        posts: moments.posts.map((post) => postJson(post, ref)),
        comments_you_wrote: moments.comments,
        posts_you_liked: moments.likes,
      },
    });
    out.push({
      path: "data/friend_tags.json",
      value: { tags: moments.tags, starred_friends: moments.stars },
    });
  }
  if (data.forms) {
    out.push({ path: "data/forms.json", value: formsJson(data) });
  }
  if (data.feedback) {
    out.push({ path: "data/feedback.json", value: feedbackJson(data) });
  }
  if (data.aiDigest) {
    out.push({ path: "data/ai_digest.json", value: data.aiDigest });
  }
  if (data.noteExtras) {
    out.push({ path: "data/note_extras.json", value: data.noteExtras });
  }
  if (data.stories) {
    out.push({ path: "data/stories.json", value: storiesJson(data) });
  }
  if (data.taskExtras) {
    out.push({ path: "data/task_extras.json", value: data.taskExtras });
  }
  if (data.favorites) {
    out.push({ path: "data/favorites.json", value: favoritesJson(data) });
  }
  if (data.momentsMore) {
    out.push({ path: "data/moments_more.json", value: momentsMoreJson(data) });
  }
  if (data.knowledge) {
    out.push({ path: "data/knowledge.json", value: data.knowledge });
  }
  if (data.honors) {
    out.push({ path: "data/honors.json", value: data.honors });
  }
  if (data.channelPosts) {
    out.push({
      path: "data/channel_posts.json",
      value: channelPostsJson(data),
    });
  }
  if (data.events2) {
    out.push({ path: "data/events.json", value: eventsJson(data) });
  }
  const extras = data.extras;
  if (extras) {
    out.push({ path: "data/chains.json", value: extras.chains });
    out.push({ path: "data/notes.json", value: extras.notes });
    out.push({ path: "data/task_lists.json", value: extras.taskLists });
    out.push({ path: "data/saved_messages.json", value: extras.savedMessages });
    out.push({ path: "data/reminders.json", value: extras.reminders });
    out.push({
      path: "data/scheduled_messages.json",
      value: extras.scheduledMessages,
    });
    out.push({
      path: "data/wallpapers.json",
      value: extras.wallpapers.map((wallpaper) => ({
        ...wallpaper,
        photo: ref(WALLPAPERS_BUCKET, wallpaper["photo_path"]),
      })),
    });
  }
  return out;
}

const visibilityLabels: Record<string, string> = {
  friends: "All friends",
  private: "Only you",
  only: "Only some friends",
  except: "All friends except some",
};

function backLink(): string {
  return `<p><a href="../index.html">← Your WeCord data</a></p>`;
}

function section(title: string, rows: string, empty: string): string {
  return `<h2>${escapeHtml(title)}</h2><div class="card">${
    rows || `<div class="row muted">${escapeHtml(empty)}</div>`
  }</div>`;
}

function entry(when: string | null, body: string): string {
  return `<div class="msg">${
    when ? `<div class="when">${escapeHtml(readableTime(when))}</div>` : ""
  }${body}</div>`;
}

function text(value: unknown): string {
  return typeof value === "string" && value !== ""
    ? `<div class="body">${escapeHtml(value)}</div>`
    : "";
}

function tag(label: string): string {
  return `<span class="tag">${escapeHtml(label)}</span>`;
}

/** A file in the ZIP (shown when it is a picture) or a link, or its name. */
function fileHtml(
  ref: FileRef | null,
  label: string,
  inline: boolean,
  depth = "../",
): string {
  if (!ref) return "";
  if (ref.file) {
    const href = escapeHtml(`${depth}${ref.file}`);
    return inline
      ? `<div><a href="${href}"><img src="${href}" alt="${
        escapeHtml(label)
      }" style="max-width:160px;max-height:160px;border-radius:10px;margin:4px 6px 0 0"></a></div>`
      : `<div><a href="${href}">${escapeHtml(label)}</a></div>`;
  }
  if (ref.download_url) {
    return `<div><a href="${escapeHtml(ref.download_url)}">${
      escapeHtml(label)
    }</a> <span class="muted">(link works until ${
      escapeHtml(readableTime(ref.download_url_expires_at))
    })</span></div>`;
  }
  return `<div class="muted">${escapeHtml(label)} (file not available)</div>`;
}

export function buildMomentsHtml(data: ExportData): string {
  const moments = data.moments!;
  const ref = fileRefs(data);
  const settings = moments.settings;
  const range = settings ? str(settings["visible_range"]) : null;
  const rangeLabels: Record<string, string> = {
    all: "All",
    six_months: "Last six months",
    one_month: "Last month",
    three_days: "Last three days",
  };
  const more = isObject(data.momentsMore) ? data.momentsMore : {};
  const remindedByPost = new Map(
    objects(more["reminded"]).map((r) => [
      str(r["post_id"]) ?? "",
      names(r["people"]),
    ]),
  );
  const pictureByComment = new Map(
    objects(more["comment_pictures"]).map((p) => [
      str(p["comment_id"]) ?? "",
      p,
    ]),
  );
  const posts = moments.posts.map((post) => {
    const photos = objects(post["photos"]).map((photo, n) =>
      fileHtml(ref(MOMENTS_BUCKET, photo["path"]), `Photo ${n + 1}`, true) +
      (str(photo["alt"])
        ? `<div class="muted">Description: ${
          escapeHtml(str(photo["alt"])!)
        }</div>`
        : "")
    ).join("");
    const reminded = remindedByPost.get(str(post["id"]) ?? "");
    const video = post["video"];
    const videoHtml = isObject(video)
      ? fileHtml(ref(MOMENTS_BUCKET, video["path"]), "Video", false)
      : "";
    const audience = names(post["audience_friends"]);
    const audienceTags = objects(post["audience_tags"]).map((t) =>
      str(t["name"]) ?? ""
    ).filter((n) => n !== "").join(", ");
    const who = [audience, audienceTags ? `tags: ${audienceTags}` : ""].filter(
      (part) => part !== "",
    ).join("; ");
    const link = str(post["link_url"]);
    return entry(
      str(post["created_at"]),
      `${text(post["body"])}${
        link
          ? `<div><a href="${escapeHtml(link)}">${
            escapeHtml(str(post["link_title"]) ?? link)
          }</a></div>`
          : ""
      }${
        str(post["location"])
          ? `<div class="muted">📍 ${escapeHtml(str(post["location"])!)}</div>`
          : ""
      }${photos}${videoHtml}<div>${
        tag(visibilityLabels[str(post["visibility"]) ?? ""] ?? "Friends")
      }${str(post["pinned_at"]) ? ` ${tag("Pinned")}` : ""}${
        who ? ` <span class="muted">${escapeHtml(who)}</span>` : ""
      }</div>${
        reminded
          ? `<div class="muted">Reminded to read: ${escapeHtml(reminded)}</div>`
          : ""
      }`,
    );
  }).join("");
  const comments = moments.comments.map((comment) =>
    entry(
      str(comment["created_at"]),
      `<div class="muted">On a post by ${
        escapeHtml(personName(comment["post_author"]) || "someone")
      }${
        str(comment["reply_to"] && (comment["reply_to"] as Json)["id"])
          ? `, replying to ${escapeHtml(personName(comment["reply_to"]))}`
          : ""
      }</div>${text(comment["text"])}${
        str(comment["post_text"])
          ? `<div class="muted">Your post: ${
            escapeHtml(str(comment["post_text"])!)
          }</div>`
          : ""
      }${
        pictureByComment.has(str(comment["id"]) ?? "")
          ? fileHtml(
            ref(
              MOMENTS_BUCKET,
              pictureByComment.get(str(comment["id"]) ?? "")!["path"],
            ),
            str(
              pictureByComment.get(str(comment["id"]) ?? "")!["description"],
            ) ??
              "Picture on the comment",
            true,
          )
          : ""
      }`,
    )
  ).join("");
  const likes = moments.likes.map((like) =>
    `<div class="row"><span class="muted">Post ${
      escapeHtml((str(like["post_id"]) ?? "").slice(0, 8))
    }</span><span class="muted">${
      escapeHtml(readableTime(str(like["created_at"])))
    }</span></div>`
  ).join("");
  const choices = moments.friendPrefs.map((pref) =>
    `<div class="row"><span>${
      escapeHtml(personName(pref["friend"]))
    }</span><span class="muted">${
      [
        pref["hide_mine"] === true ? "can’t see your Moments" : "",
        pref["hide_theirs"] === true ? "their Moments hidden from you" : "",
      ].filter((part) => part !== "").join(" · ") || "no special choice"
    }</span></div>`
  ).join("");
  const tags = moments.tags.map((t) =>
    `<div class="row"><span>${
      escapeHtml(str(t["name"]) ?? "")
    }</span><span class="muted">${
      escapeHtml(names(t["friends"]) || "nobody yet")
    }</span></div>`
  ).join("");
  const stars = moments.stars.map((s) =>
    `<div class="row"><span>${
      escapeHtml(personName(s["friend"]))
    }</span><span class="muted">${
      escapeHtml(readableTime(str(s["starred_at"])))
    }</span></div>`
  ).join("");
  return page(
    "Your Moments — your WeCord data",
    `${backLink()}<h1>Your Moments</h1>
<p class="muted">The posts you wrote, the comments you wrote on any post, the
posts you liked, and your Moments settings, friend tags and starred friends.
Other people’s posts, photos, comments and settings are not part of this
export.</p>
<h2>Settings</h2><div class="card">${
      field("Visible range", range ? rangeLabels[range] ?? range : null)
    }${
      settings
        ? fileHtml(
          ref(MOMENTS_BUCKET, settings["cover_path"]),
          "Cover photo",
          false,
        )
        : ""
    }${settings ? "" : '<div class="row muted">Default settings.</div>'}</div>
${section(`Your posts (${moments.posts.length})`, posts, "No posts.")}
${
      section(
        `Comments you wrote (${moments.comments.length})`,
        comments,
        "No comments.",
      )
    }
${section(`Posts you liked (${moments.likes.length})`, likes, "No likes.")}
${
      section(
        "Reminders you got",
        objects(more["reminded_by"]).map((r) =>
          `<div class="row"><span>${
            escapeHtml(personName(r["from"]))
          } reminded you to read a post</span><span class="muted">${
            escapeHtml(readableTime(str(r["created_at"])))
          }</span></div>`
        ).join(""),
        "No reminders.",
      )
    }
${section("Choices for friends", choices, "No special choices.")}
${section(`Friend tags (${moments.tags.length})`, tags, "No tags.")}
${
      section(
        `Starred friends (${moments.stars.length})`,
        stars,
        "No starred friends.",
      )
    }`,
  );
}

export function buildChainsHtml(data: ExportData): string {
  const chains = data.extras!.chains.map((chain) => {
    const mine = chain["created_by_me"] === true;
    const my = isObject(chain["my_entry"]) ? chain["my_entry"] : null;
    return entry(
      str(chain["created_at"]),
      `<div><strong>${escapeHtml(str(chain["title"]) ?? "")}</strong> ${
        tag(
          mine
            ? "you started it"
            : `started by ${personName(chain["creator"])}`,
        )
      }</div><div class="muted">in ${
        escapeHtml(conversationName(data, chain["conversation_id"]))
      }</div>${text(chain["description"])}${
        str(chain["example"])
          ? `<div class="muted">Example: ${
            escapeHtml(str(chain["example"])!)
          }</div>`
          : ""
      }${
        my
          ? `<div class="muted">Your line, ${
            escapeHtml(readableTime(str(my["joined_at"])))
          }:</div>${text(my["text"]) || '<div class="muted">(no note)</div>'}`
          : ""
      }`,
    );
  }).join("");
  return page(
    "Group chains — your WeCord data",
    `${backLink()}<h1>Group chains</h1>
<p class="muted">Chains you started or joined. Only your own line is included;
other people’s lines, and the description of chains you did not start, are not.</p>
<div class="card">${chains || '<div class="row muted">No chains.</div>'}</div>`,
  );
}

export function buildNotesHtml(data: ExportData): string {
  const extras = data.extras!;
  const notes = extras.notes.map((note) => {
    const blocks = objects(note["blocks"]).map((block) => text(block["text"]))
      .join("");
    return entry(
      str(note["updated_at"]),
      `<div><strong>${
        escapeHtml(
          `${str(note["icon"]) ?? ""} ${str(note["title"]) ?? "Untitled"}`,
        )
      }</strong> ${
        tag(
          note["created_by_me"] === true
            ? "you made it"
            : "made by someone else",
        )
      }</div><div class="muted">in ${
        escapeHtml(conversationName(data, note["conversation_id"]))
      }</div>${blocks || '<div class="muted">(no text of yours)</div>'}`,
    );
  }).join("");
  const lists = extras.taskLists.map((list) => {
    const items = objects(list["items"]).map((item) =>
      `<div class="body">${str(item["completed_at"]) ? "☑" : "☐"} ${
        escapeHtml(str(item["title"]) ?? "")
      }${
        str(item["details"])
          ? ` <span class="muted">— ${escapeHtml(str(item["details"])!)}</span>`
          : ""
      }${
        str(item["due_at"])
          ? ` <span class="muted">due ${
            escapeHtml(readableTime(str(item["due_at"])))
          }</span>`
          : ""
      }${
        names(item["assigned_to"])
          ? ` <span class="muted">for ${
            escapeHtml(names(item["assigned_to"]))
          }</span>`
          : ""
      }</div>`
    ).join("");
    return entry(
      str(list["created_at"]),
      `<div><strong>${
        escapeHtml(
          `${str(list["icon"]) ?? ""} ${str(list["title"]) ?? "Untitled"}`,
        )
      }</strong> ${
        tag(
          list["created_by_me"] === true
            ? "you made it"
            : "made by someone else",
        )
      }</div><div class="muted">in ${
        escapeHtml(conversationName(data, list["conversation_id"]))
      }</div>${items || '<div class="muted">(no items of yours)</div>'}`,
    );
  }).join("");
  return page(
    "Notes and task lists — your WeCord data",
    `${backLink()}<h1>Notes and task lists</h1>
<p class="muted">Notes and lists live in chats and are shared with the chat.
Of each note this export has the lines you last wrote; of each list, the items
you created. Titles and chat names are there for context. Anything someone
else wrote is not.</p>
${section(`Notes (${extras.notes.length})`, notes, "No notes.")}
${section(`Task lists (${extras.taskLists.length})`, lists, "No task lists.")}`,
  );
}

export function buildSavedHtml(data: ExportData): string {
  const extras = data.extras!;
  const saved = extras.savedMessages.map((item) =>
    entry(
      str(item["saved_at"]),
      `<div class="muted">in ${
        escapeHtml(conversationName(data, item["conversation_id"]))
      }${
        str(item["done_at"])
          ? ` · done ${escapeHtml(readableTime(str(item["done_at"])))}`
          : ""
      }</div>${
        item["from_you"] === true
          ? text(item["text"])
          : '<div class="muted">A message from someone else (not included).</div>'
      }`,
    )
  ).join("");
  const reminders = extras.reminders.map((item) =>
    entry(
      str(item["remind_at"]),
      `<div class="muted">in ${
        escapeHtml(conversationName(data, item["conversation_id"]))
      }${str(item["dismissed_at"]) ? " · dismissed" : ""}</div>${
        item["from_you"] === true
          ? text(item["text"])
          : '<div class="muted">About a message from someone else (not included).</div>'
      }`,
    )
  ).join("");
  const scheduled = extras.scheduledMessages.map((item) =>
    entry(
      str(item["send_at"]),
      `<div class="muted">to ${
        escapeHtml(conversationName(data, item["conversation_id"]))
      } · ${escapeHtml(str(item["status"]) ?? "")}</div>${text(item["text"])}`,
    )
  ).join("");
  return page(
    "Saved messages, reminders and scheduled messages — your WeCord data",
    `${backLink()}<h1>Saved messages, reminders and scheduled messages</h1>
<p class="muted">What you saved, set reminders for and scheduled. The text of a
saved or reminded message is included only when you wrote it.</p>
${
      section(
        `Saved messages (${extras.savedMessages.length})`,
        saved,
        "Nothing saved.",
      )
    }
${section(`Reminders (${extras.reminders.length})`, reminders, "No reminders.")}
${
      section(
        `Scheduled messages (${extras.scheduledMessages.length})`,
        scheduled,
        "Nothing scheduled.",
      )
    }`,
  );
}

export function buildWallpapersHtml(data: ExportData): string {
  const ref = fileRefs(data);
  const rows = data.extras!.wallpapers.map((wallpaper) => {
    const kind = str(wallpaper["kind"]) ?? "none";
    const where = wallpaper["conversation_id"]
      ? conversationName(data, wallpaper["conversation_id"])
      : "All chats (default)";
    const what = kind === "preset"
      ? `Preset “${str(wallpaper["preset_id"]) ?? ""}”`
      : kind === "photo"
      ? "Your photo"
      : "No wallpaper";
    return `<div class="msg"><div><strong>${escapeHtml(where)}</strong> ${
      tag(what)
    }</div>${
      kind === "photo"
        ? fileHtml(
          ref(WALLPAPERS_BUCKET, wallpaper["photo_path"]),
          "Wallpaper photo",
          true,
        )
        : ""
    }<div class="muted">dim ${String(wallpaper["dim"] ?? "")}${
      wallpaper["blur"] === true ? ", blurred" : ""
    }</div></div>`;
  }).join("");
  return page(
    "Chat wallpapers — your WeCord data",
    `${backLink()}<h1>Chat wallpapers</h1>
<p class="muted">The wallpapers you chose, for all chats or for one chat.</p>
<div class="card">${
      rows || '<div class="row muted">No wallpapers.</div>'
    }</div>`,
  );
}

/** The pictures I attached to answers of forms: files to link to. */
export function formFilesToSign(
  forms: Json[],
): { bucket: string; path: string }[] {
  const seen = new Map<string, { bucket: string; path: string }>();
  for (const form of forms) {
    for (const response of objects(form["my_responses"])) {
      const answers = response["answers"];
      if (!isObject(answers)) continue;
      for (const value of Object.values(answers)) {
        if (
          isObject(value) && typeof value["bucket"] === "string" &&
          typeof value["path"] === "string"
        ) {
          seen.set(`${value["bucket"]}/${value["path"]}`, {
            bucket: value["bucket"],
            path: value["path"],
          });
        }
      }
    }
  }
  return [...seen.values()];
}

/** The screenshots I attached to feedback: files to link to. */
export function feedbackFilesToSign(
  feedback: Json[],
): { bucket: string; path: string }[] {
  const seen = new Map<string, { bucket: string; path: string }>();
  for (const item of feedback) {
    const bucket = item["screenshot_bucket"];
    const path = item["screenshot_path"];
    if (typeof bucket === "string" && typeof path === "string") {
      seen.set(`${bucket}/${path}`, { bucket, path });
    }
  }
  return [...seen.values()];
}

const STORIES_BUCKET = "stories";

/** The files of my dailies: links, never put into the archive. */
export function storyFilesToSign(
  stories: Json | null | undefined,
): { bucket: string; path: string }[] {
  const seen = new Map<string, { bucket: string; path: string }>();
  for (const story of objects(stories?.["stories"])) {
    for (const key of ["path", "poster_path", "thumb_path"]) {
      const path = story[key];
      if (typeof path === "string") {
        seen.set(`${STORIES_BUCKET}/${path}`, { bucket: STORIES_BUCKET, path });
      }
    }
  }
  return [...seen.values()];
}

const audienceLabels: Record<string, string> = {
  friends: "All friends",
  close: "Close friends",
  private: "Only you",
  only: "Only some friends",
  except: "All friends except some",
};

/** My dailies with links to their files; the close friends and reports. */
function storiesJson(data: ExportData): Json {
  const ref = fileRefs(data);
  const stories = isObject(data.stories) ? data.stories : {};
  return {
    dailies: objects(stories["stories"]).map((story) => {
      const { path, poster_path: poster, thumb_path: thumb, ...rest } = story;
      delete rest["bucket"];
      return {
        ...rest,
        file: ref(STORIES_BUCKET, path),
        poster: poster ? ref(STORIES_BUCKET, poster) : null,
        thumbnail: ref(STORIES_BUCKET, thumb),
      };
    }),
    close_friends: objects(stories["close_friends"]),
    reports_you_filed: objects(stories["reports"]),
  };
}

export function buildStoriesHtml(data: ExportData): string {
  const ref = fileRefs(data);
  const stories = isObject(data.stories) ? data.stories : {};
  const dailies = objects(stories["stories"]).map((story) => {
    const kind = str(story["media_kind"]) === "video" ? "Video" : "Photo";
    const picture = fileHtml(
      ref(STORIES_BUCKET, story["thumb_path"]),
      `${kind} thumbnail`,
      true,
    );
    const media = fileHtml(ref(STORIES_BUCKET, story["path"]), kind, false);
    const audience = audienceLabels[str(story["audience"]) ?? ""] ?? "";
    const viewers = Number(story["viewer_count"] ?? 0);
    const ends = readableTime(str(story["expires_at"]));
    return entry(
      str(story["created_at"]),
      `${text(story["caption"])}${picture}${media}<div class="muted">${
        escapeHtml(audience)
      } · ${viewers} viewer${viewers === 1 ? "" : "s"}, ends ${
        escapeHtml(ends)
      }</div>`,
    );
  }).join("");
  const close = objects(stories["close_friends"]).map((person) =>
    `<div class="row">${
      escapeHtml(str(person["name"]) ?? personName(person))
    }</div>`
  ).join("");
  const reports = objects(stories["reports"]).map((report) =>
    entry(
      str(report["created_at"]),
      `<div class="body">${escapeHtml(str(report["reason"]) ?? "")}</div>${
        text(report["details"])
      }<div class="muted">${escapeHtml(str(report["status"]) ?? "")}</div>`,
    )
  ).join("");
  return page(
    "Daily — your WeCord data",
    `${backLink()}<h1>Daily</h1>
<p class="muted">The dailies you have up now (a daily ends 24 hours after you
post it), your close friends and the dailies you reported. Who viewed a daily
is not listed. Links to the files work until this export expires.</p>
${section("Your dailies", dailies, "No dailies up.")}
${section("Close friends", close, "No close friends.")}
${section("Reports you filed", reports, "No reports.")}`,
  );
}

/** Task lists 2.0: fields, subtasks and repeat rules of my tasks (D7). */
export function buildTaskExtrasHtml(data: ExportData): string {
  const extras = isObject(data.taskExtras) ? data.taskExtras : {};
  const repeatLabel = (rule: unknown): string => {
    if (!isObject(rule)) return "";
    const unit =
      { daily: "day", weekly: "week", monthly: "month", yearly: "year" }[
        str(rule["freq"]) ?? ""
      ];
    const every = Number(rule["interval"] ?? 1);
    return unit
      ? `repeats every ${every === 1 ? "" : `${every} `}${unit}${
        every === 1 ? "" : "s"
      }`
      : "";
  };
  const lists = objects(extras["lists"]).map((list) => {
    const fields = objects(list["fields"]).map((field) =>
      str(field["name"]) ?? ""
    )
      .filter((name) => name !== "").join(", ");
    const items = objects(list["items"]).map((item) => {
      const values = objects(item["values"]).map((value) => {
        const raw = value["value"];
        const shown = isObject(raw) ? personName(raw) : String(raw ?? "");
        return `${str(value["field"]) ?? ""}: ${shown}`;
      }).join(" · ");
      const notes = [
        item["parent_id"] ? "subtask" : "",
        repeatLabel(item["repeat"]),
        values,
      ].filter((part) => part !== "").join(" · ");
      return `<div class="body">${escapeHtml(str(item["title"]) ?? "")}${
        notes ? ` <span class="muted">— ${escapeHtml(notes)}</span>` : ""
      }</div>`;
    }).join("");
    return entry(
      null,
      `<div><strong>${escapeHtml(str(list["title"]) || "Untitled")}</strong> ${
        tag(
          list["created_by_me"] === true
            ? "you made it"
            : "made by someone else",
        )
      }</div><div class="muted">in ${
        escapeHtml(conversationName(data, list["conversation_id"]))
      }${fields ? ` · fields: ${escapeHtml(fields)}` : ""}</div>${
        items || '<div class="muted">(no tasks of yours)</div>'
      }`,
    );
  }).join("");
  return page(
    "Task list fields — your WeCord data",
    `${backLink()}<h1>Task list fields, subtasks and repeats</h1>
<p class="muted">What the lists you use store beyond the title and date: their
own fields, the values on the tasks you created, which tasks are subtasks and
which repeat.</p>
${section("Task lists", lists, "No task lists.")}`,
  );
}

/** The pictures on the comments I wrote: links, never put into the archive. */
export function momentsMoreFilesToSign(
  more: Json | null | undefined,
): { bucket: string; path: string }[] {
  const seen = new Map<string, { bucket: string; path: string }>();
  for (const picture of objects(more?.["comment_pictures"])) {
    const path = picture["path"];
    if (typeof path === "string") {
      seen.set(`${MOMENTS_BUCKET}/${path}`, { bucket: MOMENTS_BUCKET, path });
    }
  }
  return [...seen.values()];
}

/** Pins, reminders and comment pictures, with a link for each picture. */
function momentsMoreJson(data: ExportData): Json {
  const ref = fileRefs(data);
  const more = isObject(data.momentsMore) ? data.momentsMore : {};
  return {
    pinned_posts: objects(more["pinned"]),
    reminded_by_you: objects(more["reminded"]),
    reminded_you: objects(more["reminded_by"]),
    comment_pictures: objects(more["comment_pictures"]).map((picture) => ({
      comment_id: picture["comment_id"],
      post_id: picture["post_id"],
      description: picture["description"] ?? null,
      created_at: picture["created_at"],
      file: ref(MOMENTS_BUCKET, picture["path"]),
    })),
  };
}

const SAVED_NOTES_BUCKET = "saved-notes";

/** The pictures of my notes: links, never put into the archive. */
export function favoriteFilesToSign(
  favorites: Json | null | undefined,
): { bucket: string; path: string }[] {
  const seen = new Map<string, { bucket: string; path: string }>();
  for (const item of objects(favorites?.["items"])) {
    for (const image of objects(item["images"])) {
      const path = image["path"];
      if (typeof path === "string") {
        seen.set(`${SAVED_NOTES_BUCKET}/${path}`, {
          bucket: SAVED_NOTES_BUCKET,
          path,
        });
      }
    }
  }
  return [...seen.values()];
}

/** My favorites with a link to each picture of a note. */
function favoritesJson(data: ExportData): Json {
  const ref = fileRefs(data);
  const favorites = isObject(data.favorites) ? data.favorites : {};
  return {
    folders: objects(favorites["folders"]),
    items: objects(favorites["items"]).map((item) => ({
      ...item,
      images: item["images"] === undefined
        ? undefined
        : objects(item["images"]).map((image) => ({
          file: ref(SAVED_NOTES_BUCKET, image["path"]),
        })),
    })),
  };
}

const favoriteKindLabels: Record<string, string> = {
  message: "Message",
  moment: "Moment",
  circle_post: "Circle post",
  link: "Link",
  note: "Note",
  text: "Text",
};

export function buildFavoritesHtml(data: ExportData): string {
  const ref = fileRefs(data);
  const favorites = isObject(data.favorites) ? data.favorites : {};
  const folders = objects(favorites["folders"]).map((folder) =>
    `<div class="row">${escapeHtml(str(folder["name"]) ?? "")}</div>`
  ).join("");
  const items = objects(favorites["items"]).map((item) => {
    const kind = str(item["kind"]) ?? "";
    const label = favoriteKindLabels[kind] ?? kind;
    const title = str(item["title"]);
    const url = str(item["url"]);
    const tags = Array.isArray(item["tags"])
      ? item["tags"].filter((t): t is string => typeof t === "string")
        .map(tag).join(" ")
      : "";
    const folder = str(item["folder"]);
    const pictures = objects(item["images"]).map((image, n) =>
      fileHtml(ref(SAVED_NOTES_BUCKET, image["path"]), `Picture ${n + 1}`, true)
    ).join("");
    const written = kind === "message" || kind === "moment" ||
        kind === "circle_post"
      ? (item["text"] === undefined
        ? '<div class="muted">Written by someone else: not included.</div>'
        : text(item["text"]))
      : "";
    const link = url
      ? `<div><a href="${escapeHtml(url)}">${escapeHtml(url)}</a></div>`
      : "";
    return entry(
      str(item["saved_at"]),
      `<div class="muted">${escapeHtml(label)}${
        folder ? ` · ${escapeHtml(folder)}` : ""
      }${item["done_at"] ? " · done" : ""}</div>${
        title ? `<div class="body"><b>${escapeHtml(title)}</b></div>` : ""
      }${link}${text(item["body"])}${written}${pictures}${
        text(item["remark"])
      }${tags ? `<div>${tags}</div>` : ""}`,
    );
  }).join("");
  return page(
    "Favorites — your WeCord data",
    `${backLink()}<h1>Favorites</h1>
<p class="muted">What you kept, with its folder, tags and remark. The words of
messages, Moments and circle posts are included only when you wrote them.
Your links, notes and text are whole. Links to note pictures work until this
export expires.</p>
${section("Folders", folders, "No folders.")}
${section("Kept", items, "Nothing kept.")}`,
  );
}

/** My feedback with the link to each screenshot. */
function feedbackJson(data: ExportData): Json[] {
  const ref = fileRefs(data);
  return (data.feedback ?? []).map((item) => {
    const { screenshot_bucket: bucket, screenshot_path: path, ...rest } = item;
    return {
      ...rest,
      screenshot: typeof bucket === "string" ? ref(bucket, path) : null,
    };
  });
}

export function buildFeedbackHtml(data: ExportData): string {
  const ref = fileRefs(data);
  const items = (data.feedback ?? []).map((item) => {
    const bucket = item["screenshot_bucket"];
    const picture = typeof bucket === "string"
      ? fileHtml(ref(bucket, item["screenshot_path"]), "Your screenshot", true)
      : "";
    const replies = objects(item["replies"]).map((reply) =>
      `<div class="muted">Reply, ${
        escapeHtml(readableTime(str(reply["published_at"])))
      }:</div>${text(reply["body"])}`
    ).join("");
    const version = [str(item["platform"]), str(item["app_version"])]
      .filter((part) => part !== null && part !== "").join(" ");
    return entry(
      str(item["created_at"]),
      `${text(item["message"])}${
        version ? `<div class="muted">${escapeHtml(version)}</div>` : ""
      }${picture}${replies}`,
    );
  }).join("");
  return page(
    "Feedback — your WeCord data",
    `${backLink()}<h1>Feedback and help</h1>
<p class="muted">The feedback you sent, with the version and platform it carried,
and the replies from the WeCord team.</p>
<div class="card">${
      items || '<div class="row muted">No feedback.</div>'
    }</div>`,
  );
}

/** One answer in words: the label of a choice, a date, a number. */
function formAnswerText(question: Json, value: unknown): string {
  const type = str(question["type"]);
  const options = objects(question["options"]);
  const label = (id: unknown) =>
    str(options.find((o) => o["id"] === id)?.["label"]) ?? String(id);
  if (value === null || value === undefined) return "";
  if (type === "multiple_choice" && Array.isArray(value)) {
    return value.map(label).join(", ");
  }
  if (type === "single_choice") return label(value);
  if (type === "member") return "A member of the chat";
  if (isObject(value)) return "";
  return String(value);
}

/** My answers to the forms, readable. Other people's answers are not here. */
function formsJson(data: ExportData): Json[] {
  const ref = fileRefs(data);
  return (data.forms ?? []).map((form) => {
    const questions = objects(form["questions"]);
    return {
      ...form,
      my_responses: objects(form["my_responses"]).map((response) => {
        const answers = isObject(response["answers"])
          ? response["answers"]
          : {};
        return {
          ...response,
          readable: questions.map((question) => {
            const value = answers[str(question["id"]) ?? ""];
            const picture = isObject(value) && typeof value["path"] === "string"
              ? ref(str(value["bucket"]) ?? "chat-images", value["path"])
              : null;
            return {
              question: str(question["label"]),
              answer: formAnswerText(question, value),
              picture,
            };
          }),
        };
      }),
    };
  });
}

export function buildFormsHtml(data: ExportData): string {
  const ref = fileRefs(data);
  const forms = (data.forms ?? []).map((form) => {
    const mine = form["created_by_me"] === true;
    const questions = objects(form["questions"]);
    const sheets = objects(form["my_responses"]).map((response) => {
      const answers = isObject(response["answers"]) ? response["answers"] : {};
      const lines = questions.map((question) => {
        const value = answers[str(question["id"]) ?? ""];
        const picture = isObject(value) && typeof value["path"] === "string"
          ? fileHtml(
            ref(str(value["bucket"]) ?? "chat-images", value["path"]),
            "Your picture",
            true,
          )
          : "";
        const answer = formAnswerText(question, value);
        return `<div><span class="muted">${
          escapeHtml(str(question["label"]) ?? "")
        }</span> ${
          answer === "" && picture === ""
            ? '<span class="muted">(no answer)</span>'
            : escapeHtml(answer)
        }${picture}</div>`;
      }).join("");
      return `<div class="muted">Your answers, ${
        escapeHtml(readableTime(str(response["submitted_at"])))
      }:</div>${lines}`;
    }).join("");
    return entry(
      str(form["created_at"]),
      `<div><strong>${escapeHtml(str(form["title"]) ?? "")}</strong> ${
        tag(mine ? "you made it" : `made by ${personName(form["creator"])}`)
      }</div><div class="muted">in ${
        escapeHtml(conversationName(data, form["conversation_id"]))
      }</div>${mine ? text(form["description"]) : ""}${
        mine
          ? `<div class="muted">${
            escapeHtml(String(form["response_count"] ?? 0))
          } answers in all (not included).</div>`
          : ""
      }${sheets || '<div class="muted">You did not answer this form.</div>'}`,
    );
  }).join("");
  return page(
    "Forms — your WeCord data",
    `${backLink()}<h1>Forms</h1>
<p class="muted">Forms you made or answered. Only your own answers are included;
other people’s answers, and who answered a form you made, are not.</p>
<div class="card">${forms || '<div class="row muted">No forms.</div>'}</div>`,
  );
}

/** The daily digest settings: the switch, time, language and chats. */
export function buildAiDigestHtml(data: ExportData): string {
  const digest = isObject(data.aiDigest) ? data.aiDigest : {};
  const chats = objects(digest["subscriptions"]).map((chat) => {
    const circle = str(chat["circle"]);
    return entry(
      str(chat["since"]),
      `<div><strong>${escapeHtml(str(chat["name"]) ?? "Chat")}</strong>${
        circle ? ` <span class="muted">in ${escapeHtml(circle)}</span>` : ""
      }</div>`,
    );
  }).join("");
  const on = digest["enabled"] === true;
  return page(
    "Daily digest — your WeCord data",
    `${backLink()}<h1>Daily digest</h1>
<p class="muted">A summary of the chats you follow, once a day. The digests
themselves are short-lived and not included.</p>
<div class="card"><div class="row">${tag(on ? "on" : "off")} ${
      escapeHtml(str(digest["deliver_at"]) ?? "")
    } ${escapeHtml(str(digest["time_zone"]) ?? "")}</div></div>
<h2>Chats you follow</h2>
<div class="card">${
      chats || '<div class="row muted">No chats followed.</div>'
    }</div>`,
  );
}

/** The pages I made in circle knowledge bases, and the ones I read (D6). */
export function buildKnowledgeHtml(data: ExportData): string {
  const knowledge = isObject(data.knowledge) ? data.knowledge : {};
  const made = objects(knowledge["pages_made"]).map((p) =>
    entry(
      str(p["created_at"]),
      `<div><strong>${
        escapeHtml(str(p["title"]) || "A page you can no longer read")
      }</strong> <span class="muted">${
        escapeHtml(str(p["circle_name"]) ?? "")
      }</span></div>`,
    )
  ).join("");
  const read = objects(knowledge["pages_read"]).map((p) =>
    entry(
      str(p["read_at"]),
      `<div><strong>${
        escapeHtml(str(p["title"]) || "A page you can no longer read")
      }</strong> <span class="muted">${
        escapeHtml(str(p["circle_name"]) ?? "")
      }</span></div>`,
    )
  ).join("");
  return page(
    "Knowledge base pages — your WeCord data",
    `${backLink()}<h1>Knowledge base pages</h1>
<p class="muted">The pages you made in circles and the ones you opened. The
words you wrote in them are in notes.json. A title is shown only while you can
still read the page.</p>
<h2>Pages you made</h2>
<div class="card">${made || '<div class="row muted">No pages.</div>'}</div>
<h2>Pages you read</h2>
<div class="card">${
      read || '<div class="row muted">No pages read.</div>'
    }</div>`,
  );
}

const CHAT_IMAGES_BUCKET = "chat-images";

/** The pictures of my media posts: links, never put into the archive. */
export function channelPostFilesToSign(
  posts: Json | null | undefined,
): { bucket: string; path: string }[] {
  const seen = new Map<string, { bucket: string; path: string }>();
  for (const post of objects(posts?.["media_posts"])) {
    const picture = post["picture"];
    if (!isObject(picture)) continue;
    const path = picture["path"];
    if (typeof path !== "string") continue;
    const bucket = str(picture["bucket"]) ?? CHAT_IMAGES_BUCKET;
    seen.set(`${bucket}/${path}`, { bucket, path });
  }
  return [...seen.values()];
}

/** Media posts (with a link for each picture), questions, accepted answers. */
function channelPostsJson(data: ExportData): Json {
  const ref = fileRefs(data);
  const posts = isObject(data.channelPosts) ? data.channelPosts : {};
  return {
    media_posts: objects(posts["media_posts"]).map((post) => {
      const picture = isObject(post["picture"]) ? post["picture"] : null;
      return {
        circle_name: post["circle_name"],
        channel_name: post["channel_name"],
        title: post["title"],
        posted_at: post["posted_at"],
        picture: picture
          ? {
            description: picture["description"] ?? null,
            file: ref(
              str(picture["bucket"]) ?? CHAT_IMAGES_BUCKET,
              picture["path"],
            ),
          }
          : null,
      };
    }),
    questions: objects(posts["questions"]),
    accepted_answers: objects(posts["accepted_answers"]),
  };
}

/** My picture posts, my questions and my accepted answers (C9). */
export function buildChannelPostsHtml(data: ExportData): string {
  const posts = isObject(data.channelPosts) ? data.channelPosts : {};
  const where = (item: Json) =>
    `<span class="muted">${escapeHtml(str(item["circle_name"]) ?? "")} · ${
      escapeHtml(str(item["channel_name"]) ?? "")
    }</span>`;
  const ref = fileRefs(data);
  const media = objects(posts["media_posts"]).map((post) => {
    const picture = isObject(post["picture"]) ? post["picture"] : null;
    const link = picture
      ? ref(
        str(picture["bucket"]) ?? CHAT_IMAGES_BUCKET,
        picture["path"],
      )?.download_url
      : null;
    const description = picture ? str(picture["description"]) : null;
    return entry(
      str(post["posted_at"]),
      `<div><strong>${escapeHtml(str(post["title"]) ?? "")}</strong> ${
        where(post)
      }</div>${
        description ? `<div class="body">${escapeHtml(description)}</div>` : ""
      }${
        link
          ? `<div><a href="${escapeHtml(link)}">Picture (link)</a></div>`
          : ""
      }`,
    );
  }).join("");
  const questions = objects(posts["questions"]).map((question) => {
    const status = question["solved"] === true
      ? question["answer_accepted"] === true
        ? "solved, answer accepted"
        : "solved"
      : "open";
    return entry(
      str(question["asked_at"]),
      `<div><strong>${escapeHtml(str(question["title"]) ?? "")}</strong> ${
        where(question)
      }</div><div class="muted">${escapeHtml(status)}${
        question["solved_by_you"] === true ? " · marked by you" : ""
      }</div>`,
    );
  }).join("");
  const answers = objects(posts["accepted_answers"]).map((answer) =>
    entry(
      str(answer["accepted_at"]),
      `<div><strong>An answer of yours was accepted</strong> ${
        where(answer)
      }</div>`,
    )
  ).join("");
  return page(
    "Picture posts and Q&A — your WeCord data",
    `${backLink()}<h1>Picture posts and Q&amp;A</h1>
<p class="muted">The posts you made in media channels, the questions you asked
in Q&amp;A channels, and where an answer of yours was accepted. The words of
your posts and answers are with your messages; other people's questions and
answers are not copied.</p>
<h2>Picture posts</h2>
<div class="card">${
      media || '<div class="row muted">No picture posts.</div>'
    }</div>
<h2>Questions</h2>
<div class="card">${
      questions || '<div class="row muted">No questions.</div>'
    }</div>
<h2>Accepted answers</h2>
<div class="card">${answers || '<div class="row muted">None.</div>'}</div>`,
  );
}

/** The pictures I added to events and the covers of the events I made. */
export function eventFilesToSign(
  events: Json | null | undefined,
): { bucket: string; path: string }[] {
  const seen = new Map<string, { bucket: string; path: string }>();
  const add = (bucket: unknown, path: unknown) => {
    if (typeof path !== "string" || typeof bucket !== "string") return;
    seen.set(`${bucket}/${path}`, { bucket, path });
  };
  for (const photo of objects(events?.["photos"])) {
    add(photo["bucket"], photo["path"]);
  }
  for (const made of objects(events?.["events_made"])) {
    const cover = made["cover"];
    if (isObject(cover)) add(cover["bucket"], cover["path"]);
  }
  return [...seen.values()];
}

/** Events: sign-ups (with my answers), waiting, check-ins, pictures, made. */
function eventsJson(data: ExportData): Json {
  const ref = fileRefs(data);
  const events = isObject(data.events2) ? data.events2 : {};
  return {
    signed_up: objects(events["signed_up"]),
    waiting: objects(events["waiting"]),
    check_ins: objects(events["check_ins"]),
    photos: objects(events["photos"]).map((photo) => ({
      kind: photo["kind"],
      event: photo["title"],
      added_at: photo["added_at"],
      file: ref(str(photo["bucket"]) ?? CHAT_IMAGES_BUCKET, photo["path"]),
    })),
    // The events I made with a call (scheduled calls); never a link's code.
    calls_made: objects(events["calls_made"]),
    events_made: objects(events["events_made"]).map((made) => {
      const cover = isObject(made["cover"]) ? made["cover"] : null;
      return {
        ...made,
        cover: cover
          ? ref(str(cover["bucket"]) ?? CHAT_IMAGES_BUCKET, cover["path"])
          : null,
      };
    }),
  };
}

function answersText(answers: unknown, questions: unknown): string {
  if (!isObject(answers)) return "";
  const labels = new Map<string, string>();
  for (const question of objects(questions)) {
    const id = str(question["id"]);
    const label = str(question["label"]);
    if (id && label) labels.set(id, label);
  }
  return Object.entries(answers)
    .map(([id, value]) => `${labels.get(id) ?? id}: ${String(value)}`)
    .join(" · ");
}

/** My events: what I signed up to, waited for, checked in to, added, made. */
export function buildEventsHtml(data: ExportData): string {
  const events = isObject(data.events2) ? data.events2 : {};
  const ref = fileRefs(data);
  const place = (item: Json) =>
    item["circle_name"]
      ? `<span class="muted">${
        escapeHtml(str(item["circle_name"]) ?? "")
      }</span>`
      : "";
  const signedUp = objects(events["signed_up"]).map((item) => {
    const answers = answersText(item["answers"], item["questions"]);
    return entry(
      str(item["starts_at"]),
      `<div><strong>${escapeHtml(str(item["title"]) ?? "")}</strong> ${
        place(item)
      }</div><div class="muted">${
        escapeHtml(
          `${str(item["answer"]) ?? ""}${
            item["cancelled"] === true ? " · cancelled" : ""
          }${item["checked_in_at"] ? " · checked in" : ""}`,
        )
      }</div>${
        answers ? `<div class="body">${escapeHtml(answers)}</div>` : ""
      }`,
    );
  }).join("");
  const waiting = objects(events["waiting"]).map((item) =>
    entry(
      str(item["starts_at"]),
      `<div><strong>${escapeHtml(str(item["title"]) ?? "")}</strong></div>`,
    )
  ).join("");
  const checkIns = objects(events["check_ins"]).map((item) =>
    entry(
      str(item["checked_in_at"]),
      `<div><strong>${escapeHtml(str(item["title"]) ?? "")}</strong></div>`,
    )
  ).join("");
  const photos = objects(events["photos"]).map((photo) => {
    const link = ref(
      str(photo["bucket"]) ?? CHAT_IMAGES_BUCKET,
      photo["path"],
    )?.download_url;
    return entry(
      str(photo["added_at"]),
      `<div><strong>${escapeHtml(str(photo["title"]) ?? "")}</strong></div>${
        link
          ? `<div><a href="${escapeHtml(link)}">Picture (link)</a></div>`
          : ""
      }`,
    );
  }).join("");
  const made = objects(events["events_made"]).map((item) => {
    const questions = objects(item["questions"]);
    const bits = [
      item["repeats"] ? `repeats ${String(item["repeats"])}` : "",
      item["capacity"] ? `capacity ${String(item["capacity"])}` : "",
      questions.length > 0 ? `${questions.length} question(s)` : "",
    ].filter((bit) => bit !== "").join(" · ");
    return entry(
      str(item["starts_at"]),
      `<div><strong>${escapeHtml(str(item["title"]) ?? "")}</strong> ${
        place(item)
      }</div>${bits ? `<div class="muted">${escapeHtml(bits)}</div>` : ""}`,
    );
  }).join("");
  const calls = objects(events["calls_made"]).map((item) => {
    const bits = [
      item["cancelled"] === true ? "cancelled" : "",
      item["repeats"] ? `repeats ${String(item["repeats"])}` : "",
      item["link_turned_off"] === true ? "link turned off" : "",
    ].filter((bit) => bit !== "").join(" · ");
    return entry(
      str(item["starts_at"]),
      `<div><strong>${escapeHtml(str(item["title"]) ?? "")}</strong></div>${
        bits ? `<div class="muted">${escapeHtml(bits)}</div>` : ""
      }`,
    );
  }).join("");
  return page(
    "Events — your WeCord data",
    `${backLink()}<h1>Events</h1>
<p class="muted">The events you signed up to (with the answers you gave), the
waiting lists you were on, where you checked in, the pictures you added and the
events you made. Other people's answers, names and pictures are not copied.</p>
${section("Signed up", signedUp, "None.")}
${section("Waiting list", waiting, "None.")}
${section("Checked in", checkIns, "None.")}
${section("Pictures you added", photos, "None.")}
${section("Events you made", made, "None.")}
${section("Calls you scheduled", calls, "None.")}`,
  );
}

/** The titles circles gave me and my honors (C7). */
export function buildHonorsHtml(data: ExportData): string {
  const honors = isObject(data.honors) ? data.honors : {};
  const titles = objects(honors["titles"]).map((t) =>
    entry(
      str(t["given_at"]),
      `<div><strong>${
        escapeHtml(str(t["title"]) ?? "")
      }</strong> <span class="muted">${
        escapeHtml(str(t["circle_name"]) ?? "")
      }</span></div>`,
    )
  ).join("");
  const earned = objects(honors["honors"]).map((h) => {
    const kind = str(h["kind"]) === "streak"
      ? `${String(h["level"] ?? "")}-day streak`
      : `Week level ${String(h["level"] ?? "")}`;
    return entry(
      str(h["awarded_at"]),
      `<div><strong>${escapeHtml(kind)}</strong> <span class="muted">${
        escapeHtml(str(h["circle_name"]) ?? "")
      }</span></div>`,
    );
  }).join("");
  const streaks = objects(honors["streaks"]).map((s) =>
    entry(
      str(s["as_of"]),
      `<div><strong>${
        escapeHtml(str(s["circle_name"]) ?? "")
      }</strong> <span class="muted">streak ${
        escapeHtml(String(s["current_streak"] ?? 0))
      } days, best ${escapeHtml(String(s["best_streak"] ?? 0))}</span></div>`,
    )
  ).join("");
  const out = objects(honors["opted_out"]).map((o) =>
    entry(
      str(o["since"]),
      `<div><strong>${escapeHtml(str(o["circle_name"]) ?? "")}</strong></div>`,
    )
  ).join("");
  return page(
    "Circle titles and honors — your WeCord data",
    `${backLink()}<h1>Circle titles and honors</h1>
<p class="muted">The titles circles gave you, the honors you earned from the
days you were active (never the messages), your running streaks, and the
circles where you chose to stay out of honors.</p>
<h2>Titles</h2>
<div class="card">${titles || '<div class="row muted">No titles.</div>'}</div>
<h2>Honors</h2>
<div class="card">${earned || '<div class="row muted">No honors.</div>'}</div>
<h2>Streaks</h2>
<div class="card">${streaks || '<div class="row muted">No streaks.</div>'}</div>
<h2>Circles you stay out of</h2>
<div class="card">${out || '<div class="row muted">None.</div>'}</div>`,
  );
}

/** Comments on notes, personal templates and published pages (D5). */
export function buildNoteExtrasHtml(data: ExportData): string {
  const extras = isObject(data.noteExtras) ? data.noteExtras : {};
  const comments = objects(extras["comments"]).map((comment) =>
    entry(
      str(comment["created_at"]),
      `<div><strong>${
        escapeHtml(str(comment["note_title"]) || "Untitled note")
      }</strong> ${comment["reply"] === true ? tag("reply") : ""}${
        comment["resolved"] === true ? tag("resolved") : ""
      }</div>${
        str(comment["quoted"])
          ? `<div class="muted">on “${
            escapeHtml(str(comment["quoted"]) ?? "")
          }”</div>`
          : ""
      }${text(comment["body"])}`,
    )
  ).join("");
  const templates = objects(extras["templates"]).map((template) =>
    entry(
      str(template["created_at"]),
      `<div><strong>${
        escapeHtml(str(template["name"]) ?? "")
      }</strong> <span class="muted">${
        escapeHtml(
          String(
            Array.isArray(template["blocks"]) ? template["blocks"].length : 0,
          ),
        )
      } blocks</span></div>`,
    )
  ).join("");
  const published = objects(extras["published"]).map((note) =>
    entry(
      str(note["published_at"]),
      `<div><strong>${
        escapeHtml(str(note["note_title"]) || "Untitled note")
      }</strong> ${
        note["allow_indexing"] === true ? tag("search engines allowed") : ""
      }</div>`,
    )
  ).join("");
  return page(
    "Note comments, templates and pages — your WeCord data",
    `${backLink()}<h1>Note comments, templates and pages</h1>
<p class="muted">Only what you wrote. The links of pages you published are
secret and are not included; withdrawing a page turns its link off.</p>
<h2>Comments you wrote</h2>
<div class="card">${
      comments || '<div class="row muted">No comments.</div>'
    }</div>
<h2>Your templates</h2>
<div class="card">${
      templates || '<div class="row muted">No templates.</div>'
    }</div>
<h2>Pages you published</h2>
<div class="card">${
      published || '<div class="row muted">No published pages.</div>'
    }</div>`,
  );
}

/** The HTML pages of the new sections, and the index rows that link them. */
export function buildSectionPages(
  data: ExportData,
): { path: string; label: string; summary: string; content: string }[] {
  const out: {
    path: string;
    label: string;
    summary: string;
    content: string;
  }[] = [];
  const moments = data.moments;
  if (moments) {
    out.push({
      path: "pages/moments.html",
      label: "Moments, friend tags and starred friends",
      summary: `${moments.posts.length} post${
        moments.posts.length === 1 ? "" : "s"
      } · ${moments.comments.length} comment${
        moments.comments.length === 1 ? "" : "s"
      } · ${moments.likes.length} like${
        moments.likes.length === 1 ? "" : "s"
      } · ${moments.tags.length} tag${
        moments.tags.length === 1 ? "" : "s"
      } · ${moments.stars.length} starred`,
      content: buildMomentsHtml(data),
    });
  }
  if (data.forms) {
    out.push({
      path: "pages/forms.html",
      label: "Forms",
      summary: `${data.forms.length}`,
      content: buildFormsHtml(data),
    });
  }
  if (data.feedback) {
    out.push({
      path: "pages/feedback.html",
      label: "Feedback and help",
      summary: `${data.feedback.length}`,
      content: buildFeedbackHtml(data),
    });
  }
  if (data.stories) {
    out.push({
      path: "pages/stories.html",
      label: "Daily",
      summary: `${objects(data.stories["stories"]).length} up now`,
      content: buildStoriesHtml(data),
    });
  }
  if (data.taskExtras) {
    out.push({
      path: "pages/task_extras.html",
      label: "Task list fields, subtasks and repeats",
      summary: `${
        objects(
          isObject(data.taskExtras) ? data.taskExtras["lists"] : null,
        ).length
      } lists`,
      content: buildTaskExtrasHtml(data),
    });
  }
  if (data.favorites) {
    const items = objects(data.favorites["items"]).length;
    const folders = objects(data.favorites["folders"]).length;
    out.push({
      path: "pages/favorites.html",
      label: "Favorites",
      summary: `${items} kept · ${folders} folder${folders === 1 ? "" : "s"}`,
      content: buildFavoritesHtml(data),
    });
  }
  if (data.aiDigest) {
    const followed = objects(
      isObject(data.aiDigest) ? data.aiDigest["subscriptions"] : null,
    );
    out.push({
      path: "pages/ai_digest.html",
      label: "Daily digest",
      summary: `${followed.length} chat${
        followed.length === 1 ? "" : "s"
      } followed`,
      content: buildAiDigestHtml(data),
    });
  }
  if (data.knowledge) {
    const counts = (key: string) =>
      objects(isObject(data.knowledge) ? data.knowledge[key] : null).length;
    out.push({
      path: "pages/knowledge.html",
      label: "Knowledge base pages",
      summary: `${counts("pages_made")} made · ${counts("pages_read")} read`,
      content: buildKnowledgeHtml(data),
    });
  }
  if (data.honors) {
    const counts = (key: string) =>
      objects(isObject(data.honors) ? data.honors[key] : null).length;
    out.push({
      path: "pages/honors.html",
      label: "Circle titles and honors",
      summary: `${counts("titles")} titles · ${counts("honors")} honors`,
      content: buildHonorsHtml(data),
    });
  }
  if (data.channelPosts) {
    const counts = (key: string) =>
      objects(isObject(data.channelPosts) ? data.channelPosts[key] : null)
        .length;
    out.push({
      path: "pages/channel_posts.html",
      label: "Picture posts and Q&A",
      summary: `${counts("media_posts")} picture posts · ${
        counts("questions")
      } questions`,
      content: buildChannelPostsHtml(data),
    });
  }
  if (data.events2) {
    const counts = (key: string) =>
      objects(isObject(data.events2) ? data.events2[key] : null).length;
    out.push({
      path: "pages/events.html",
      label: "Events",
      summary: `${counts("signed_up")} signed up · ${
        counts("events_made")
      } made`,
      content: buildEventsHtml(data),
    });
  }
  if (data.noteExtras) {
    const counts = (key: string) =>
      objects(isObject(data.noteExtras) ? data.noteExtras[key] : null).length;
    out.push({
      path: "pages/note_extras.html",
      label: "Note comments, templates and published pages",
      summary: `${counts("comments")} comment${
        counts("comments") === 1 ? "" : "s"
      } · ${counts("templates")} template${
        counts("templates") === 1 ? "" : "s"
      } · ${counts("published")} published`,
      content: buildNoteExtrasHtml(data),
    });
  }
  const extras = data.extras;
  if (extras) {
    out.push(
      {
        path: "pages/chains.html",
        label: "Group chains",
        summary: `${extras.chains.length}`,
        content: buildChainsHtml(data),
      },
      {
        path: "pages/notes.html",
        label: "Notes and task lists",
        summary: `${extras.notes.length} note${
          extras.notes.length === 1 ? "" : "s"
        } · ${extras.taskLists.length} list${
          extras.taskLists.length === 1 ? "" : "s"
        }`,
        content: buildNotesHtml(data),
      },
      {
        path: "pages/saved.html",
        label: "Saved messages, reminders and scheduled messages",
        summary:
          `${extras.savedMessages.length} saved · ${extras.reminders.length} reminders · ${extras.scheduledMessages.length} scheduled`,
        content: buildSavedHtml(data),
      },
      {
        path: "pages/wallpapers.html",
        label: "Chat wallpapers",
        summary: `${extras.wallpapers.length}`,
        content: buildWallpapersHtml(data),
      },
    );
  }
  return out;
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
pages/                Readable pages for Moments, group chains, notes and
                      task lists, saved messages, reminders and scheduled
                      messages, and chat wallpapers.
data/moments.json     Your Moments posts, the comments you wrote, your likes
                      and Moments settings.
data/friend_tags.json Your friend tags and starred friends.
data/chains.json      Group chains you started or joined (your own line).
data/forms.json       Forms you made or answered (your own answers).
data/feedback.json    Feedback you sent and the replies you got.
data/ai_digest.json   Your daily digest settings and the chats you follow.
data/note_extras.json The comments you wrote on notes, your note templates
                      and the pages you published (without their links).
data/stories.json     Your dailies still up, close friends and reports.
data/favorites.json   Your favorites: folders, tags, links, notes and what
                      you kept (other people's words are not copied).
data/knowledge.json   The pages you made in circle knowledge bases and the
                      pages you read (the words you wrote are in notes.json).
data/honors.json      The titles circles gave you, your honors and streaks, and
                      the circles you stay out of honors in.
data/channel_posts.json The posts you made in media channels (with a link to
                      each picture), the questions you asked in Q&A channels
                      and where an answer of yours was accepted.
data/events.json      The events you signed up to (with your answers), waited
                      for, checked in to, the pictures you added and the
                      events you made, and the calls you scheduled (never
                      a call link's code or other people's answers).
data/moments_more.json The Moments you pinned, the people you reminded to
                      read, the reminders you got (never their words) and
                      the pictures on your comments.
data/notes.json       Notes (the lines you wrote) in your chats.
data/task_lists.json  Task lists (the items you created).
data/task_extras.json Fields, values, subtasks and repeats of those items.
data/saved_messages.json, data/reminders.json, data/scheduled_messages.json
data/wallpapers.json  Your chat wallpapers.
files/                Your own photos, videos, covers and wallpapers that
                      fit into this archive.

Only your own content is here. Other people appear by name only. Links to
the files you sent, and to files that did not fit into this archive, expire
when this export does (7 days after it was made). Download what you want to
keep.
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

  const sectionPages = buildSectionPages(data);
  const files: ExportFile[] = [
    { path: "README.txt", content: readme },
    { path: "index.html", content: buildIndexHtml(data, pages, sectionPages) },
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
  for (const entry of sectionPages) {
    files.push({ path: entry.path, content: entry.content });
  }
  for (const entry of buildSectionJson(data)) {
    files.push({ path: entry.path, content: pretty(entry.value) });
  }
  return files;
}

/** The finished archive: the text files and my own files (stored as they are). */
export function buildExportZip(data: ExportData): Uint8Array {
  const entries: Record<string, Uint8Array | [Uint8Array, { level: 0 }]> = {};
  for (const file of buildExportFiles(data)) {
    entries[file.path] = strToU8(file.content);
  }
  for (const blob of data.files) {
    // Photos and videos are compressed already.
    entries[blob.zipPath] = [blob.bytes, { level: 0 }];
  }
  return zipSync(entries, { level: 6 });
}
