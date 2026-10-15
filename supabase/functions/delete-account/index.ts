// Deletes the caller's account. prepare_account_deletion (run as the
// caller) leaves their circles and groups and turns their profile into
// "Deleted User", and returns the Storage objects of the circles it
// deleted; then, with the service role, those objects, their avatar files
// and their login are removed. Refuses with 409 owns_circles while they own a
// circle that has other members.
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const avatarBucket = "profile-avatars";

// Storage removes at most 1000 objects per request.
const removeBatchSize = 1000;

interface DeletedObject {
  bucket_id?: unknown;
  object_path?: unknown;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
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

  // As the caller, so it can only ever touch their own account.
  const { data: deletedObjects, error: prepareError } = await userClient.rpc(
    "prepare_account_deletion",
  );
  if (prepareError) {
    if (prepareError.code === "55000") {
      return json({ error: "owns_circles" }, 409);
    }
    return json({ error: "prepare_failed" }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Best effort: nothing points at these files any more.
  const pathsByBucket = new Map<string, string[]>();
  for (const row of (deletedObjects ?? []) as DeletedObject[]) {
    if (typeof row?.bucket_id !== "string") continue;
    if (typeof row?.object_path !== "string") continue;
    const paths = pathsByBucket.get(row.bucket_id) ?? [];
    paths.push(row.object_path);
    pathsByBucket.set(row.bucket_id, paths);
  }
  for (const [bucket, paths] of pathsByBucket) {
    for (let start = 0; start < paths.length; start += removeBatchSize) {
      await admin.storage.from(bucket).remove(
        paths.slice(start, start + removeBatchSize),
      );
    }
  }

  // Best effort: the profile no longer points at these files.
  const { data: files } = await admin.storage.from(avatarBucket).list(
    user.id,
    { limit: 1000 },
  );
  const paths = (files ?? []).map((file) => `${user.id}/${file.name}`);
  if (paths.length > 0) {
    await admin.storage.from(avatarBucket).remove(paths);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    return json({ error: "delete_failed" }, 500);
  }
  return json({ deleted: true });
});
