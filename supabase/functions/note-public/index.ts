// A published note as JSON: GET /note-public/<token>. verify_jwt is off
// (supabase/config.toml) because the readers have no WeCord account; the
// token is checked inside the database function public_note_by_token, which
// only the service role may call. See page.ts.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  handleNotePublicRequest,
  type LookupResult,
  SIGNED_SECONDS,
  WindowLimiter,
} from "./page.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

const admin = supabaseUrl && serviceRoleKey
  ? createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  : null;

// 20 wrong tokens a minute per address, per running instance.
const badTokens = new WindowLimiter(20, 60_000);

Deno.serve((request) =>
  handleNotePublicRequest(request, {
    now: () => new Date(),
    badTokens,
    lookup: async (token) => {
      if (!admin) throw new Error("not configured");
      const { data, error } = await admin.rpc("public_note_by_token", {
        p_token: token,
      });
      if (error) throw error;
      return data as LookupResult;
    },
    sign: async (paths) => {
      if (!admin) throw new Error("not configured");
      const { data, error } = await admin.storage.from("note-files")
        .createSignedUrls(paths, SIGNED_SECONDS);
      if (error) throw error;
      const urls: Record<string, string> = {};
      for (const entry of data ?? []) {
        if (entry.path && entry.signedUrl && !entry.error) {
          urls[entry.path] = entry.signedUrl;
        }
      }
      return urls;
    },
  })
);
