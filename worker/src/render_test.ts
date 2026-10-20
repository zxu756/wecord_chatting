// Run: deno test worker/
import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  type Card,
  escapeHtml,
  PAGE_CSS,
  parseCard,
  pickLanguage,
  renderCardPage,
  renderErrorPage,
  renderUnavailablePage,
  securityHeaders,
  sha256Base64,
} from "./render.ts";

const evil = `<script>alert(1)</script>"'><img src=x onerror=alert(2)>&amp;`;

function card(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    available: true,
    slug: "pixel-club",
    name: "Pixel Club",
    description: "Pixel art, palettes and weekly challenges.",
    icon_url: "https://img.example/a/pixel.png?x=1",
    category: "art",
    language: "en",
    tags: ["pixel art", "palettes"],
    member_level: 50,
    join_mode: "open",
    ...extra,
  };
}

function page(
  raw: Record<string, unknown>,
  kind: "circle" | "invite" = "circle",
  lang: "en" | "zh" = "en",
): string {
  const parsed = parseCard(raw) as Card;
  assert(parsed, "the card parses");
  return renderCardPage(parsed, {
    lang,
    kind,
    origin: "https://wecord.example",
    param: "pixel-club",
  });
}

Deno.test("escapeHtml escapes every character that can break out", () => {
  assertEquals(
    escapeHtml(`<a href="x" onclick='y'>&\``),
    "&lt;a href=&quot;x&quot; onclick=&#39;y&#39;&gt;&amp;&#96;",
  );
});

Deno.test("a hostile name, description and tags never become markup", () => {
  const html = page(card({
    name: evil,
    description: evil,
    tags: [evil],
  }));
  assertFalse(html.includes("<script>alert(1)"));
  assertFalse(html.includes("<img src=x"));
  assertFalse(html.includes("onerror=alert(2)>"));
  // The text is still there, as text.
  assert(html.includes("&lt;script&gt;alert(1)&lt;/script&gt;"));
  // Only the page's own tags exist: no element came from the data.
  assertEquals((html.match(/<script/gi) ?? []).length, 0);
  assertEquals((html.match(/<img/gi) ?? []).length, 1);
});

Deno.test("a hostile name cannot leave the title or the meta attributes", () => {
  const html = page(
    card({
      name:
        `</title><meta http-equiv="refresh" content="0;url=https://evil.example">`,
    }),
  );
  assertFalse(html.includes(`</title><meta http-equiv`));
  assertFalse(html.includes(`<meta http-equiv`));
  const title = /<title>([^<]*)<\/title>/.exec(html);
  assert(title, "one clean title element");
  assert(/<meta property="og:title" content="[^"<>]*">/.test(html));
  assert(/<meta name="description" content="[^"<>]*">/.test(html));
});

Deno.test("the picture must be a plain https address", () => {
  for (
    const icon of [
      "http://img.example/a.png",
      "javascript:alert(1)",
      "data:text/html,<script>alert(1)</script>",
      `https://img.example/"onerror="alert(1)`,
      "https://img.example/a b.png",
      "https://img.example/<x>",
      "//img.example/a.png",
      42,
      null,
      "https://" + "a".repeat(300),
    ]
  ) {
    const parsed = parseCard(card({ icon_url: icon }));
    assertEquals(parsed?.iconUrl, null, String(icon));
  }
  assertEquals(
    parseCard(card())?.iconUrl,
    "https://img.example/a/pixel.png?x=1",
  );
  const html = page(card());
  assert(html.includes(`<img src="https://img.example/a/pixel.png?x=1"`));
  assert(
    html.includes(
      `<meta property="og:image" content="https://img.example/a/pixel.png?x=1">`,
    ),
  );
});

Deno.test("without a picture the Open Graph image is the app icon", () => {
  const html = page(card({ icon_url: null }));
  assert(html.includes(`content="https://wecord.example/icons/Icon-512.png"`));
  assertEquals((html.match(/<img/gi) ?? []).length, 0);
});

