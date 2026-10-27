// No test here calls an outside address: the database and the web are fakes.
import { assert, assertEquals } from "jsr:@std/assert@1";
import type { Deps } from "./fetch.ts";
import { type FeedItem, itemKey } from "./feed.ts";
import {
  type Claimed,
  MAX_POSTS_PER_READ,
  MAX_SEEN,
  oldestFirst,
  planRead,
  type Rpc,
  runFeeds,
} from "./run.ts";

const NOW = Date.parse("2026-10-28T12:00:00Z");

function rssWith(count: number, start = 1): string {
  const items = Array.from({ length: count }, (_, index) => {
    const n = start + count - 1 - index; // newest first
    return `<item><title>Post ${n}</title><link>https://blog.example.com/p/${n}</link><guid>g${n}</guid><pubDate>${
      new Date(NOW - (100 - n) * 3600_000).toUTCString()
    }</pubDate><description>About ${n}</description></item>`;
  }).join("");
  return `<rss version="2.0"><channel><title>Blog</title>${items}</channel></rss>`;
}

function webDeps(
  answer: (url: string) => Response,
  seen: string[] = [],
): Deps {
  return {
    resolve: () => Promise.resolve(["93.184.216.34"]),
    now: () => NOW,
    fetch: ((url: string | URL | Request) => {
      seen.push(String(url));
      return Promise.resolve(answer(String(url)));
    }) as typeof fetch,
  };
}

type Call = { name: string; params: Record<string, unknown> };

function database(
  rounds: Claimed[][],
  options: { postError?: boolean } = {},
): { rpc: Rpc; calls: Call[] } {
  const calls: Call[] = [];
  const queue = [...rounds];
  const rpc: Rpc = (name, params) => {
    calls.push({ name, params });
    if (name === "claim_channel_feeds") {
      return Promise.resolve({ data: queue.shift() ?? [], error: null });
    }
    if (name === "post_feed_items") {
      return Promise.resolve(
        options.postError ? { data: null, error: { message: "boom" } } : {
          data: {
            posted: (params.feed_items as unknown[]).length,
            skipped: 0,
          },
          error: null,
        },
      );
    }
    return Promise.resolve({ data: null, error: null });
  };
  return { rpc, calls };
}

function claimed(overrides: Partial<Claimed> = {}): Claimed {
  return {
    feed_id: "feed-1",
    url: "https://blog.example.com/feed.xml",
    etag: null,
    last_modified: null,
    seen_keys: [],
    initialized: false,
    ...overrides,
  };
}

function finishOf(calls: Call[]): Record<string, unknown> {
  const finish = calls.find((call) => call.name === "finish_channel_feed");
  assert(finish, "finish_channel_feed was called");
  return finish.params;
}

Deno.test("the first read remembers the items and posts nothing", async () => {
  const { rpc, calls } = database([[claimed()]]);
  const summary = await runFeeds(
    rpc,
    webDeps(() =>
      new Response(rssWith(3), {
        status: 200,
        headers: {
          ETag: '"e1"',
          "Last-Modified": "Wed, 28 Oct 2026 08:00:00 GMT",
        },
      })
    ),
  );
  assertEquals(summary, { feeds: 1, posted: 0, failed: 0, unchanged: 0 });
  assertEquals(calls.some((call) => call.name === "post_feed_items"), false);
  const finish = finishOf(calls);
  assertEquals(finish.fetch_ok, true);
  assertEquals(finish.feed_title, "Blog");
  assertEquals(finish.new_etag, '"e1"');
  assertEquals((finish.new_seen as string[]).length, 3);
});

Deno.test("later reads post the new items, oldest first, at most five", async () => {
  const first = rssWith(3);
  const seenKeys: string[] = [];
  // What the first read remembered.
  {
    const { rpc, calls } = database([[claimed()]]);
    await runFeeds(rpc, webDeps(() => new Response(first, { status: 200 })));
    seenKeys.push(...(finishOf(calls).new_seen as string[]));
  }
  const { rpc, calls } = database([[
    claimed({ initialized: true, seen_keys: seenKeys }),
  ]]);
  const summary = await runFeeds(
    rpc,
    webDeps(() => new Response(rssWith(10), { status: 200 })),
  );
  // Posts 4..10 are new; only the newest five go, oldest first.
  assertEquals(summary.posted, MAX_POSTS_PER_READ);
  const post = calls.find((call) => call.name === "post_feed_items")!;
  const posted = post.params.feed_items as { title: string; link: string }[];
  assertEquals(posted.map((item) => item.title), [
    "Post 6",
    "Post 7",
    "Post 8",
    "Post 9",
    "Post 10",
  ]);
  assertEquals(posted[0].link, "https://blog.example.com/p/6");
  assertEquals(post.params.target_feed_id, "feed-1");
  // All ten are remembered, so the older new ones are not posted later.
  assertEquals((finishOf(calls).new_seen as string[]).length, 10);
});

Deno.test("nothing new posts nothing", async () => {
  const keys = await Promise.all(
    ["g3", "g2", "g1"].map((id) =>
      itemKey({ id, title: "", link: null, summary: "", published: null })
    ),
  );
  const { rpc, calls } = database([[
    claimed({ initialized: true, seen_keys: keys }),
  ]]);
  const summary = await runFeeds(
    rpc,
    webDeps(() => new Response(rssWith(3), { status: 200 })),
  );
  assertEquals(summary.posted, 0);
  assertEquals(calls.some((call) => call.name === "post_feed_items"), false);
  assertEquals(finishOf(calls).fetch_ok, true);
});

