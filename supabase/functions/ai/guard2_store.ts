// The database and storage side of AI guard 2.0 and the link check: the real
// stores that index.ts passes in. The decisions are in guard2.ts,
// link_check.ts and SQL (migrations 202610260200 to 202610260220); this file
// only moves rows. Its pure parts are tested without a database.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type {
  Guard2Store,
  GuardItemClaim,
  GuardItemResult,
  GuardMessageInfo,
} from "./guard2.ts";
import type { LinkCheckStore, LinkPageInfo } from "./link_check.ts";
import { type GuardImage, MAX_IMAGE_BYTES } from "./vision.ts";

type Row = Record<string, unknown>;
// deno-lint-ignore no-explicit-any
type Client = SupabaseClient<any, any, any>;

function asRow(value: unknown): Row | null {
  const row = Array.isArray(value) ? value[0] : value;
  return row !== null && typeof row === "object" && !Array.isArray(row)
    ? row as Row
    : null;
}

function text(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

/// The message in ai_guard_message_info's answer; null when it is nothing.
export function messageInfoFromRow(value: unknown): GuardMessageInfo | null {
  const row = asRow(value);
  if (row === null || typeof row.type !== "string") {
    return null;
  }
  return {
    type: row.type,
    body: text(row.body),
    attachment: row.attachment ?? null,
  };
}

/// The claim in ai_guard_item_claim's answer; null when it is nothing.
export function itemClaimFromRow(value: unknown): GuardItemClaim | null {
  const row = asRow(value);
  if (row === null || typeof row.circle_id !== "string") {
    return null;
  }
  return {
    circleId: row.circle_id,
    itemType: text(row.item_type),
    title: text(row.title),
    detail: text(row.detail),
    aiEnabled: row.ai_enabled !== false,
  };
}

/// Whether storage can scale pictures down (a paid plan feature). Learned
/// the first time it says no, and tried again after an hour.
let transformUnavailableAt = 0;
const TRANSFORM_RETRY_MS = 60 * 60 * 1000;

async function downloadImage(
  client: Client,
  image: GuardImage,
): Promise<Uint8Array | null> {
  const bucket = client.storage.from(image.bucket);
  if (Date.now() - transformUnavailableAt >= TRANSFORM_RETRY_MS) {
    try {
      const { data, error } = await bucket.download(image.path, {
        transform: { width: 768, height: 768, resize: "contain", quality: 70 },
      });
      if (!error && data) {
        return new Uint8Array(await data.arrayBuffer());
      }
      transformUnavailableAt = Date.now();
    } catch {
      transformUnavailableAt = Date.now();
    }
  }
  // As stored, when it is small enough to send.
  if (image.size > MAX_IMAGE_BYTES) {
    return null;
  }
  const { data, error } = await bucket.download(image.path);
  if (error || !data) {
    return null;
  }
  return new Uint8Array(await data.arrayBuffer());
}

function circleUsage(value: unknown): { allowed: boolean; used: number } {
  const row = asRow(value);
  return {
    allowed: row?.allowed === true,
    used: typeof row?.used === "number" ? row.used : 0,
  };
}

export function createGuard2Store(admin: Client): Guard2Store {
  return {
    messageInfo: async (messageId) => {
      const { data, error } = await admin.rpc("ai_guard_message_info", {
        p_message_id: messageId,
      });
      if (error) {
        throw new Error(`ai_guard_message_info: ${error.message}`);
      }
      return messageInfoFromRow(data);
    },
    downloadImage: (image) => downloadImage(admin, image),
    visionConsume: async (circleId, limit) => {
      const { data, error } = await admin.rpc(
        "ai_consume_circle_vision_request",
        { p_circle_id: circleId, p_limit: limit },
      );
      if (error) {
        throw new Error(`ai_consume_circle_vision_request: ${error.message}`);
      }
      return circleUsage(data);
    },
    visionRefund: async (circleId) => {
      await admin.rpc("ai_refund_circle_vision_request", {
        p_circle_id: circleId,
      });
    },
    setRuntimeFlag: async (key, enabled) => {
      const { error } = await admin.rpc("ai_set_runtime_flag", {
        p_key: key,
        p_enabled: enabled,
      });
      if (error) {
        throw new Error(`ai_set_runtime_flag: ${error.message}`);
      }
    },
    itemClaim: async (reviewId) => {
      const { data, error } = await admin.rpc("ai_guard_item_claim", {
        p_review_id: reviewId,
      });
      if (error) {
        throw new Error(`ai_guard_item_claim: ${error.message}`);
      }
      return itemClaimFromRow(data);
    },
    itemFinish: async (reviewId, result: GuardItemResult) => {
      const { data, error } = await admin.rpc("finish_guard_item_review", {
        p_review_id: reviewId,
        p_verdict: result.verdict?.category ?? "not_checked",
        p_reason: result.verdict?.reason ?? null,
        p_reason_zh: result.verdict?.reasonZh ?? null,
        p_unchecked_reason: result.unchecked ?? null,
      });
      if (error) {
        throw new Error(`finish_guard_item_review: ${error.message}`);
      }
      return typeof data === "string" ? data : null;
    },
  };
}

/// The cached preview in a link_previews row; null when it is nothing.
export function pageInfoFromRow(value: unknown): LinkPageInfo | null {
  const row = asRow(value);
  if (row === null) {
    return null;
  }
  const maybe = (field: unknown) => {
    const value = typeof field === "string" ? field.trim() : "";
    return value === "" ? null : value;
  };
  return {
    title: maybe(row.title),
    description: maybe(row.description),
    siteName: maybe(row.site_name),
    finalUrl: maybe(row.final_url),
  };
}

export function createLinkCheckStore(admin: Client): LinkCheckStore {
  return {
    preview: async (url) => {
      const { data } = await admin
        .from("link_previews")
        .select("title,description,site_name,final_url")
        .eq("url", url)
        .maybeSingle();
      return pageInfoFromRow(data);
    },
    aiEnabled: async (userId) => {
      const { data } = await admin
        .from("user_ai_settings")
        .select("ai_enabled")
        .eq("user_id", userId)
        .maybeSingle();
      return (data as { ai_enabled?: boolean | null } | null)?.ai_enabled !==
        false;
    },
  };
}
