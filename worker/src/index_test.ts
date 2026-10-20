// Run: deno test worker/
import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { type Deps, type Env, handleRequest, routeFor } from "./index.ts";

const origin = "https://wecord.example";
const inviteCode = "h7kq2mpzab";

const publicCard = {
  available: true,
  slug: "pixel-club",
  name: "Pixel Club",
  description: "Pixel art and palettes.",
  icon_url: null,
  category: "art",
  language: "en",
  tags: ["pixel art"],
  member_level: 25,
  join_mode: "open",
};

interface Seen {
  url: string;
  headers: Headers;
  body: unknown;
}

function setup(answer: () => Response | Promise<Response>, cache = false) {
  const seen: Seen[] = [];
  const assets: string[] = [];
  const stored = new Map<string, Response>();
  const pending: Promise<unknown>[] = [];
  const env: Env = {
    ASSETS: {
      fetch: (request) => {
        assets.push(new URL(request.url).pathname);
        return Promise.resolve(
          new Response("<!doctype html>app", { status: 200 }),
        );
      },
    },
    SUPABASE_URL: "https://project.supabase.co/",
    SUPABASE_ANON_KEY: "anon-key",
  };
  const deps: Deps = {
    fetch: async (input, init) => {
      seen.push({
        url: String(input),
        headers: new Headers(init?.headers),
        body: JSON.parse(String(init?.body)),
      });
      return await answer();
    },
    cache: cache
      ? {
        match: (key) => Promise.resolve(stored.get(key.url)?.clone()),
        put: (key, response) => {
          stored.set(key.url, response);
          return Promise.resolve();
        },
      }
      : null,
  };
  const ctx = { waitUntil: (p: Promise<unknown>) => void pending.push(p) };
  const run = async (path: string, init: RequestInit = {}, e: Env = env) => {
    const response = await handleRequest(
      new Request(origin + path, init),
      e,
      ctx,
      deps,
    );
    await Promise.all(pending);
    return response;
  };
  return { run, seen, assets, stored, env };
}

const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });

Deno.test("routeFor owns /c/<slug> and /invite/<code> only", () => {
  assertEquals(routeFor("/c/pixel-club"), {
    kind: "circle",
    param: "pixel-club",
  });
  assertEquals(routeFor("/c/Pixel-Club/"), {
    kind: "circle",
    param: "pixel-club",
  });
  assertEquals(routeFor("/invite/" + inviteCode), {
    kind: "invite",
    param: inviteCode,
  });
  assertEquals(routeFor("/invite/" + inviteCode.toUpperCase()), {
    kind: "invite",
    param: inviteCode,
  });
  for (
    const path of [
      "/",
      "/n/abc",
      "/icons/Icon-512.png",
      "/c",
      "/c/",
      "/invite",
      "/chat/x",
      "/c/a/b",
      "/invite/x/y",
    ]
  ) {
    assert(routeFor(path) === "other" || routeFor(path) === "invalid", path);
  }
  assertEquals(routeFor("/"), "other");
  assertEquals(routeFor("/n/abc"), "other");
  assertEquals(routeFor("/main.dart.js"), "other");
  // Values that can't be a slug or a code never reach the database.
  for (
    const path of [
      "/c/ab",
      "/c/-abc",
      "/c/has%20space",
      "/c/%2e%2e",
      "/c/a%2Fb",
      "/c/%E0%A4%A",
      "/invite/short",
      "/invite/0000000000",
      "/invite/" + "a".repeat(50),
      "/c/" + "a".repeat(40),
    ]
  ) {
    assertEquals(routeFor(path), "invalid", path);
  }
});

Deno.test("other paths go straight to the assets", async () => {
  const t = setup(() => json(publicCard));
  const response = await t.run("/some/app/path");
  assertEquals(await response.text(), "<!doctype html>app");
  assertEquals(t.assets, ["/some/app/path"]);
  assertEquals(t.seen.length, 0);
});