Deno.test("parseCard refuses anything that is not an available card", () => {
  for (
    const raw of [
      null,
      undefined,
      "x",
      42,
      [],
      {},
      { available: false },
      { available: "true", name: "x" },
      { available: true },
      { available: true, name: "" },
      { available: true, name: 5 },
      { available: true, name: "   " },
    ]
  ) {
    assertEquals(parseCard(raw), null, JSON.stringify(raw));
  }
});

Deno.test("parseCard bounds and checks every field", () => {
  const parsed = parseCard(card({
    name: "n".repeat(500),
    description: "d".repeat(900),
    category: "<b>",
    language: "xx",
    tags: ["a", "b", "c", "d", "e", "f", 5, null, "t".repeat(100)],
    member_level: 7,
    join_mode: "whatever",
    slug: "Not A Slug",
  })) as Card;
  assertEquals(Array.from(parsed.name).length, 100);
  assertEquals(Array.from(parsed.description ?? "").length, 300);
  assertEquals(parsed.category, null);
  assertEquals(parsed.language, null);
  assertEquals(parsed.tags.length, 5);
  assertEquals(parsed.memberLevel, null);
  assertEquals(parsed.joinMode, "open");
  assertEquals(parsed.slug, null);
  // Control characters are dropped.
  assertEquals(parseCard(card({ name: "a\u0000b\u0007c" }))?.name, "abc");
});

Deno.test("the member count is shown as a level, and hidden below 5", () => {
  assert(page(card({ member_level: 50 })).includes("50+ members"));
  assert(page(card({ member_level: 1000 })).includes("1,000+ members"));
  const hidden = page(card({ member_level: null }));
  assertFalse(hidden.includes("members<"));
  assertFalse(/\d\+ members/.test(hidden));
  assert(
    page(card({ member_level: 50 }), "circle", "zh").includes("50+ 位成员"),
  );
});

Deno.test("a card page links into the web app's own routes", () => {
  assert(page(card()).includes(`href="/#/c/pixel-club"`));
  assert(page(card(), "invite").includes(`href="/#/invite/pixel-club"`));
  // The canonical address is the page itself.
  assert(
    page(card()).includes(
      `<link rel="canonical" href="https://wecord.example/c/pixel-club">`,
    ),
  );
});

Deno.test("the button says what will happen", () => {
  assert(page(card({ join_mode: "open" })).includes(">Join in WeCord<"));
  assert(
    page(card({ join_mode: "apply" })).includes(">Request to join in WeCord<"),
  );
  assert(page(card({ join_mode: "invite_only" })).includes(">Open in WeCord<"));
  // A valid invite always lets you in (or to ask).
  assert(
    page(card({ join_mode: "invite_only" }), "invite").includes(
      ">Join in WeCord<",
    ),
  );
  assert(
    page(card({ join_mode: "open" }), "circle", "zh").includes(
      ">在 WeCord 中加入<",
    ),
  );
  assert(
    page(card({ join_mode: "apply" }), "circle", "zh").includes(
      "这个圈子需要审核才能加入",
    ),
  );
  assert(page(card(), "invite").includes("You&#39;re invited to join"));
  assert(page(card(), "invite", "zh").includes("邀请你加入"));
});

Deno.test("pages are in English or Chinese and say so in lang", () => {
  const en = page(card());
  const zh = page(card(), "circle", "zh");
  assert(en.includes(`<html lang="en">`));
  assert(zh.includes(`<html lang="zh-CN">`));
  assert(zh.includes("WeCord 上的公开圈子"));
  assert(zh.includes("艺术 · English · 50+ 位成员"));
  assert(en.includes("Art · English · 50+ members"));
  assert(
    renderUnavailablePage("zh", "https://x.example").includes("此页面不可用"),
  );
  assert(
    renderUnavailablePage("en", "https://x.example").includes(
      "This page isn&#39;t available",
    ),
  );
  assert(renderErrorPage("zh", "https://x.example").includes("暂时无法访问"));
});

