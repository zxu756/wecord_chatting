import { assertEquals } from "jsr:@std/assert@1";
import {
  charsetFromContentType,
  cleanText,
  extractPreviewMeta,
  isHtmlContentType,
} from "./html_meta.ts";

Deno.test("reads Open Graph tags in any attribute order", () => {
  const html = `<html><head>
    <title>Fallback title</title>
    <meta property="og:title" content="OG &amp; Title">
    <meta content='OG description' property='og:description' />
    <meta property="og:image" content="/img/cover.png">
    <meta property="og:site_name" content="Example Site">
  </head><body></body></html>`;

  assertEquals(extractPreviewMeta(html, "https://example.com/post/1"), {
    title: "OG & Title",
    description: "OG description",
    image_url: "https://example.com/img/cover.png",
    site_name: "Example Site",
  });
});

Deno.test("falls back to title and meta description", () => {
  const html = `<head><TITLE>  Plain
    page  </TITLE><meta name="Description" content="About &#8220;us&#8221;"></head>`;

  assertEquals(extractPreviewMeta(html, "https://example.com/"), {
    title: "Plain page",
    description: "About “us”",
    image_url: null,
    site_name: null,
  });
});

Deno.test("ignores empty OG values and uses twitter tags", () => {
  const html = `<meta property="og:title" content="  ">
    <meta name="twitter:title" content="Tweet title">
    <meta name="twitter:image" content="https://cdn.example.com/a.jpg">`;

  const meta = extractPreviewMeta(html, "https://example.com/");
  assertEquals(meta.title, "Tweet title");
  assertEquals(meta.image_url, "https://cdn.example.com/a.jpg");
});

Deno.test("keeps only http(s) images", () => {
  for (
    const image of [
      "javascript:alert(1)",
      "data:image/png;base64,AAAA",
      "file:///etc/passwd",
    ]
  ) {
    const html = `<meta property="og:image" content="${image}">`;
    assertEquals(
      extractPreviewMeta(html, "https://example.com/").image_url,
      null,
      image,
    );
  }
  const protocolRelative = extractPreviewMeta(
    `<meta property="og:image" content="//cdn.example.com/x.png">`,
    "https://example.com/",
  );
  assertEquals(protocolRelative.image_url, "https://cdn.example.com/x.png");
});

Deno.test("strips tags and truncates long values", () => {
  const html = `<meta property="og:description" content="${"x".repeat(600)}">
    <title>Hi <b>there</b></title>`;
  const meta = extractPreviewMeta(html, "https://example.com/");
  assertEquals(meta.title, "Hi there");
  assertEquals(Array.from(meta.description ?? "").length, 500);
  assertEquals(meta.description?.endsWith("…"), true);
});

Deno.test("returns nulls when nothing is found", () => {
  assertEquals(extractPreviewMeta("<p>hello</p>", "https://example.com/"), {
    title: null,
    description: null,
    image_url: null,
    site_name: null,
  });
});

Deno.test("content type helpers", () => {
  assertEquals(isHtmlContentType("text/html; charset=UTF-8"), true);
  assertEquals(isHtmlContentType("TEXT/HTML"), true);
  assertEquals(isHtmlContentType("application/json"), false);
  assertEquals(isHtmlContentType("image/png"), false);
  assertEquals(isHtmlContentType(null), false);
  assertEquals(
    charsetFromContentType('text/html; charset="Shift_JIS"'),
    "shift_jis",
  );
  assertEquals(charsetFromContentType("text/html"), null);
  assertEquals(cleanText("a&nbsp;&amp;&#x41;&bogus;"), "a &A&bogus;");
});
