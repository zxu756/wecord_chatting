// "Download my data". Collects the caller's profile, friends, conversations
// (names), the messages they sent, circles and settings, and their Moments,
// friend tags, group chains, notes, lists, saved messages, reminders,
// scheduled messages and wallpapers (with their own photos and videos while
// they fit) into a ZIP (JSON files plus readable HTML pages), keeps it in the
// private data-exports
// bucket under <user>/<timestamp>.zip for 7 days and hands out a signed link.
//
// POST {}               starts an export (202 {id}); one per person per 24
//                       hours (429 rate_limited, 409 in_progress). The work
//                       goes on after the answer.
// GET                   the person's latest export, or ?id=<id>: status,
//                       stage, progress 0-100 and, once ready, download_url.
// POST {"purge": true}  with the service role key (a scheduler): deletes
//                       exports older than 7 days.
//
// Old exports are also deleted whenever someone starts a new one, so a
// scheduler is optional.
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { collectExportData } from "./collect.ts";
import {
  buildExportZip,
  exportExpiresAt,
  exportObjectPath,
  type ExportStage,
  stageProgress,
} from "./export_builder.ts";

const BUCKET = "data-exports";
const DOWNLOAD_NAME = "wecord-data.zip";
const LINK_SECONDS = 60 * 60;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface ExportRow {
  id: string;
  user_id: string;
  status: "working" | "ready" | "failed" | "expired";
  stage: string;
  detail: string | null;
  progress: number;
  file_path: string | null;
  byte_size: number | null;
  error: string | null;
  created_at: string;
  completed_at: string | null;
  expires_at: string | null;
}

/** Deletes the files of exports past their 7 days. */
export async function purgeExpired(
  admin: SupabaseClient,
  now: Date,
): Promise<number> {
  const { data } = await admin.from("data_exports").select("id, file_path")
    .eq("status", "ready").lt("expires_at", now.toISOString()).limit(200);
  const expired = (data ?? []) as { id: string; file_path: string | null }[];
  const paths = expired.map((row) => row.file_path).filter((
    path,
  ): path is string => typeof path === "string");
  if (paths.length > 0) {
    await admin.storage.from(BUCKET).remove(paths);
  }
  if (expired.length > 0) {
    await admin.from("data_exports").update({
      status: "expired",
      file_path: null,
    }).in("id", expired.map((row) => row.id));
  }
  // Failed attempts are only needed for the rate limit's sake.
  await admin.from("data_exports").delete().in("status", ["failed", "expired"])
    .lt("created_at", new Date(now.getTime() - 7 * 86400_000).toISOString());
  return expired.length;
}

/** A person keeps one export: the newest. */
async function removeOtherExports(
  admin: SupabaseClient,
  userId: string,
  keepId: string,
) {
  const { data } = await admin.from("data_exports").select("id, file_path")
    .eq("user_id", userId).eq("status", "ready").neq("id", keepId);
  const others = (data ?? []) as { id: string; file_path: string | null }[];
  const paths = others.map((row) => row.file_path).filter((
    path,
  ): path is string => typeof path === "string");
  if (paths.length > 0) {
    await admin.storage.from(BUCKET).remove(paths);
  }
  if (others.length > 0) {
    await admin.from("data_exports").update({
      status: "expired",
      file_path: null,
    }).in("id", others.map((row) => row.id));
  }
}

