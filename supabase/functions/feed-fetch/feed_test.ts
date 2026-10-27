import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  FeedError,
  itemKey,
  parseFeed,
  plainText,
  readDate,
  safeLink,
} from "./feed.ts";

const NOW = Date.parse("2026-10-28T12:00:00Z");
const BASE = "https://blog.example.com/feed.xml";

const rss = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>The Trail &amp; Blog</title>
    <link>https://blog.example.com/</link>
    <atom:link href="https://blog.example.com/feed.xml" rel="self" type="application/rss+xml"/>
    <item>
      <title><![CDATA[Packing <b>light</b> for 3 days]]></title>
      <link>https://blog.example.com/p/2</link>
      <guid isPermaLink="false">post-2</guid>
      <pubDate>Tue, 27 Oct 2026 08:30:00 GMT</pubDate>
      <description>&lt;p&gt;A short &lt;em&gt;guide&lt;/em&gt; &amp;amp; checklist.&lt;/p&gt;&lt;script&gt;alert(1)&lt;/script&gt;</description>
    </item>
    <item>
      <title>Second&#8217;s post</title>
      <link>/p/1</link>
      <pubDate>not a date</pubDate>
      <content:encoded><![CDATA[<div>Full <a href="http://evil.example">text</a> here</div>]]></content:encoded>
    </item>
  </channel>
</rss>`;

Deno.test("reads an RSS feed", () => {
  const feed = parseFeed(rss, BASE, NOW);
  assertEquals(feed.title, "The Trail & Blog");
  assertEquals(feed.items.length, 2);
  assertEquals(feed.items[0], {
    id: "post-2",
    title: "Packing light for 3 days",
    link: "https://blog.example.com/p/2",
    summary: "A short guide & checklist.",
    published: "2026-10-27T08:30:00.000Z",
  });
  // A relative link resolves on the feed's address; a bad date is nothing;
  // the summary falls back to the full content, as text.
  assertEquals(feed.items[1].link, "https://blog.example.com/p/1");
  assertEquals(feed.items[1].published, null);
  assertEquals(feed.items[1].title, "Second’s post");
  assertEquals(feed.items[1].summary, "Full text here");
  assertEquals(feed.items[1].id, "https://blog.example.com/p/1");
});

const atom = `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title type="html">Release &lt;notes&gt;</title>
  <link rel="self" href="https://app.example.com/atom.xml"/>
  <entry>
    <title>v2.0</title>
    <id>tag:app.example.com,2026:v2</id>
    <link rel="alternate" type="text/html" href="https://app.example.com/v2"/>
    <link rel="enclosure" href="https://app.example.com/v2.zip"/>
    <updated>2026-10-26T10:00:00+02:00</updated>
    <summary type="text">Big release</summary>
  </entry>
  <entry>
    <title>Only content</title>
    <id>tag:app.example.com,2026:v1</id>
    <link href="http://app.example.com/v1"/>
    <published>2026-10-01T00:00:00Z</published>
    <content type="html">&lt;p&gt;Hello&lt;br/&gt;world&lt;/p&gt;</content>
  </entry>
</feed>`;

Deno.test("reads an Atom feed", () => {
  const feed = parseFeed(atom, "https://app.example.com/atom.xml", NOW);
  assertEquals(feed.title, "Release");
  assertEquals(feed.items.length, 2);
  assertEquals(feed.items[0].id, "tag:app.example.com,2026:v2");
  assertEquals(feed.items[0].link, "https://app.example.com/v2");
  assertEquals(feed.items[0].published, "2026-10-26T08:00:00.000Z");
  assertEquals(feed.items[0].summary, "Big release");
  // An http link is left off.
  assertEquals(feed.items[1].link, null);
  assertEquals(feed.items[1].summary, "Hello world");
});

Deno.test("reads RSS 1.0 (RDF)", () => {
  const feed = parseFeed(
    `<?xml version="1.0"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel rdf:about="https://old.example.org/"><title>Old site</title></channel>
  <item rdf:about="https://old.example.org/1"><title>One</title><link>https://old.example.org/1</link><dc:date>2026-10-20T00:00:00Z</dc:date></item>
</rdf:RDF>`,
    "https://old.example.org/rss",
    NOW,
  );
  assertEquals(feed.title, "Old site");
  assertEquals(feed.items.length, 1);
  assertEquals(feed.items[0].published, "2026-10-20T00:00:00.000Z");
});

Deno.test("refuses documents with a DOCTYPE or entities", () => {
  const bomb = `<?xml version="1.0"?>
