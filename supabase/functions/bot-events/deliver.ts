// Sending queued events to the addresses bots subscribed with, and reporting
// what happened. The signing, the address check and the DNS check are the ones
// the interaction callbacks use (supabase/functions/_shared).
import { callbackHeaders } from "../_shared/sign.ts";
import { type Resolver, resolveSafeUrl } from "../_shared/ssrf.ts";

export const SEND_TIMEOUT_MS = 5000;
export const MAX_BODY_BYTES = 16 * 1024;
const BATCH_SIZE = 20;
const MAX_ROUNDS = 5;

/// One row of claim_bot_events.
export type Claimed = {
  delivery_id: string;
  bot_id: string;
  circle_id: string;
  event: string;
  attempt: number;
  occurred_at: string;
  url: string;
  secret: string;
  data: Record<string, unknown>;
};

export type Outcome = {
  delivered: boolean;
  status: number | null;
  error: string | null;
};

export type Deps = {
  resolve: Resolver;
  fetch: typeof fetch;
  /** Milliseconds since 1970. */
  now: () => number;
};

/// What is POSTed: the version, what happened, the bot and circle, when, the
/// attempt (1 to 6) and the details of the event.
export function eventBody(item: Claimed): string {
  return JSON.stringify({
    version: 1,
    type: "event",
    event: item.event,
    event_id: item.delivery_id,
    bot_id: item.bot_id,
    circle_id: item.circle_id,
    occurred_at: item.occurred_at,
    attempt: item.attempt,
    data: item.data,
  });
}

/// The headers of an event: the same signature as a callback, the delivery id
/// in X-WeCord-Delivery, and the kind of event in X-WeCord-Event.
export async function eventHeaders(
  item: Claimed,
  timestamp: number,
  body: string,
): Promise<Record<string, string>> {
  return {
    ...(await callbackHeaders(item.secret, timestamp, body, item.delivery_id)),
    "User-Agent": "WeCord-Bot-Events/1",
    "X-WeCord-Event": item.event,
  };
}

/// Sends one event. Never throws; the outcome says what to report. The error
/// is a short code, never anything the bot's server said.
export async function deliverOne(item: Claimed, deps: Deps): Promise<Outcome> {
  const safe = await resolveSafeUrl(item.url, deps.resolve);
  if (!safe.ok) {
    return { delivered: false, status: null, error: safe.reason };
  }
  const body = eventBody(item);
  if (new TextEncoder().encode(body).byteLength > MAX_BODY_BYTES) {
    return { delivered: false, status: null, error: "payload_too_big" };
  }
  const timestamp = Math.floor(deps.now() / 1000);
  try {
    const response = await deps.fetch(safe.url, {
      method: "POST",
      headers: await eventHeaders(item, timestamp, body),
      body,
      // A redirect could lead somewhere the check did not see.
      redirect: "manual",
      credentials: "omit",
      signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
    });
    // The answer is not read: bots act through the API.
    await response.body?.cancel().catch(() => {});
    if (response.status >= 200 && response.status < 300) {
      return { delivered: true, status: response.status, error: null };
    }
    const redirected = response.status >= 300 && response.status < 400;
    return {
      delivered: false,
      status: response.status,
      error: redirected ? "redirect_not_followed" : `http_${response.status}`,
    };
  } catch (error) {
    const timedOut = error instanceof DOMException &&
      (error.name === "TimeoutError" || error.name === "AbortError");
    return {
      delivered: false,
      status: null,
      error: timedOut ? "timeout" : "network_error",
    };
  }
}

type Rpc = (
  name: string,
  params: Record<string, unknown>,
) => Promise<{ data: unknown; error: { message: string } | null }>;

export type Summary = { claimed: number; delivered: number; failed: number };

/// Claims due events, sends them (up to 20 at once) and reports, until nothing
/// is due or [MAX_ROUNDS] rounds are done.
export async function runEvents(rpc: Rpc, deps: Deps): Promise<Summary> {
  const summary: Summary = { claimed: 0, delivered: 0, failed: 0 };
  for (let round = 0; round < MAX_ROUNDS; round++) {
    const claim = await rpc("claim_bot_events", { max_count: BATCH_SIZE });
    if (claim.error) {
      throw new Error(`claim failed: ${claim.error.message}`);
    }
    const items = Array.isArray(claim.data) ? claim.data as Claimed[] : [];
    if (items.length === 0) {
      break;
    }
    summary.claimed += items.length;
    await Promise.all(items.map(async (item) => {
      const outcome = await deliverOne(item, deps);
      if (outcome.delivered) {
        summary.delivered++;
      } else {
        summary.failed++;
      }
      const reported = await rpc("finish_bot_event", {
        target_delivery_id: item.delivery_id,
        delivered: outcome.delivered,
        http_status: outcome.status,
        error_text: outcome.error,
      });
      if (reported.error) {
        console.error("finish_bot_event failed", reported.error.message);
      }
    }));
    if (items.length < BATCH_SIZE) {
      break;
    }
  }
  return summary;
}