async function runExport(
  admin: SupabaseClient,
  exportId: string,
  userId: string,
) {
  const now = new Date();
  const setStage = async (stage: ExportStage, detail?: string) => {
    await admin.from("data_exports").update({
      stage,
      detail: detail ?? null,
      progress: stageProgress(stage),
    }).eq("id", exportId);
  };
  try {
    const data = await collectExportData(admin, {
      userId,
      now,
      onStage: setStage,
    });
    await setStage("packaging");
    const zip = buildExportZip(data);
    await setStage("uploading");
    const path = exportObjectPath(userId, now);
    const uploaded = await admin.storage.from(BUCKET).upload(path, zip, {
      contentType: "application/zip",
      upsert: false,
    });
    if (uploaded.error) throw uploaded.error;
    await removeOtherExports(admin, userId, exportId);
    await admin.from("data_exports").update({
      status: "ready",
      stage: "ready",
      detail: null,
      progress: 100,
      file_path: path,
      byte_size: zip.length,
      completed_at: new Date().toISOString(),
      expires_at: exportExpiresAt(now).toISOString(),
    }).eq("id", exportId);
  } catch (error) {
    console.error("data export failed", exportId, error);
    await admin.from("data_exports").update({
      status: "failed",
      error: "export_failed",
      completed_at: new Date().toISOString(),
    }).eq("id", exportId);
  }
}

async function describe(admin: SupabaseClient, row: ExportRow) {
  let downloadUrl: string | null = null;
  if (row.status === "ready" && row.file_path) {
    const signed = await admin.storage.from(BUCKET).createSignedUrl(
      row.file_path,
      LINK_SECONDS,
      { download: DOWNLOAD_NAME },
    );
    downloadUrl = signed.data?.signedUrl ?? null;
  }
  return {
    id: row.id,
    status: row.status,
    stage: row.stage,
    detail: row.detail,
    progress: row.progress,
    byte_size: row.byte_size,
    created_at: row.created_at,
    expires_at: row.expires_at,
    error: row.error,
    download_url: downloadUrl,
  };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "GET" && request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "not_configured" }, 500);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (token === "" || token === authorization) {
    return json({ error: "unauthorized" }, 401);
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: Record<string, unknown> = {};
  if (request.method === "POST") {
    try {
      const parsed = await request.json();
      if (parsed && typeof parsed === "object") body = parsed;
    } catch {
      // No body is fine: it starts an export.
    }
  }

  // A scheduler with the service role key only tidies up.
  if (token === serviceRoleKey) {
    if (request.method === "POST" && body["purge"] === true) {
      return json({ purged: await purgeExpired(admin, new Date()) });
    }
    return json({ error: "unauthorized" }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(
    token,
  );
  const user = userData?.user;
  if (userError || !user) {
    return json({ error: "unauthorized" }, 401);
  }

  if (request.method === "GET") {
    const id = new URL(request.url).searchParams.get("id");
    let query = admin.from("data_exports").select("*").eq("user_id", user.id);
    if (id !== null) {
      if (!uuidPattern.test(id)) return json({ error: "invalid_id" }, 400);
      query = query.eq("id", id);
    } else {
      query = query.in("status", ["working", "ready", "failed"]);
    }
    const { data, error } = await query.order("created_at", {
      ascending: false,
    }).limit(1);
    if (error) return json({ error: "lookup_failed" }, 500);
    const row = (data ?? [])[0] as ExportRow | undefined;
    if (!row) return json({ export: null });
    return json({ export: await describe(admin, row) });
  }

  await purgeExpired(admin, new Date()).catch(() => 0);
  const begun = await admin.rpc("begin_data_export", {
    target_user_id: user.id,
  });
  if (begun.error) return json({ error: "start_failed" }, 500);
  const result = (begun.data ?? [])[0] as {
    export_id: string;
    started: boolean;
    status: string;
    retry_after_seconds: number;
  } | undefined;
  if (!result) return json({ error: "start_failed" }, 500);
  if (!result.started) {
    return result.status === "working"
      ? json({ error: "in_progress", id: result.export_id }, 409)
      : json({
        error: "rate_limited",
        id: result.export_id,
        retry_after_seconds: result.retry_after_seconds,
      }, 429);
  }

  const job = runExport(admin, result.export_id, user.id);
  // The runtime keeps working after the answer is sent.
  const runtime = (globalThis as {
    EdgeRuntime?: { waitUntil(promise: Promise<unknown>): void };
  }).EdgeRuntime;
  if (runtime) {
    runtime.waitUntil(job);
  } else {
    await job;
  }
  return json({ id: result.export_id }, 202);
});