Deno.test("not modified keeps the cache headers and the title", async () => {
  const { rpc, calls } = database([[
    claimed({ initialized: true, etag: '"e1"', last_modified: "Mon" }),
  ]]);
  const seenRequests: string[] = [];
  const web = webDeps(() => new Response(null, { status: 304 }), seenRequests);
  const summary = await runFeeds(rpc, web);
  assertEquals(summary.unchanged, 1);
  const finish = finishOf(calls);
  assertEquals(finish.fetch_ok, true);
  assertEquals(finish.new_etag, '"e1"');
  assertEquals(finish.feed_title, null);
  assertEquals(finish.new_seen, null);
});

Deno.test("a failed read is reported with a short code", async () => {
  const { rpc, calls } = database([[claimed({ initialized: true })]]);
  const summary = await runFeeds(
    rpc,
    webDeps(() => new Response("Server error <script>", { status: 500 })),
  );
  assertEquals(summary.failed, 1);
  const finish = finishOf(calls);
  assertEquals(finish.fetch_ok, false);
  assertEquals(finish.error_code, "http_500");
  assertEquals(finish.http_status, 500);
  assertEquals(finish.permanent, false);
});

Deno.test("a web page is not a feed: final for a new feed, not for an old one", async () => {
  const page = "<!DOCTYPE html><html><body>Welcome</body></html>";
  for (const [initialized, permanent] of [[false, true], [true, false]]) {
    const { rpc, calls } = database([[claimed({ initialized })]]);
    await runFeeds(rpc, webDeps(() => new Response(page, { status: 200 })));
    const finish = finishOf(calls);
    assertEquals(finish.error_code, "not_a_feed");
    assertEquals(finish.permanent, permanent);
  }
  const { rpc, calls } = database([[claimed()]]);
  await runFeeds(
    rpc,
    webDeps(() => new Response("<html><body>x</body></html>", { status: 200 })),
  );
  assertEquals(finishOf(calls).error_code, "not_a_feed");
});

Deno.test("an entity bomb is refused", async () => {
  const bomb =
    `<?xml version="1.0"?><!DOCTYPE x [<!ENTITY a "aaaa">]><rss><channel><title>&a;</title></channel></rss>`;
  const { rpc, calls } = database([[claimed({ initialized: true })]]);
  await runFeeds(rpc, webDeps(() => new Response(bomb, { status: 200 })));
  assertEquals(finishOf(calls).error_code, "doctype_refused");
});

Deno.test("when posting fails nothing is remembered", async () => {
  const { rpc, calls } = database([[
    claimed({ initialized: true, seen_keys: ["x"] }),
  ]], { postError: true });
  const summary = await runFeeds(
    rpc,
    webDeps(() => new Response(rssWith(2), { status: 200 })),
  );
  assertEquals(summary.failed, 1);
  const finish = finishOf(calls);
  assertEquals(finish.fetch_ok, false);
  assertEquals(finish.error_code, "post_failed");
  assertEquals(finish.new_seen, null);
});

Deno.test("rounds continue while batches are full, and stop when none is due", async () => {
  const batch = (n: number, offset: number) =>
    Array.from(
      { length: n },
      (_, i) =>
        claimed({
          feed_id: `f${offset + i}`,
          initialized: true,
          url: `https://site${offset + i}.example.com/rss`,
        }),
    );
  const { rpc, calls } = database([batch(10, 0), batch(3, 10)]);
  const summary = await runFeeds(
    rpc,
    webDeps(() => new Response(null, { status: 304 })),
  );
  assertEquals(summary.feeds, 13);
  assertEquals(calls.filter((c) => c.name === "claim_channel_feeds").length, 2);
  assertEquals(
    calls.filter((c) => c.name === "finish_channel_feed").length,
    13,
  );
});

Deno.test("an address the database should not have handed out is still refused", async () => {
  const { rpc, calls } = database([[
    claimed({
      url: "https://169.254.169.254/latest/meta-data",
      initialized: true,
    }),
  ]]);
  const requests: string[] = [];
  await runFeeds(rpc, webDeps(() => new Response("x"), requests));
  assertEquals(requests, []);
  assertEquals(finishOf(calls).permanent, true);
});

Deno.test("planning: oldest first by date, else by position; seen is capped", () => {
  const item = (id: string, published: string | null): FeedItem => ({
    id,
    title: id,
    link: null,
    summary: "",
    published,
  });
  const dated = [
    item("c", "2026-10-03T00:00:00Z"),
    item("a", "2026-10-01T00:00:00Z"),
    item("b", "2026-10-02T00:00:00Z"),
  ];
  assertEquals(oldestFirst(dated).map((i) => i.id), ["a", "b", "c"]);
  // No dates: the feed lists the newest first, so reverse it.
  assertEquals(
    oldestFirst([item("3", null), item("2", null), item("1", null)]).map((i) =>
      i.id
    ),
    ["1", "2", "3"],
  );

  const many = Array.from({ length: 50 }, (_, i) => item(`n${i}`, null));
  const keys = many.map((_, i) => `k${i}`);
  const old = Array.from({ length: 300 }, (_, i) => `old${i}`);
  const plan = planRead(many, keys, old, true);
  assertEquals(plan.toPost.length, MAX_POSTS_PER_READ);
  assertEquals(plan.remember.length, MAX_SEEN);
  assertEquals(plan.remember.slice(0, 3), ["k0", "k1", "k2"]);
});