Deno.test("a public circle page asks the database for the slug and nothing else", async () => {
  const t = setup(() => json(publicCard));
  const response = await t.run("/c/Pixel-Club");
  assertEquals(response.status, 200);
  assertEquals(t.seen.length, 1);
  assertEquals(
    t.seen[0].url,
    "https://project.supabase.co/rest/v1/rpc/get_public_circle_card",
  );
  assertEquals(t.seen[0].body, { card_slug: "pixel-club" });
  assertEquals(t.seen[0].headers.get("apikey"), "anon-key");
  assertEquals(t.seen[0].headers.get("authorization"), "Bearer anon-key");
  const html = await response.text();
  assert(html.includes("<h1>Pixel Club</h1>"));
  assert(html.includes(`href="/#/c/pixel-club"`));
  assertEquals(
    response.headers.get("content-type"),
    "text/html; charset=utf-8",
  );
});

Deno.test("an invite page asks for the invite and links to the app's invite route", async () => {
  const t = setup(() => json(publicCard));
  const response = await t.run("/invite/" + inviteCode);
  assertEquals(response.status, 200);
  assertEquals(
    t.seen[0].url,
    "https://project.supabase.co/rest/v1/rpc/get_public_invite_card",
  );
  assertEquals(t.seen[0].body, { invite_code: inviteCode });
  const html = await response.text();
  assert(html.includes(`href="/#/invite/${inviteCode}"`));
  assert(html.includes("invited"));
});

Deno.test("every page carries the CSP and the other security headers", async () => {
  const t = setup(() => json(publicCard));
  for (
    const path of [
      "/c/pixel-club",
      "/c/nope-club",
      "/c/ab",
      "/invite/" + inviteCode,
    ]
  ) {
    const response = await t.run(path);
    const csp = response.headers.get("content-security-policy") ?? "";
    assert(csp.includes("default-src 'none'"), path);
    assertFalse(csp.includes("script-src"), path);
    assertFalse(csp.includes("unsafe-inline"), path);
    assert(csp.includes("frame-ancestors 'none'"), path);
    assertEquals(response.headers.get("x-content-type-options"), "nosniff");
    assertEquals(response.headers.get("referrer-policy"), "no-referrer");
    assert((response.headers.get("x-robots-tag") ?? "").includes("noindex"));
    await response.text();
  }
});

Deno.test("unavailable looks the same whatever the reason", async () => {
  const unavailable = { available: false };
  const bodies: string[] = [];
  const statuses: number[] = [];
  // The database says unavailable (private, taken down, revoked ...).
  const t = setup(() => json(unavailable));
  for (
    const path of [
      "/c/secret-club",
      "/c/delisted-club",
      "/c/no-such-club",
      "/invite/" + inviteCode,
      "/invite/aaaaaaaaaa",
    ]
  ) {
    const response = await t.run(path);
    statuses.push(response.status);
    bodies.push(await response.text());
  }
  // Values that never reach the database.
  for (const path of ["/c/ab", "/invite/short"]) {
    const response = await t.run(path);
    statuses.push(response.status);
    bodies.push(await response.text());
  }
  assertEquals(new Set(statuses), new Set([404]));
  assertEquals(new Set(bodies).size, 1, "one page for all of them");
  assertFalse(/secret|delisted|no-such|aaaaaaaaaa|h7kq2m/.test(bodies[0]));
});

Deno.test("an answer that is not a card is unavailable, not a crash", async () => {
  for (
    const answer of [null, [], "x", { available: true }, {
      available: true,
      name: 4,
    }, { foo: "bar" }]
  ) {
    const t = setup(() => json(answer));
    const response = await t.run("/c/pixel-club");
    assertEquals(response.status, 404, JSON.stringify(answer));
    await response.text();
  }
});

Deno.test("a hostile card is escaped end to end", async () => {
  const t = setup(() =>
    json({
      ...publicCard,
      name: `<script>alert(1)</script>`,
      description: `"><img src=x onerror=alert(1)>`,
      tags: [`<b>x</b>`],
    })
  );
  const html = await (await t.run("/c/pixel-club")).text();
  assertFalse(html.includes("<script>alert"));
  assertFalse(html.includes("<img src=x"));
  assertFalse(html.includes("<b>x</b>"));
  assert(html.includes("&lt;script&gt;alert(1)&lt;/script&gt;"));
});

