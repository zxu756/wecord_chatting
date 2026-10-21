// Reads one person's data for the export with the service role, always
// filtered to that person: their profile and account, friends, the
// conversations they are in (names only), the messages they sent, their
// circles and settings. Every part is read on its own, so one that cannot be
// read (a table a deployment does not have yet) is listed in `skipped`
// instead of failing the whole export.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  attachmentsToSign,
  channelPostFilesToSign,
  EXPORT_LIFETIME_MS,
  type ExportBlob,
  type ExportCircle,
  type ExportConversation,
  type ExportData,
  type ExportExtras,
  exportFileZipPath,
  type ExportFriend,
  type ExportMessage,
  type ExportMoments,
  type ExportStage,
  favoriteFilesToSign,
  feedbackFilesToSign,
  formFilesToSign,
  type Json,
  momentsMoreFilesToSign,
  type OwnedFile,
  ownedFiles,
  storyFilesToSign,
} from "./export_builder.ts";

/** The most messages one export carries. */
export const MAX_MESSAGES = 200_000;
const PAGE_SIZE = 1000;
const SIGN_BATCH = 100;

/**
 * What goes into the ZIP itself of the person's own Moments photos, videos,
 * cover and wallpapers (the bucket for exports holds 100 MB per file): a file
 * above MAX_FILE_BYTES, files past MAX_TOTAL_FILE_BYTES or MAX_FILE_COUNT, and
 * files not fetched within FILE_TIME_BUDGET_MS are linked with a signed URL
 * instead, like the files in messages.
 */
export const MAX_FILE_BYTES = 10 * 1024 * 1024;
export const MAX_TOTAL_FILE_BYTES = 40 * 1024 * 1024;
export const MAX_FILE_COUNT = 500;
export const FILE_TIME_BUDGET_MS = 90_000;

type Row = Record<string, unknown>;