Deno.test("pickLanguage follows q-values and falls back to English", () => {
  assertEquals(pickLanguage(null), "en");
  assertEquals(pickLanguage(""), "en");
  assertEquals(pickLanguage("zh-CN,zh;q=0.9,en;q=0.8"), "zh");
  assertEquals(pickLanguage("en-US,en;q=0.9,zh;q=0.8"), "en");
  assertEquals(pickLanguage("fr;q=0.9, zh-Hans;q=0.8"), "zh");
  assertEquals(pickLanguage("zh;q=0.2, en;q=0.9"), "en");
  assertEquals(pickLanguage("ja,ko"), "en");
  assertEquals(pickLanguage("zh;q=0"), "en");
  assertEquals(pickLanguage("zh-TW"), "zh");
  assertEquals(pickLanguage("english"), "en");
  // ?lang= wins over the header, but only for the two languages.
  assertEquals(pickLanguage("zh-CN", "en"), "en");
  assertEquals(pickLanguage("en", "zh"), "zh");
  assertEquals(pickLanguage("zh-CN", "fr"), "zh");
  assertEquals(pickLanguage("zh-CN", "<script>"), "zh");
  assertEquals(pickLanguage("x".repeat(100000) + ",zh"), "en");
});

Deno.test("the unavailable page is one page, whatever the reason", () => {
  const a = renderUnavailablePage("en", "https://wecord.example");
  const b = renderUnavailablePage("en", "https://wecord.example");
  assertEquals(a, b);
  // It names no circle, slug or code, and is not indexable.
  assertFalse(/pixel|invite\//i.test(a));
  assert(a.includes(`<meta name="robots" content="noindex, nofollow">`));
  assertFalse(a.includes("og:url"));
});

Deno.test("every page is indexable by nobody and has no script", () => {
  for (
    const html of [
      page(card()),
      renderUnavailablePage("en", "https://wecord.example"),
      renderErrorPage("zh", "https://wecord.example"),
    ]
  ) {
    assert(html.includes(`<meta name="robots" content="noindex, nofollow">`));
    assert(html.includes(`<meta name="referrer" content="no-referrer">`));
    assertEquals((html.match(/<script/gi) ?? []).length, 0);
    assertEquals((html.match(/<style>/g) ?? []).length, 1);
    assertFalse(/\son[a-z]+=/i.test(html), "no inline event handlers");
    assertFalse(/style="/.test(html), "no inline style attributes");
  }
});

Deno.test("the CSP allows no script and only the page's own style", async () => {
  const headers = await securityHeaders();
  const csp = headers["Content-Security-Policy"];
  assert(csp.includes("default-src 'none'"));
  assertFalse(csp.includes("script-src"));
  assertFalse(csp.includes("'unsafe-inline'"));
  assertFalse(csp.includes("'unsafe-eval'"));
  assert(csp.includes("frame-ancestors 'none'"));
  assert(csp.includes("base-uri 'none'"));
  assert(csp.includes("form-action 'none'"));
  assert(csp.includes("img-src https:"));
  const hash = await sha256Base64(PAGE_CSS);
  assert(csp.includes(`style-src 'sha256-${hash}'`));
  assertEquals(headers["X-Content-Type-Options"], "nosniff");
  assertEquals(headers["X-Frame-Options"], "DENY");
  assertEquals(headers["Referrer-Policy"], "no-referrer");
  assert(headers["X-Robots-Tag"].includes("noindex"));
});

Deno.test("the hash in the CSP is of the exact style text on the page", async () => {
  const html = page(card());
  const inline = /<style>([\s\S]*?)<\/style>/.exec(html)![1];
  assertEquals(inline, PAGE_CSS);
  assertEquals(await sha256Base64(inline), await sha256Base64(PAGE_CSS));
});
