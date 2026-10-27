// No test here calls an outside address: the resolver and fetch are fakes.
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  decodeBody,
  type Deps,
  fetchFeed,
  MAX_BODY_BYTES,
  MAX_REDIRECTS,
} from "./fetch.ts";
import type { Resolver } from "../_shared/ssrf.ts";

const none = { etag: null, lastModified: null };

type Sent = { url: string; init: RequestInit };

function deps(
  answers: (url: string, sent: Sent[]) => Response | Promise<Response>,
  resolve: Resolver = () => Promise.resolve(["93.184.216.34"]),
): { deps: Deps; sent: Sent[] } {
  const sent: Sent[] = [];
  return {
    sent,
    deps: {
      resolve,
      now: () => Date.parse("2026-10-28T12:00:00Z"),
      fetch: ((url: string | URL | Request, init?: RequestInit) => {
        sent.push({ url: String(url), init: init ?? {} });
        return Promise.resolve(answers(String(url), sent));
      }) as typeof fetch,
    },
  };
}

Deno.test("a good read sends safe headers and returns the text and cache headers", async () => {
  const { deps: d, sent } = deps(() =>
    new Response("<rss/>", {
      status: 200,
      headers: {
        "Content-Type": "application/rss+xml",
        "ETag": '"v1"',
        "Last-Modified": "Wed, 28 Oct 2026 08:00:00 GMT",
      },
    })
  );
  const result = await fetchFeed(
    "https://blog.example.com/feed.xml",
    { etag: '"v0"', lastModified: "Tue, 27 Oct 2026 08:00:00 GMT" },
    d,
  );
  assertEquals(result, {
    kind: "ok",
    text: "<rss/>",
    finalUrl: "https://blog.example.com/feed.xml",
    etag: '"v1"',
    lastModified: "Wed, 28 Oct 2026 08:00:00 GMT",
    status: 200,
  });
  const init = sent[0].init;
  assertEquals(init.method, "GET");
  assertEquals(init.redirect, "manual");
  assertEquals(init.credentials, "omit");
  assert(init.signal instanceof AbortSignal);
  const headers = init.headers as Record<string, string>;
  assert(headers["User-Agent"].startsWith("WeCord-Feeds/1"));
  assertEquals(headers["If-None-Match"], '"v0"');
  assertEquals(headers["If-Modified-Since"], "Tue, 27 Oct 2026 08:00:00 GMT");
  assertEquals(headers["Cookie"], undefined);
  assertEquals(headers["Authorization"], undefined);
});

Deno.test("not modified costs nothing", async () => {
  const { deps: d } = deps(() => new Response(null, { status: 304 }));
  assertEquals(
    await fetchFeed("https://blog.example.com/feed.xml", none, d),
    { kind: "not_modified", status: 304 },
  );
});

Deno.test("addresses that are not public are refused before any request", async () => {
  const cases: [string, Resolver, string, boolean][] = [
    [
      "http://blog.example.com/feed",
      () => Promise.resolve(["93.184.216.34"]),
      "not_https",
      true,
    ],
    [
      "https://10.0.0.5/feed",
      () => Promise.resolve(["10.0.0.5"]),
      "ip_address",
      true,
    ],
    [
      "https://localhost/feed",
      () => Promise.resolve(["127.0.0.1"]),
      "inner_name",
      true,
    ],
    [
      "https://printer.local/feed",
      () => Promise.resolve(["10.1.1.1"]),
      "inner_name",
      true,
    ],
    [
      "https://u:p@blog.example.com/feed",
      () => Promise.resolve(["93.184.216.34"]),
      "credentials_in_url",
      true,
    ],
    [
      "https://blog.example.com:8443/feed",
      () => Promise.resolve(["93.184.216.34"]),
      "port_not_allowed",
      true,
    ],
    [
      "https://sneaky.example.com/feed",
      () => Promise.resolve(["169.254.169.254"]),
      "inner_address",
      true,
    ],
    [
      "https://sneaky6.example.com/feed",
      (_h, type) =>
        Promise.resolve(type === "AAAA" ? ["::1"] : ["93.184.216.34"]),
      "inner_address",
      true,
    ],
    [
      "https://gone.example.com/feed",
      () => Promise.resolve([]),
      "dns_failed",
      false,
    ],
  ];
  for (const [url, resolve, code, permanent] of cases) {
    const { deps: d, sent } = deps(() => new Response("x"), resolve);
    assertEquals(
      await fetchFeed(url, none, d),
      { kind: "error", code, status: null, permanent },
      url,
    );
    assertEquals(sent.length, 0, url);
  }
});

Deno.test("a redirect is followed by hand and checked again", async () => {
  const { deps: d, sent } = deps((url) =>
    url === "https://old.example.com/feed"
      ? new Response(null, {
        status: 301,
        headers: { Location: "https://new.example.com/rss" },
      })
      : new Response("<rss/>", { status: 200 })
  );
  const result = await fetchFeed("https://old.example.com/feed", {
    etag: '"x"',
    lastModified: null,
  }, d);
  assertEquals(result.kind, "ok");
  if (result.kind === "ok") {
    assertEquals(result.finalUrl, "https://new.example.com/rss");
  }
  assertEquals(sent.length, 2);
  // The cache header is for the first address only.
  assertEquals(
    (sent[1].init.headers as Record<string, string>)["If-None-Match"],
    undefined,
  );
});

