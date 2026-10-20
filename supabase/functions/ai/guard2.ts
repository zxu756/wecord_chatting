// AI guard 2.0 (roadmap F7): what the guard of 202610170090 reads besides the
// text of a message. handler.ts calls into this file; the database starts
// every check (migrations 202610260200 and 202610260210), never a client.
//
//  * Polls are messages: the question and the options go through the usual
//    text check ([pollGuardText]).
//  * Pictures go to a vision model when AI_VISION_ENABLED is on ([guardImage]);
//    with it off, or when the model refuses pictures, the picture is skipped
//    and the message released as "not checked". The picture goes to the
//    provider as base64 in that one request and is not stored anywhere.
//  * Events, notes and tasks created by the people the guard checks are
//    classified like a message ([runGuardItem]); what the AI flags goes to the
//    circle's Review queue.

import { type AiConfig, readAiConfig } from "./config.ts";
import {
  extractLinkDomains,
  guardText,
  type GuardVerdict,
  parseGuardVerdict,
} from "./guard.ts";
import type { AiDeps, GuardResult } from "./handler.ts";
import { guardPrompt } from "./prompts.ts";
import { complete, ProviderError } from "./provider.ts";
import {
  type GuardImage,
  guardImagePrompt,
  imageDataUrl,
  isVisionRefusal,
  MAX_IMAGE_BYTES,
  readGuardImage,
  readVisionConfig,
  VISION_TIMEOUT_MS,
} from "./vision.ts";

/// What the function reads about a message it claimed (ai_guard_message_info).
export interface GuardMessageInfo {
  type: string;
  body: string;
  attachment: unknown;
}

/// An event, note or task waiting for its check (ai_guard_item_claim).
export interface GuardItemClaim {
  circleId: string;
  itemType: string;
  title: string;
  detail: string;
  aiEnabled: boolean;
}

export type GuardItemResult =
  | { verdict: GuardVerdict; unchecked?: undefined }
  | {
    verdict?: undefined;
    unchecked: "not_configured" | "ai_off" | "limit" | "error" | "timeout";
  };

/// What AI guard 2.0 needs from the database and storage (index.ts wires it;
/// tests pass fakes). Without it the guard checks text only, as before.
export interface Guard2Store {
  messageInfo(messageId: string): Promise<GuardMessageInfo | null>;
  /// The picture's bytes, scaled down where storage can do that; null when
  /// it cannot be read or is too big to send.
  downloadImage(image: GuardImage): Promise<Uint8Array | null>;
  visionConsume(
    circleId: string,
    limit: number,
  ): Promise<{ allowed: boolean; used: number }>;
  visionRefund(circleId: string): Promise<void>;
  /// Tells the database what the function is set up for, so that pictures
  /// are only held when they can be read.
  setRuntimeFlag(key: string, enabled: boolean): Promise<void>;
  itemClaim(reviewId: string): Promise<GuardItemClaim | null>;
  itemFinish(reviewId: string, result: GuardItemResult): Promise<string | null>;
}

/// How long the model has for an event, note or task.
export const ITEM_TIMEOUT_MS = 15_000;

// ------------------------------------------------------------------ polls

/// The text of a poll for the model: the question and the options.
export function pollGuardText(info: GuardMessageInfo): string {
  const lines = [info.body.trim()];
  const attachment = info.attachment;
  if (
    attachment !== null && typeof attachment === "object" &&
    !Array.isArray(attachment)
  ) {
    const options = (attachment as Record<string, unknown>).options;
    if (Array.isArray(options)) {
      for (const option of options.slice(0, 10)) {
        const text = option !== null && typeof option === "object"
          ? (option as Record<string, unknown>).text
          : option;
        if (typeof text === "string" && text.trim() !== "") {
          lines.push(`- ${text.trim()}`);
        }
      }
    }
  }
  return `Poll question and options:\n${lines.join("\n")}`;
}

// --------------------------------------------------------------- pictures

/// When a model last refused pictures. For a while after, this copy of the
/// function says vision is off, so the database stops holding pictures and
/// the provider is not asked again for each one.
let visionRefusedAt = 0;
const VISION_REFUSAL_MEMORY_MS = 6 * 60 * 60 * 1000;

/// Forgets a refusal (tests).
export function resetVisionRefusal(): void {
  visionRefusedAt = 0;
}

/// Whether pictures can be checked right now: switched on, and the model has
/// not recently refused them.
export function visionReady(
  config: AiConfig,
  env: (name: string) => string | undefined,
  now = Date.now(),
): boolean {
  return readVisionConfig(config, env).enabled &&
    now - visionRefusedAt >= VISION_REFUSAL_MEMORY_MS;
}

/// What was last told to the database, and when, so a status call does not
/// cost a database call every time.
let syncedVision: { ready: boolean; at: number } | null = null;
const VISION_SYNC_EVERY_MS = 10 * 60 * 1000;

/// Tells the database whether pictures can be checked (ai_runtime_flags),
/// when that changed or has not been said for a while. Never throws.
export async function syncVisionFlag(
  store: Guard2Store,
  ready: boolean,
  now = Date.now(),
): Promise<void> {
  if (
    syncedVision !== null && syncedVision.ready === ready &&
    now - syncedVision.at < VISION_SYNC_EVERY_MS
  ) {
    return;
  }
  try {
    await store.setRuntimeFlag("vision", ready);
    syncedVision = { ready, at: now };
  } catch (error) {
    console.error("ai could not tell the database about vision", String(error));
  }
}