<!DOCTYPE lolz [<!ENTITY lol "lol"><!ENTITY lol2 "&lol;&lol;&lol;&lol;">]>
<rss><channel><title>&lol2;</title></channel></rss>`;
  const error = assertThrows(() => parseFeed(bomb, BASE, NOW), FeedError);
  assertEquals(error.code, "doctype_refused");
  assertThrows(
    () => parseFeed(`<!doctype html><html></html>`, BASE, NOW),
    FeedError,
  );
  assertThrows(
    () => parseFeed(`<rss><!ENTITY x "y"></rss>`, BASE, NOW),
    FeedError,
  );
});

Deno.test("something that is not a feed is refused", () => {
  const error = assertThrows(
    () => parseFeed("<html><body>Hello</body></html>", BASE, NOW),
    FeedError,
  );
  assertEquals(error.code, "not_a_feed");
  assertThrows(() => parseFeed("just text", BASE, NOW), FeedError);
  assertThrows(
    () => parseFeed("<!-- never closed <rss>", BASE, NOW),
    FeedError,
  );
});

Deno.test("keeps only 50 items, and only the fields it needs", () => {
  const items = Array.from(
    { length: 80 },
    (_, index) =>
      `<item><title>Item ${index}</title><guid>g${index}</guid><secret>hidden</secret></item>`,
  ).join("");
  const feed = parseFeed(
    `<rss><channel><title>Many</title>${items}</channel></rss>`,
    BASE,
    NOW,
  );
  assertEquals(feed.items.length, 50);
  assertEquals(Object.keys(feed.items[0]).sort(), [
    "id",
    "link",
    "published",
    "summary",
    "title",
  ]);
});

Deno.test("a pile of unclosed tags does not sink the feed", () => {
  const pile = "<br>".repeat(100);
  const feed = parseFeed(
    `<rss><channel><title>T</title><item><title>A</title><description>${pile}text</description></item><item><title>B</title></item></channel></rss>`,
    BASE,
    NOW,
  );
  assertEquals(feed.items.map((item) => item.title), ["A", "B"]);
});

Deno.test("plain text: tags and scripts go, entities decode, space is tidy", () => {
  assertEquals(
    plainText(
      "<p>Hello&nbsp;<b>there</b></p><script>x()</script>\n\n  you",
      100,
    ),
    "Hello there you",
  );
  assertEquals(plainText("&lt;img src=x onerror=alert(1)&gt;ok", 100), "ok");
  assertEquals(plainText("a‮b​c\u0007d", 100), "a b c d");
  assertEquals(plainText("x".repeat(500), 10), "xxxxxxxxx…");
  assertEquals(plainText("&#128512;&#xD800;&#1114112;", 100), "😀");
});

Deno.test("links: https only, resolved, no credentials", () => {
  assertEquals(safeLink("/a?b=1#frag", BASE), "https://blog.example.com/a?b=1");
  assertEquals(safeLink("http://blog.example.com/a", BASE), null);
  assertEquals(safeLink("javascript:alert(1)", BASE), null);
  assertEquals(safeLink("https://user:pw@blog.example.com/", BASE), null);
  assertEquals(safeLink("", BASE), null);
  assertEquals(
    safeLink("https://blog.example.com/" + "a".repeat(600), BASE),
    null,
  );
});

Deno.test("dates: ISO or RFC 822, never far in the future", () => {
  assertEquals(
    readDate("Wed, 28 Oct 2026 08:00:00 GMT", NOW),
    "2026-10-28T08:00:00.000Z",
  );
  assertEquals(
    readDate("2026-10-28T08:00:00Z", NOW),
    "2026-10-28T08:00:00.000Z",
  );
  assertEquals(readDate("2030-01-01T00:00:00Z", NOW), null);
  assertEquals(readDate("", NOW), null);
  assertEquals(readDate("tomorrow-ish", NOW), null);
});

Deno.test("item keys are short, stable and differ per item", async () => {
  const feed = parseFeed(rss, BASE, NOW);
  const first = await itemKey(feed.items[0]);
  assertEquals(first, await itemKey(feed.items[0]));
  assert(/^[0-9a-f]{16}$/.test(first));
  assert(first !== await itemKey(feed.items[1]));
});