Deno.test("a redirect to an inner address is not followed", async () => {
  const resolve: Resolver = (host) =>
    Promise.resolve(
      host === "evil.example.com" ? ["10.0.0.1"] : ["93.184.216.34"],
    );
  for (
    const target of [
      "https://evil.example.com/x",
      "http://blog.example.com/x",
      "https://127.0.0.1/x",
      "https://metadata.internal/x",
    ]
  ) {
    const { deps: d, sent } = deps(
      (url) =>
        url.startsWith("https://blog.example.com/feed")
          ? new Response(null, { status: 302, headers: { Location: target } })
          : new Response("secret", { status: 200 }),
      resolve,
    );
    const result = await fetchFeed("https://blog.example.com/feed", none, d);
    assertEquals(result.kind, "error", target);
    if (result.kind === "error") {
      // A bad address behind a redirect is the site's doing, not final.
      assertEquals(result.permanent, false, target);
    }
    assertEquals(sent.length, 1, target);
  }
});

Deno.test("redirect loops stop", async () => {
  const { deps: d, sent } = deps((url) =>
    new Response(null, { status: 302, headers: { Location: url + "x" } })
  );
  const result = await fetchFeed("https://loop.example.com/a", none, d);
  assertEquals(result, {
    kind: "error",
    code: "too_many_redirects",
    status: 302,
    permanent: false,
  });
  assertEquals(sent.length, MAX_REDIRECTS + 1);
});

Deno.test("statuses become short codes", async () => {
  const cases: [number, string, boolean][] = [
    [404, "http_404", false],
    [403, "http_403", false],
    [410, "http_410", true],
    [429, "rate_limited", false],
    [503, "rate_limited", false],
    [500, "http_500", false],
  ];
  for (const [status, code, permanent] of cases) {
    const { deps: d } = deps(() =>
      new Response("<html>sorry</html>", { status })
    );
    assertEquals(
      await fetchFeed("https://blog.example.com/feed", none, d),
      { kind: "error", code, status, permanent },
    );
  }
});

Deno.test("a body over 512 KB is cut off", async () => {
  const big = "a".repeat(MAX_BODY_BYTES + 1);
  const { deps: d } = deps(() => new Response(big, { status: 200 }));
  assertEquals(
    await fetchFeed("https://blog.example.com/feed", none, d),
    { kind: "error", code: "too_big", status: 200, permanent: false },
  );
  // Declared too big: not read, the connection is dropped.
  let cancelled = false;
  const { deps: d2 } = deps(() => {
    const response = new Response(
      new ReadableStream({
        cancel() {
          cancelled = true;
        },
      }),
      {
        status: 200,
        headers: { "Content-Length": String(MAX_BODY_BYTES + 5) },
      },
    );
    return response;
  });
  const result = await fetchFeed("https://blog.example.com/feed", none, d2);
  assertEquals(result.kind, "error");
  assertEquals(cancelled, true);
  // Exactly at the limit is fine.
  const { deps: d3 } = deps(() =>
    new Response("a".repeat(MAX_BODY_BYTES), { status: 200 })
  );
  assertEquals(
    (await fetchFeed("https://blog.example.com/feed", none, d3)).kind,
    "ok",
  );
});

Deno.test("pictures, video and archives are not feeds", async () => {
  for (
    const type of [
      "image/png",
      "video/mp4",
      "application/pdf",
      "application/zip",
    ]
  ) {
    const { deps: d } = deps(() =>
      new Response("x", { status: 200, headers: { "Content-Type": type } })
    );
    assertEquals(
      await fetchFeed("https://blog.example.com/feed", none, d),
      { kind: "error", code: "not_a_feed", status: 200, permanent: true },
      type,
    );
  }
});

Deno.test("a slow server times out", async () => {
  const { deps: d } = deps(() => {
    throw new DOMException("The signal timed out", "TimeoutError");
  });
  assertEquals(
    await fetchFeed("https://slow.example.com/feed", none, d),
    { kind: "error", code: "timeout", status: null, permanent: false },
  );
  const { deps: d2 } = deps(() => {
    throw new TypeError("connection reset");
  });
  assertEquals(
    await fetchFeed("https://down.example.com/feed", none, d2),
    { kind: "error", code: "network", status: null, permanent: false },
  );
});

Deno.test("the declared encoding is used", () => {
  const latin = new Uint8Array([
    ...new TextEncoder().encode(
      '<?xml version="1.0" encoding="ISO-8859-1"?><t>',
    ),
    0xe9,
    ...new TextEncoder().encode("</t>"),
  ]);
  assert(decodeBody(latin).includes("é"));
  assertEquals(
    decodeBody(new TextEncoder().encode("<t>日本語</t>")),
    "<t>日本語</t>",
  );
  assertEquals(
    decodeBody(
      new TextEncoder().encode(
        '<?xml version="1.0" encoding="nonsense-9"?><t>ok</t>',
      ),
    ),
    '<?xml version="1.0" encoding="nonsense-9"?><t>ok</t>',
  );
});
