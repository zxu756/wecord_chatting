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
  const name = path.split("/").slice(1).join("-").replace(/[^A-Za-z0-9._-]/g, "_");
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
  return `<div class="row"><span>${escapeHtml(label)}</span><span class="muted">${
    escapeHtml(value)
  }</span></div>`;
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
  const posts = moments.posts.map((post) => {
    const photos = objects(post["photos"]).map((photo, n) =>
      fileHtml(ref(MOMENTS_BUCKET, photo["path"]), `Photo ${n + 1}`, true)
    ).join("");
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
      }${str(post["location"]) ? `<div class="muted">📍 ${escapeHtml(str(post["location"])!)}</div>` : ""}${photos}${videoHtml}<div>${
        tag(visibilityLabels[str(post["visibility"]) ?? ""] ?? "Friends")
      }${who ? ` <span class="muted">${escapeHtml(who)}</span>` : ""}</div>`,
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
          ? `<div class="muted">Your post: ${escapeHtml(str(comment["post_text"])!)}</div>`
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
    `<div class="row"><span>${escapeHtml(personName(pref["friend"]))}</span><span class="muted">${
      [
        pref["hide_mine"] === true ? "can’t see your Moments" : "",
        pref["hide_theirs"] === true ? "their Moments hidden from you" : "",
      ].filter((part) => part !== "").join(" · ") || "no special choice"
    }</span></div>`
  ).join("");
  const tags = moments.tags.map((t) =>
    `<div class="row"><span>${escapeHtml(str(t["name"]) ?? "")}</span><span class="muted">${
      escapeHtml(names(t["friends"]) || "nobody yet")
    }</span></div>`
  ).join("");
  const stars = moments.stars.map((s) =>
    `<div class="row"><span>${escapeHtml(personName(s["friend"]))}</span><span class="muted">${
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
        ? fileHtml(ref(MOMENTS_BUCKET, settings["cover_path"]), "Cover photo", false)
        : ""
    }${
      settings ? "" : '<div class="row muted">Default settings.</div>'
    }</div>
${section(`Your posts (${moments.posts.length})`, posts, "No posts.")}
${section(`Comments you wrote (${moments.comments.length})`, comments, "No comments.")}
${section(`Posts you liked (${moments.likes.length})`, likes, "No likes.")}
${section("Choices for friends", choices, "No special choices.")}
${section(`Friend tags (${moments.tags.length})`, tags, "No tags.")}
${section(`Starred friends (${moments.stars.length})`, stars, "No starred friends.")}`,
  );
}

export function buildChainsHtml(data: ExportData): string {
  const chains = data.extras!.chains.map((chain) => {
    const mine = chain["created_by_me"] === true;
    const my = isObject(chain["my_entry"]) ? chain["my_entry"] : null;
    return entry(
      str(chain["created_at"]),
      `<div><strong>${escapeHtml(str(chain["title"]) ?? "")}</strong> ${
        tag(mine ? "you started it" : `started by ${personName(chain["creator"])}`)
      }</div><div class="muted">in ${
        escapeHtml(conversationName(data, chain["conversation_id"]))
      }</div>${text(chain["description"])}${
        str(chain["example"])
          ? `<div class="muted">Example: ${escapeHtml(str(chain["example"])!)}</div>`
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
    const blocks = objects(note["blocks"]).map((block) =>
      text(block["text"])
    ).join("");
    return entry(
      str(note["updated_at"]),
      `<div><strong>${escapeHtml(`${str(note["icon"]) ?? ""} ${str(note["title"]) ?? "Untitled"}`)}</strong> ${
        tag(note["created_by_me"] === true ? "you made it" : "made by someone else")
      }</div><div class="muted">in ${
        escapeHtml(conversationName(data, note["conversation_id"]))
      }</div>${blocks || '<div class="muted">(no text of yours)</div>'}`,
    );
  }).join("");
  const lists = extras.taskLists.map((list) => {
    const items = objects(list["items"]).map((item) =>
      `<div class="body">${
        str(item["completed_at"]) ? "☑" : "☐"
      } ${escapeHtml(str(item["title"]) ?? "")}${
        str(item["details"])
          ? ` <span class="muted">— ${escapeHtml(str(item["details"])!)}</span>`
          : ""
      }${
        str(item["due_at"])
          ? ` <span class="muted">due ${escapeHtml(readableTime(str(item["due_at"])))}</span>`
          : ""
      }${
        names(item["assigned_to"])
          ? ` <span class="muted">for ${escapeHtml(names(item["assigned_to"]))}</span>`
          : ""
      }</div>`
    ).join("");
    return entry(
      str(list["created_at"]),
      `<div><strong>${escapeHtml(`${str(list["icon"]) ?? ""} ${str(list["title"]) ?? "Untitled"}`)}</strong> ${
        tag(list["created_by_me"] === true ? "you made it" : "made by someone else")
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
      `<div class="muted">in ${escapeHtml(conversationName(data, item["conversation_id"]))}${
        str(item["done_at"]) ? ` · done ${escapeHtml(readableTime(str(item["done_at"])))}` : ""
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
      `<div class="muted">in ${escapeHtml(conversationName(data, item["conversation_id"]))}${
        str(item["dismissed_at"]) ? " · dismissed" : ""
      }</div>${
        item["from_you"] === true
          ? text(item["text"])
          : '<div class="muted">About a message from someone else (not included).</div>'
      }`,
    )
  ).join("");
  const scheduled = extras.scheduledMessages.map((item) =>
    entry(
      str(item["send_at"]),
      `<div class="muted">to ${escapeHtml(conversationName(data, item["conversation_id"]))} · ${
        escapeHtml(str(item["status"]) ?? "")
      }</div>${text(item["text"])}`,
    )
  ).join("");
  return page(
    "Saved messages, reminders and scheduled messages — your WeCord data",
    `${backLink()}<h1>Saved messages, reminders and scheduled messages</h1>
<p class="muted">What you saved, set reminders for and scheduled. The text of a
saved or reminded message is included only when you wrote it.</p>
${section(`Saved messages (${extras.savedMessages.length})`, saved, "Nothing saved.")}
${section(`Reminders (${extras.reminders.length})`, reminders, "No reminders.")}
${section(`Scheduled messages (${extras.scheduledMessages.length})`, scheduled, "Nothing scheduled.")}`,
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
        ? fileHtml(ref(WALLPAPERS_BUCKET, wallpaper["photo_path"]), "Wallpaper photo", true)
        : ""
    }<div class="muted">dim ${String(wallpaper["dim"] ?? "")}${
      wallpaper["blur"] === true ? ", blurred" : ""
    }</div></div>`;
  }).join("");
  return page(
    "Chat wallpapers — your WeCord data",
    `${backLink()}<h1>Chat wallpapers</h1>
<p class="muted">The wallpapers you chose, for all chats or for one chat.</p>
<div class="card">${rows || '<div class="row muted">No wallpapers.</div>'}</div>`,
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
      summary: `${moments.posts.length} post${moments.posts.length === 1 ? "" : "s"} · ${moments.comments.length} comment${
        moments.comments.length === 1 ? "" : "s"
      } · ${moments.likes.length} like${moments.likes.length === 1 ? "" : "s"} · ${moments.tags.length} tag${
        moments.tags.length === 1 ? "" : "s"
      } · ${moments.stars.length} starred`,
      content: buildMomentsHtml(data),
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
        summary: `${extras.notes.length} note${extras.notes.length === 1 ? "" : "s"} · ${extras.taskLists.length} list${
          extras.taskLists.length === 1 ? "" : "s"
        }`,
        content: buildNotesHtml(data),
      },
      {
        path: "pages/saved.html",
        label: "Saved messages, reminders and scheduled messages",
        summary: `${extras.savedMessages.length} saved · ${extras.reminders.length} reminders · ${extras.scheduledMessages.length} scheduled`,
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
data/notes.json       Notes (the lines you wrote) in your chats.
data/task_lists.json  Task lists (the items you created).
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