function text(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

export interface CollectOptions {
  userId: string;
  now: Date;
  /** Overrides for the caps on files put into the ZIP (tests). */
  fileLimits?: {
    maxFileBytes?: number;
    maxTotalBytes?: number;
    maxCount?: number;
    timeBudgetMs?: number;
  };
  /** Called as each step starts, with how far along the export is. */
  onStage?: (stage: ExportStage, detail?: string) => Promise<void> | void;
}

async function tryRead<T>(
  skipped: string[],
  name: string,
  read: () => Promise<T>,
  fallback: T,
): Promise<T> {
  try {
    return await read();
  } catch {
    skipped.push(name);
    return fallback;
  }
}

/** Throws the query error, so tryRead can list the part as skipped. */
function rows<T>(result: { data: T[] | null; error: unknown }): T[] {
  if (result.error) throw result.error;
  return result.data ?? [];
}

export async function collectExportData(
  admin: SupabaseClient,
  options: CollectOptions,
): Promise<ExportData> {
  const { userId, now } = options;
  const stage = async (name: ExportStage, detail?: string) => {
    await options.onStage?.(name, detail);
  };
  const skipped: string[] = [];

  await stage("profile");
  const profile = await tryRead<Row | null>(skipped, "profile", async () => {
    const found = await admin.from("profiles").select("*").eq("id", userId)
      .maybeSingle();
    if (found.error) throw found.error;
    return found.data as Row | null;
  }, null);
  const account = await tryRead(skipped, "account", async () => {
    const found = await admin.auth.admin.getUserById(userId);
    if (found.error) throw found.error;
    return found.data.user;
  }, null);

  const settings: Record<string, unknown> = {};
  const privacy = await tryRead<Row[]>(
    skipped,
    "privacy settings",
    async () =>
      rows(
        await admin.from("user_privacy_settings").select("*").eq(
          "user_id",
          userId,
        ),
      ),
    [],
  );
  if (privacy[0]) settings["privacy"] = privacy[0];
  const circleNotifications = await tryRead<Row[]>(
    skipped,
    "notification settings",
    async () =>
      rows(
        await admin.from("circle_notification_settings").select("*").eq(
          "user_id",
          userId,
        ),
      ),
    [],
  );
  settings["circle_notifications"] = circleNotifications;

  await stage("friends");
  const friendships = await tryRead<Row[]>(skipped, "friends", async () =>
    rows(
      await admin.from("friendships").select("*").or(
        `user_low_id.eq.${userId},user_high_id.eq.${userId}`,
      ),
    ), []);
  const friendIds = friendships.map((row) =>
    row["user_low_id"] === userId ? row["user_high_id"] : row["user_low_id"]
  ).filter((id): id is string => typeof id === "string");
  const requests = await tryRead<Row[]>(
    skipped,
    "friend requests",
    async () =>
      rows(
        await admin.from("friend_requests").select("*").or(
          `requester_id.eq.${userId},receiver_id.eq.${userId}`,
        ),
      ),
    [],
  );
  const blocks = await tryRead<Row[]>(
    skipped,
    "blocked users",
    async () =>
      rows(await admin.from("blocks").select("*").eq("blocker_id", userId)),
    [],
  );

  const otherIds = new Set<string>(friendIds);
  for (const block of blocks) {
    if (typeof block["blocked_id"] === "string") {
      otherIds.add(block["blocked_id"]);
    }
  }
  for (const request of requests) {
    for (const key of ["requester_id", "receiver_id"]) {
      const id = request[key];
      if (typeof id === "string" && id !== userId) otherIds.add(id);
    }
  }
  const people = new Map<string, Row>();
  for (const batch of chunk([...otherIds], 200)) {
    const found = await tryRead<Row[]>(skipped, "people", async () =>
      rows(
        await admin.from("profiles").select("id, username, display_name").in(
          "id",
          batch,
        ),
      ), []);
    for (const person of found) people.set(person["id"] as string, person);
  }
  const personName = (id: unknown) => {
    const person = typeof id === "string" ? people.get(id) : undefined;
    return {
      id: typeof id === "string" ? id : null,
      username: text(person?.["username"]),
      display_name: text(person?.["display_name"]),
    };
  };
  const friends: ExportFriend[] = friendships.map((row) => {
    const low = row["user_low_id"] === userId;
    const other = personName(low ? row["user_high_id"] : row["user_low_id"]);
    return {
      id: other.id ?? "",
      username: other.username ?? "",
      displayName: other.display_name ?? "",
      remark: text(low ? row["user_low_remark"] : row["user_high_remark"]),
      since: text(row["created_at"]),
    };
  });
  const friendRequests: Json[] = requests.map((row) => ({
    status: row["status"],
    direction: row["requester_id"] === userId ? "sent" : "received",
    person: personName(
      row["requester_id"] === userId ? row["receiver_id"] : row["requester_id"],
    ),
    created_at: row["created_at"],
  }));
  const blocked: Json[] = blocks.map((row) => ({
    person: personName(row["blocked_id"]),
    reason: row["reason"] ?? null,
    blocked_at: row["created_at"],
  }));

  await stage("conversations");
  const memberships = await tryRead<Row[]>(
    skipped,
    "conversations",
    async () =>
      rows(
        await admin.from("conversation_members").select("*").eq(
          "user_id",
          userId,
        ),
      ),
    [],
  );
  const conversationIds = memberships.map((row) => row["conversation_id"])
    .filter((id): id is string => typeof id === "string");
  const conversationRows = new Map<string, Row>();
  for (const batch of chunk(conversationIds, 100)) {
    const found = await tryRead<Row[]>(
      skipped,
      "conversations",
      async () =>
        rows(
          await admin.from("conversations").select(
            "id, type, title, created_at",
          )
            .in("id", batch),
        ),
      [],
    );
    for (const row of found) conversationRows.set(row["id"] as string, row);
  }
  // Direct chats are named after the other person.
  const directPeers = new Map<string, string>();
  const directIds = conversationIds.filter((id) =>
    conversationRows.get(id)?.["type"] === "direct"
  );
  for (const batch of chunk(directIds, 100)) {
    const found = await tryRead<Row[]>(
      skipped,
      "direct chats",
      async () =>
        rows(
          await admin.from("conversation_members").select(
            "conversation_id, user_id",
          ).in("conversation_id", batch).neq("user_id", userId),
        ),
      [],
    );
    for (const row of found) {
      directPeers.set(
        row["conversation_id"] as string,
        row["user_id"] as string,
      );
    }
  }
  const missingPeers = [...directPeers.values()].filter((id) =>
    !people.has(id)
  );
  for (const batch of chunk(missingPeers, 200)) {
    const found = await tryRead<Row[]>(skipped, "people", async () =>
      rows(
        await admin.from("profiles").select("id, username, display_name").in(
          "id",
          batch,
        ),
      ), []);
    for (const person of found) people.set(person["id"] as string, person);
  }
  // Circle channels are named after the channel and their circle.
  const channelRows = await tryRead<Row[]>(skipped, "channels", async () => {
    const all: Row[] = [];
    for (const batch of chunk(conversationIds, 100)) {
      all.push(
        ...rows(
          await admin.from("circle_channels").select(
            "conversation_id, name, circle_id",
          ).in("conversation_id", batch),
        ),
      );
    }
    return all;
  }, []);
  const channelByConversation = new Map<string, Row>();
  for (const row of channelRows) {
    channelByConversation.set(row["conversation_id"] as string, row);
  }
  const circleIds = [
    ...new Set(
      channelRows.map((row) => row["circle_id"]).filter((id): id is string =>
        typeof id === "string"
      ),
    ),
  ];
  const circleNames = new Map<string, string>();
  for (const batch of chunk(circleIds, 100)) {
    const found = await tryRead<Row[]>(
      skipped,
      "circle names",
      async () =>
        rows(await admin.from("circles").select("id, name").in("id", batch)),
      [],
    );
    for (const row of found) {
      circleNames.set(row["id"] as string, row["name"] as string);
    }
  }
  const conversations: ExportConversation[] = memberships.map((member) => {
    const id = member["conversation_id"] as string;
    const row = conversationRows.get(id);
    const channel = channelByConversation.get(id);
    const peer = directPeers.get(id);
    const peerProfile = peer ? people.get(peer) : undefined;
    const kind = text(row?.["type"]) ?? "unknown";
    const name = kind === "direct"
      ? text(peerProfile?.["display_name"]) ??
        text(peerProfile?.["username"]) ??
        "Direct message"
      : channel
      ? `#${text(channel["name"]) ?? "channel"}`
      : text(row?.["title"]) ?? "Untitled";
    return {
      id,
      kind,
      name,
      circleName: channel
        ? circleNames.get(channel["circle_id"] as string) ?? null
        : null,
      joinedAt: text(member["joined_at"]),
      role: text(member["role"]),
      createdAt: text(row?.["created_at"]),
    };
  });

  await stage("messages");
  const messages: ExportMessage[] = [];
  await tryRead(skipped, "messages", async () => {
    let cursor: { at: string; id: string } | null = null;
    while (messages.length < MAX_MESSAGES) {
      let query = admin.from("messages").select(
        "id, conversation_id, type, body, attachment, created_at, edited_at, recalled_at",
      ).eq("sender_id", userId).order("created_at", { ascending: true })
        .order("id", { ascending: true }).limit(PAGE_SIZE);
      if (cursor) {
        query = query.or(
          `created_at.gt.${cursor.at},and(created_at.eq.${cursor.at},id.gt.${cursor.id})`,
        );
      }
      const page = rows(await query);
      for (const row of page as Row[]) {
        messages.push({
          id: row["id"] as string,
          conversationId: row["conversation_id"] as string,
          type: text(row["type"]) ?? "text",
          body: text(row["body"]) ?? "",
          attachment: (row["attachment"] ?? null) as Json | null,
          createdAt: row["created_at"] as string,
          editedAt: text(row["edited_at"]),
          recalledAt: text(row["recalled_at"]),
        });
      }
      if (page.length < PAGE_SIZE) break;
      const last = page[page.length - 1] as Row;
      cursor = { at: last["created_at"] as string, id: last["id"] as string };
      await stage("messages", `${messages.length}`);
    }
  }, undefined);

  await stage("circles");
  const circleMemberships = await tryRead<Row[]>(
    skipped,
    "circles",
    async () =>
      rows(
        await admin.from("circle_members").select("*").eq("user_id", userId),
      ),
    [],
  );
  const memberCircleIds = circleMemberships.map((row) => row["circle_id"])
    .filter((id): id is string => typeof id === "string");
  const memberCircleNames = new Map<string, string>();
  for (const batch of chunk(memberCircleIds, 100)) {
    const found = await tryRead<Row[]>(
      skipped,
      "circle names",
      async () =>
        rows(await admin.from("circles").select("id, name").in("id", batch)),
      [],
    );
    for (const row of found) {
      memberCircleNames.set(row["id"] as string, row["name"] as string);
    }
  }
  const levelByCircle = new Map<string, string>();
  for (const row of circleNotifications) {
    const level = text(row["level"]) ?? text(row["notification_level"]);
    if (typeof row["circle_id"] === "string" && level) {
      levelByCircle.set(row["circle_id"], level);
    }
  }
  const circles: ExportCircle[] = circleMemberships.map((row) => {
    const id = row["circle_id"] as string;
    return {
      id,
      name: memberCircleNames.get(id) ?? "Circle",
      joinedAt: text(row["joined_at"]) ?? text(row["created_at"]),
      nickname: text(row["nickname"]),
      notificationLevel: levelByCircle.get(id) ?? null,
    };
  });

  // Moments, tags and stars; then chains, notes, lists and the rest. Each is
  // one database function that reads only this person's rows.
  await stage("moments");
  const moments = await tryRead<ExportMoments | null>(
    skipped,
    "moments",
    async () => {
      const found = await callExport(admin, "export_my_moments", userId);
      return {
        settings: object(found["settings"]),
        friendPrefs: list(found["friend_prefs"]),
        posts: list(found["posts"]),
        comments: list(found["comments"]),
        likes: list(found["likes"]),
        tags: list(found["tags"]),
        stars: list(found["stars"]),
      };
    },
    null,
  );
  await stage("more");
  const extras = await tryRead<ExportExtras | null>(
    skipped,
    "notes, lists and more",
    async () => {
      const found = await callExport(admin, "export_my_extras", userId);
      return {
        chains: list(found["chains"]),
        notes: list(found["notes"]),
        taskLists: list(found["task_lists"]),
        savedMessages: list(found["saved_messages"]),
        reminders: list(found["reminders"]),
        scheduledMessages: list(found["scheduled_messages"]),
        wallpapers: list(found["wallpapers"]),
      };
    },
    null,
  );

  // Forms I made or answered: my own answers (export_my_forms).
  const forms = await tryRead<Row[] | null>(
    skipped,
    "forms",
    async () => {
      const result = await admin.rpc("export_my_forms", {
        target_user_id: userId,
      });
      if (result.error) throw result.error;
      return list(result.data);
    },
    null,
  );

  // The feedback I sent and the replies to it (export_my_feedback).
  const feedback = await tryRead<Row[] | null>(
    skipped,
    "feedback",
    async () => {
      const result = await admin.rpc("export_my_feedback", {
        target_user_id: userId,
      });
      if (result.error) throw result.error;
      return list(result.data);
    },
    null,
  );

  // The daily digest I set up: the switch, time and chats (export_my_ai_digest).
  const aiDigest = await tryRead<Row | null>(
    skipped,
    "daily digest",
    async () => {
      const result = await admin.rpc("export_my_ai_digest", {
        target_user_id: userId,
      });
      if (result.error) throw result.error;
      return object(result.data);
    },
    null,
  );

  // Comments I wrote on notes, my templates, the pages I published
  // (export_my_note_extras).
  const noteExtras = await tryRead<Row | null>(
    skipped,
    "note comments and templates",
    async () => {
      const result = await admin.rpc("export_my_note_extras", {
        target_user_id: userId,
      });
      if (result.error) throw result.error;
      return object(result.data);
    },
    null,
  );

  // The dailies I still have up and my close friends (export_my_stories).
  const stories = await tryRead<Row | null>(
    skipped,
    "daily",
    async () => {
      const result = await admin.rpc("export_my_stories", {
        target_user_id: userId,
      });
      if (result.error) throw result.error;
      return object(result.data);
    },
    null,
  );

  // The fields, values, subtasks and repeat rules of my task lists
  // (export_my_task_extras).
  const taskExtras = await tryRead<Row | null>(
    skipped,
    "task list fields",
    async () => {
      const result = await admin.rpc("export_my_task_extras", {
        target_user_id: userId,
      });
      if (result.error) throw result.error;
      return object(result.data);
    },
    null,
  );

  // What I kept: folders, tags, links, notes (export_my_saved_items).
  const favorites = await tryRead<Row | null>(
    skipped,
    "favorites",
    async () => {
      const result = await admin.rpc("export_my_saved_items", {
        target_user_id: userId,
      });
      if (result.error) throw result.error;
      return object(result.data);
    },
    null,
  );

  // Moments 2.0: pins, reminders and the pictures on my comments
  // (export_my_moments_more).
  const momentsMore = await tryRead<Row | null>(
    skipped,
    "pins and reminders",
    async () => {
      const result = await admin.rpc("export_my_moments_more", {
        target_user_id: userId,
      });
      if (result.error) throw result.error;
      return object(result.data);
    },
    null,
  );

  // The pages I made in circle knowledge bases and the ones I read
  // (export_my_knowledge).
  const knowledge = await tryRead<Row | null>(
    skipped,
    "knowledge base pages",
    async () => {
      const result = await admin.rpc("export_my_knowledge", {
        target_user_id: userId,
      });
      if (result.error) throw result.error;
      return object(result.data);
    },
    null,
  );

  // The titles circles gave me and my honors (export_my_honors).
  const honors = await tryRead<Row | null>(
    skipped,
    "circle titles and honors",
    async () => {
      const result = await admin.rpc("export_my_honors", {
        target_user_id: userId,
      });
      if (result.error) throw result.error;
      return object(result.data);
    },
    null,
  );

  // What I made in media and Q&A channels (export_my_channel_posts).
  const channelPosts = await tryRead<Row | null>(
    skipped,
    "picture posts and questions",
    async () => {
      const result = await admin.rpc("export_my_channel_posts", {
        target_user_id: userId,
      });
      if (result.error) throw result.error;
      return object(result.data);
    },
    null,
  );

  await stage("attachments");
  const linksExpireAt = new Date(now.getTime() + EXPORT_LIFETIME_MS);
  const attachmentLinks: Record<string, string> = {};
  const byBucket = new Map<string, string[]>();
  for (const { bucket, path } of attachmentsToSign(messages)) {
    byBucket.set(bucket, [...(byBucket.get(bucket) ?? []), path]);
  }
  // The pictures I attached to answers of forms are linked.
  for (const { bucket, path } of formFilesToSign(forms ?? [])) {
    byBucket.set(bucket, [...(byBucket.get(bucket) ?? []), path]);
  }
  // The screenshots I attached to feedback are linked.
  for (const { bucket, path } of feedbackFilesToSign(feedback ?? [])) {
    byBucket.set(bucket, [...(byBucket.get(bucket) ?? []), path]);
  }
  // The files of my dailies are linked (they end in a day anyway).
  for (const { bucket, path } of storyFilesToSign(stories)) {
    byBucket.set(bucket, [...(byBucket.get(bucket) ?? []), path]);
  }
  // The pictures of my notes are linked.
  for (const { bucket, path } of favoriteFilesToSign(favorites)) {
    byBucket.set(bucket, [...(byBucket.get(bucket) ?? []), path]);
  }
  // The pictures on my comments are linked.
  for (const { bucket, path } of momentsMoreFilesToSign(momentsMore)) {
    byBucket.set(bucket, [...(byBucket.get(bucket) ?? []), path]);
  }
  // The pictures of my media posts are linked.
  for (const { bucket, path } of channelPostFilesToSign(channelPosts)) {
    byBucket.set(bucket, [...(byBucket.get(bucket) ?? []), path]);
  }
  // My own photos, videos, covers and wallpapers go into the ZIP while they
  // fit; the rest is linked.
  let files: ExportBlob[] = [];
  await tryRead(skipped, "photos and videos", async () => {
    const wanted = ownedFiles(userId, moments, extras);
    const fetched = await fetchOwnFiles(
      admin,
      wanted,
      options.fileLimits ?? {},
    );
    files = fetched.blobs;
    for (const { bucket, path } of fetched.leftOver) {
      byBucket.set(bucket, [...(byBucket.get(bucket) ?? []), path]);
    }
  }, undefined);
  await tryRead(skipped, "file links", async () => {
    for (const [bucket, paths] of byBucket) {
      for (const batch of chunk(paths, SIGN_BATCH)) {
        const signed = await admin.storage.from(bucket).createSignedUrls(
          batch,
          Math.floor(EXPORT_LIFETIME_MS / 1000),
        );
        if (signed.error) continue;
        for (const entry of signed.data) {
          if (entry.path && entry.signedUrl && !entry.error) {
            attachmentLinks[`${bucket}/${entry.path}`] = entry.signedUrl;
          }
        }
      }
    }
  }, undefined);

  return {
    generatedAt: now.toISOString(),
    user: {
      id: userId,
      email: account?.email ?? null,
      createdAt: account?.created_at ?? null,
      lastSignInAt: account?.last_sign_in_at ?? null,
    },
    profile,
    settings,
    friends,
    friendRequests,
    blocked,
    conversations,
    messages,
    circles,
    moments,
    extras,
    forms,
    feedback,
    aiDigest,
    noteExtras,
    stories,
    taskExtras,
    favorites,
    momentsMore,
    knowledge,
    honors,
    channelPosts,
    files,
    attachmentLinks,
    linksExpireAt: linksExpireAt.toISOString(),
    skipped: [...new Set(skipped)],
  };
}

function list(value: unknown): Row[] {
  return Array.isArray(value)
    ? value.filter((item): item is Row =>
      typeof item === "object" && item !== null && !Array.isArray(item)
    )
    : [];
}

function object(value: unknown): Row | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Row
    : null;
}

