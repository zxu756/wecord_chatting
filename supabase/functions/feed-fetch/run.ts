// One run of feed-fetch: claim the feeds that are due, read each one, post
// what is new, and report how it went (roadmap I6).
//
// The database decides which feeds are due (claim_channel_feeds: at most one
// per web site, none whose poster can no longer post, none in a suspended
// circle) and what is posted (post_feed_items: cards, AutoMod, limits). This
// file only reads the web and hands over plain data.
import { type Deps, fetchFeed } from "./fetch.ts";
import { FeedError, type FeedItem, itemKey, parseFeed } from "./feed.ts";

export const BATCH_SIZE = 10;
export const MAX_ROUNDS = 5;
export const CONCURRENCY = 4;
/** The most items one read posts; the newest of the new ones. */
export const MAX_POSTS_PER_READ = 5;
/** Item keys remembered per feed. */
export const MAX_SEEN = 200;

/** One row of claim_channel_feeds. */
export type Claimed = {
  feed_id: string;
  url: string;
  etag: string | null;
  last_modified: string | null;
  seen_keys: string[] | null;
  initialized: boolean;
};

export type RpcResult = { data: unknown; error: { message: string } | null };
export type Rpc = (
  name: string,
  params: Record<string, unknown>,
) => PromiseLike<RpcResult>;

export type Summary = {
  feeds: number;
  posted: number;
  failed: number;
  unchanged: number;
};

type Finish = {
  ok: boolean;
  status: number | null;
  error: string | null;
  etag: string | null;
  lastModified: string | null;
  title: string | null;
  seen: string[] | null;
  permanent: boolean;
};

function finishParams(feedId: string, finish: Finish): Record<string, unknown> {
  return {
    target_feed_id: feedId,
    fetch_ok: finish.ok,
    http_status: finish.status,
    error_code: finish.error,
    new_etag: finish.etag,
    new_last_modified: finish.lastModified,
    feed_title: finish.title,
    new_seen: finish.seen,
    permanent: finish.permanent,
  };
}

/** Oldest first: by date when the items have one, else the reverse of the
 *  feed's own order (feeds list the newest first). */
export function oldestFirst(items: FeedItem[]): FeedItem[] {
  const indexed = items.map((item, index) => ({ item, index }));
  indexed.sort((a, b) => {
    const left = a.item.published ? Date.parse(a.item.published) : NaN;
    const right = b.item.published ? Date.parse(b.item.published) : NaN;
    if (Number.isFinite(left) && Number.isFinite(right) && left !== right) {
      return left - right;
    }
    return b.index - a.index;
  });
  return indexed.map((entry) => entry.item);
}

/**
 * What a read changes: the items to post (the newest few of the new ones,
 * oldest first) and the keys to remember (this read's, newest first, then
 * the older ones that fit). The first read of a feed posts nothing.
 */
export function planRead(
  items: FeedItem[],
  keys: string[],
  seen: string[],
  initialized: boolean,
): { toPost: FeedItem[]; remember: string[] } {
  const known = new Set(seen);
  const fresh: FeedItem[] = [];
  items.forEach((item, index) => {
    if (!known.has(keys[index])) {
      fresh.push(item);
    }
  });
  const remember = [...new Set([...keys, ...seen])].slice(0, MAX_SEEN);
  if (!initialized) {
    return { toPost: [], remember };
  }
  const toPost = oldestFirst(fresh).slice(-MAX_POSTS_PER_READ);
  return { toPost, remember };
}

async function processFeed(
  claimed: Claimed,
  rpc: Rpc,
  deps: Deps,
  summary: Summary,
): Promise<void> {
  const finish = async (result: Finish) => {
    const { error } = await rpc("finish_channel_feed", {
      ...finishParams(claimed.feed_id, result),
    });
    if (error) {
      console.error("finish_channel_feed failed", error.message);
    }
  };

  const fetched = await fetchFeed(
    claimed.url,
    { etag: claimed.etag, lastModified: claimed.last_modified },
    deps,
  );

  if (fetched.kind === "not_modified") {
    summary.unchanged++;
    await finish({
      ok: true,
      status: 304,
      error: null,
      etag: claimed.etag,
      lastModified: claimed.last_modified,
      title: null,
      seen: null,
      permanent: false,
    });
    return;
  }
  if (fetched.kind === "error") {
    summary.failed++;
    await finish({
      ok: false,
      status: fetched.status,
      error: fetched.code,
      etag: null,
      lastModified: null,
      title: null,
      seen: null,
      permanent: fetched.permanent,
    });
    return;
  }

  let parsed;
  try {
    parsed = parseFeed(fetched.text, fetched.finalUrl, deps.now());
  } catch (error) {
    summary.failed++;
    let code = error instanceof FeedError ? error.code : "bad_xml";
    // An ordinary web page (the person gave the site, not its feed).
    if (
      code === "doctype_refused" && /^\s*<!doctype\s+html/i.test(fetched.text)
    ) {
      code = "not_a_feed";
    }
    await finish({
      ok: false,
      status: fetched.status,
      error: code,
      etag: null,
      lastModified: null,
      title: null,
      seen: null,
      // A feed that never worked and is not one will not become one.
      permanent: !claimed.initialized &&
        (code === "not_a_feed" || code === "doctype_refused"),
    });
    return;
  }

  const keys = await Promise.all(parsed.items.map(itemKey));
  const plan = planRead(
    parsed.items,
    keys,
    claimed.seen_keys ?? [],
    claimed.initialized,
  );

  if (plan.toPost.length > 0) {
    const { data, error } = await rpc("post_feed_items", {
      target_feed_id: claimed.feed_id,
      feed_items: plan.toPost.map((item) => ({
        title: item.title,
        link: item.link,
        summary: item.summary,
        published: item.published,
      })),
    });
    if (error) {
      // Nothing was posted (one transaction): read it again next time.
      summary.failed++;
      console.error("post_feed_items failed", error.message);
      await finish({
        ok: false,
        status: fetched.status,
        error: "post_failed",
        etag: null,
        lastModified: null,
        title: null,
        seen: null,
        permanent: false,
      });
      return;
    }
    const posted = (data as { posted?: number } | null)?.posted;
    summary.posted += typeof posted === "number" ? posted : 0;
  }

  await finish({
    ok: true,
    status: fetched.status,
    error: null,
    etag: fetched.etag,
    lastModified: fetched.lastModified,
    title: parsed.title,
    seen: plan.remember,
    permanent: false,
  });
}

/** Claims and reads feeds until none is due (at most MAX_ROUNDS rounds). */
export async function runFeeds(rpc: Rpc, deps: Deps): Promise<Summary> {
  const summary: Summary = { feeds: 0, posted: 0, failed: 0, unchanged: 0 };
  for (let round = 0; round < MAX_ROUNDS; round++) {
    const { data, error } = await rpc("claim_channel_feeds", {
      max_count: BATCH_SIZE,
    });
    if (error) {
      throw new Error(`claim_channel_feeds failed: ${error.message}`);
    }
    const claimed = Array.isArray(data) ? data as Claimed[] : [];
    if (claimed.length === 0) {
      break;
    }
    summary.feeds += claimed.length;
    for (let index = 0; index < claimed.length; index += CONCURRENCY) {
      await Promise.all(
        claimed.slice(index, index + CONCURRENCY).map((feed) =>
          processFeed(feed, rpc, deps, summary).catch((caught) => {
            summary.failed++;
            console.error("feed failed", feed.feed_id, caught);
          })
        ),
      );
    }
    if (claimed.length < BATCH_SIZE) {
      break;
    }
  }
  return summary;
}