Deno.test("the page language follows Accept-Language, ?lang= wins", async () => {
  const t = setup(() => json(publicCard));
  const zh = await (await t.run("/c/pixel-club", {
    headers: { "accept-language": "zh-CN,zh;q=0.9,en;q=0.5" },
  })).text();
  assert(zh.includes(`<html lang="zh-CN">`));
  assert(zh.includes("WeCord 上的公开圈子"));
  assert(zh.includes("25+ 位成员"));
  const en = await (await t.run("/c/pixel-club", {
    headers: { "accept-language": "en-US" },
  })).text();
  assert(en.includes(`<html lang="en">`));
  const forced = await (await t.run("/c/pixel-club?lang=zh", {
    headers: { "accept-language": "en-US" },
  })).text();
  assert(forced.includes(`<html lang="zh-CN">`));
  const none = await (await t.run("/c/pixel-club")).text();
  assert(none.includes(`<html lang="en">`));
  // The unavailable page speaks the language too.
  const t2 = setup(() => json({ available: false }));
  const gone = await (await t2.run("/c/nope-club", {
    headers: { "accept-language": "zh-CN" },
  })).text();
  assert(gone.includes("此页面不可用"));
});

Deno.test("a failed lookup is a 503 that is not cached, not 'unavailable'", async () => {
  for (
    const answer of [() => new Response("boom", { status: 500 }), () => {
      throw new Error("network");
    }, () => json({ message: "JWT" }, 401)]
  ) {
    const t = setup(answer, true);
    const response = await t.run("/c/pixel-club");
    assertEquals(response.status, 503);
    assertEquals(response.headers.get("cache-control"), "no-store");
    assertEquals(t.stored.size, 0);
    assert((await response.text()).includes("Temporarily unavailable"));
  }
});

Deno.test("only GET and HEAD, and HEAD has no body", async () => {
  const t = setup(() => json(publicCard));
  for (const method of ["POST", "PUT", "DELETE", "PATCH"]) {
    const response = await t.run("/c/pixel-club", { method, body: "x" });
    assertEquals(response.status, 405, method);
    assertEquals(response.headers.get("allow"), "GET, HEAD");
  }
  assertEquals(t.seen.length, 0);
  const head = await t.run("/c/pixel-club", { method: "HEAD" });
  assertEquals(head.status, 200);
  assertEquals(await head.text(), "");
  assert(head.headers.get("content-security-policy"));
});

Deno.test("without the database settings the web app answers, as before", async () => {
  const t = setup(() => json(publicCard));
  const response = await t.run("/c/pixel-club", {}, { ASSETS: t.env.ASSETS });
  assertEquals(await response.text(), "<!doctype html>app");
  assertEquals(t.seen.length, 0);
});

Deno.test("pages are cached per page and language, briefly", async () => {
  const t = setup(() => json(publicCard), true);
  const first = await t.run("/c/pixel-club", {
    headers: { "accept-language": "en" },
  });
  assertEquals(first.headers.get("cache-control"), "public, max-age=60");
  assertEquals(first.headers.get("vary"), "Accept-Language");
  const body = await first.text();
  assertEquals(t.seen.length, 1);
  assertEquals(t.stored.size, 1);
  // A second visit is served from the cache.
  const second = await t.run("/c/pixel-club", {
    headers: { "accept-language": "en" },
  });
  assertEquals(await second.text(), body);
  assertEquals(second.headers.get("vary"), "Accept-Language");
  assertEquals(t.seen.length, 1);
  // Another language is another entry; a query string is not part of the key.
  await (await t.run("/c/pixel-club", {
    headers: { "accept-language": "zh-CN" },
  })).text();
  assertEquals(t.seen.length, 2);
  assertEquals(t.stored.size, 2);
  await (await t.run("/c/pixel-club?utm=1", {
    headers: { "accept-language": "zh-CN" },
  })).text();
  assertEquals(t.seen.length, 2);
  // Unavailable answers are cached too, so a scan of made-up slugs is cheap
  // for the database, and a different slug is its own entry.
  const t2 = setup(() => json({ available: false }), true);
  await (await t2.run("/c/nope-club")).text();
  await (await t2.run("/c/nope-club")).text();
  assertEquals(t2.seen.length, 1);
});