/** Calls one of the export_my_* functions, which read only [userId]'s rows. */
async function callExport(
  admin: SupabaseClient,
  name: string,
  userId: string,
): Promise<Row> {
  const result = await admin.rpc(name, { target_user_id: userId });
  if (result.error) throw result.error;
  const found = object(result.data);
  if (!found) throw new Error(`${name} returned nothing`);
  return found;
}

/**
 * Downloads the person's own files into the ZIP, within the caps; returns
 * the ones that went in and the ones left over (to be linked instead).
 */
async function fetchOwnFiles(
  admin: SupabaseClient,
  files: OwnedFile[],
  limits: NonNullable<CollectOptions["fileLimits"]>,
): Promise<{ blobs: ExportBlob[]; leftOver: OwnedFile[] }> {
  const maxFile = limits.maxFileBytes ?? MAX_FILE_BYTES;
  const maxTotal = limits.maxTotalBytes ?? MAX_TOTAL_FILE_BYTES;
  const maxCount = limits.maxCount ?? MAX_FILE_COUNT;
  const deadline = Date.now() + (limits.timeBudgetMs ?? FILE_TIME_BUDGET_MS);
  const blobs: ExportBlob[] = [];
  const leftOver: OwnedFile[] = [];
  let total = 0;
  for (const file of files) {
    // A video of unknown size is only linked: it could be large.
    const tooBig = file.size !== null
      ? file.size > maxFile || total + file.size > maxTotal
      : /\.(mp4|mov|m4v|webm)$/i.test(file.path);
    if (tooBig || blobs.length >= maxCount || Date.now() > deadline) {
      leftOver.push(file);
      continue;
    }
    try {
      const downloaded = await admin.storage.from(file.bucket).download(
        file.path,
      );
      if (downloaded.error || !downloaded.data) throw downloaded.error;
      const bytes = new Uint8Array(await downloaded.data.arrayBuffer());
      if (bytes.length > maxFile || total + bytes.length > maxTotal) {
        leftOver.push(file);
        continue;
      }
      total += bytes.length;
      blobs.push({
        key: `${file.bucket}/${file.path}`,
        zipPath: exportFileZipPath(file.bucket, file.path),
        bytes,
      });
    } catch {
      leftOver.push(file);
    }
  }
  return { blobs, leftOver };
}

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}