/// Forgets what was told to the database (tests).
export function resetVisionSync(): void {
  syncedVision = null;
}

/// Checks the picture of a message. Never throws for a provider problem: the
/// result says why it was not checked instead.
export async function guardImage(
  circleId: string,
  info: GuardMessageInfo,
  config: AiConfig,
  deps: AiDeps,
): Promise<GuardResult> {
  const store = deps.guard2;
  if (store === undefined) {
    return { unchecked: "vision_off" };
  }
  const vision = readVisionConfig(config, deps.env);
  const ready = visionReady(config, deps.env);
  await syncVisionFlag(store, ready);
  if (!ready) {
    return { unchecked: "vision_off" };
  }
  const image = readGuardImage(info.attachment);
  if (image === null) {
    return { unchecked: "image_unreadable" };
  }
  const { allowed } = await store.visionConsume(circleId, vision.dailyLimit);
  if (!allowed) {
    return { unchecked: "limit" };
  }
  const refund = () => store.visionRefund(circleId).catch(() => {});

  let bytes: Uint8Array | null = null;
  try {
    bytes = await store.downloadImage(image);
  } catch (error) {
    console.error("ai guard could not read a picture", String(error));
  }
  if (bytes === null || bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES) {
    await refund();
    return { unchecked: "image_unreadable" };
  }

  try {
    const answer = await complete({ ...config, model: vision.model }, {
      messages: guardImagePrompt(imageDataUrl(bytes, image.mimeType)),
      maxTokens: 320,
      temperature: 0,
      timeoutMs: VISION_TIMEOUT_MS,
      conversationKey: circleId,
      feature: "guard_image",
    }, deps.fetch);
    const verdict = parseGuardVerdict(answer);
    if (verdict === null) {
      await refund();
      return { unchecked: "error" };
    }
    return { verdict };
  } catch (error) {
    await refund();
    if (!(error instanceof ProviderError)) {
      throw error;
    }
    if (error.kind === "failed" && isVisionRefusal(error.status)) {
      visionRefusedAt = Date.now();
      await syncVisionFlag(store, false);
      return { unchecked: "vision_unsupported" };
    }
    return {
      unchecked: error.kind === "timeout"
        ? "timeout"
        : error.kind === "busy"
        ? "limit"
        : "error",
    };
  }
}

// ------------------------------------------------------------------ items

const ITEM_LABELS: Record<string, string> = {
  circle_event: "Event",
  note: "Note title",
  task_list: "Task list title",
  task_item: "Task",
};

/// The text of an event, note or task for the model.
export function itemGuardText(claim: GuardItemClaim): string {
  const label = ITEM_LABELS[claim.itemType] ?? "Item";
  const detail = claim.detail.trim();
  return detail === ""
    ? `${label}: ${claim.title.trim()}`
    : `${label}: ${claim.title.trim()}\nDetails: ${detail}`;
}

/// The check of one event, note, task list or task, asked by the database.
/// Fails open like the guard of messages: whatever goes wrong, the item
/// stays as it is and is recorded as "not checked".
export async function runGuardItem(
  reviewId: string,
  deps: AiDeps,
): Promise<{ status: number; body: unknown }> {
  const store = deps.guard2;
  if (store === undefined) {
    return { status: 503, body: { error: "not_configured" } };
  }
  const claim = await store.itemClaim(reviewId);
  if (claim === null) {
    return { status: 200, body: { ok: true, skipped: true } };
  }

  const finish = async (result: GuardItemResult) => {
    const state = await store.itemFinish(reviewId, result);
    return {
      status: 200,
      body: result.verdict !== undefined
        ? { ok: true, state, category: result.verdict.category }
        : { ok: true, state, unchecked: result.unchecked },
    };
  };

  try {
    if (!claim.aiEnabled) {
      return await finish({ unchecked: "ai_off" });
    }
    const config = readAiConfig(deps.env);
    if (config === null) {
      return await finish({ unchecked: "not_configured" });
    }
    const { allowed } = await deps.guardConsume(
      claim.circleId,
      config.guardDailyLimit,
    );
    if (!allowed) {
      return await finish({ unchecked: "limit" });
    }
    let verdict: GuardVerdict | null;
    try {
      const text = guardText(itemGuardText(claim));
      const answer = await complete(config, {
        messages: guardPrompt({ text, domains: extractLinkDomains(text) }),
        maxTokens: 320,
        temperature: 0,
        timeoutMs: ITEM_TIMEOUT_MS,
        conversationKey: claim.circleId,
        feature: "guard",
      }, deps.fetch);
      verdict = parseGuardVerdict(answer);
    } catch (error) {
      await deps.guardRefund(claim.circleId).catch(() => {});
      if (error instanceof ProviderError) {
        return await finish({
          unchecked: error.kind === "timeout"
            ? "timeout"
            : error.kind === "busy"
            ? "limit"
            : "error",
        });
      }
      throw error;
    }
    if (verdict === null) {
      await deps.guardRefund(claim.circleId).catch(() => {});
      return await finish({ unchecked: "error" });
    }
    return await finish({ verdict });
  } catch (error) {
    console.error("ai guard item failed", String(error));
    try {
      return await finish({ unchecked: "error" });
    } catch (inner) {
      console.error("ai guard item could not finish", String(inner));
      return { status: 500, body: { error: "internal" } };
    }
  }
}
