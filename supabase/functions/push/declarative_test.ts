import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  absoluteUrl,
  DECLARATIVE_WEB_PUSH,
  DEFAULT_SITE_ORIGIN,
  siteOriginFromEnv,
  withDeclarativeFields,
} from "./declarative.ts";

const site = "https://wecord.example";

Deno.test("a chat push carries both the classic and declarative fields", () => {
  const payload = withDeclarativeFields({
    title: "Ada",
    body: "hello",
    tag: "conversation-1",
    url: "/#/chats/conversation-1",
  }, site) as Record<string, unknown>;
  // What push_sw.js reads, unchanged.
  assertEquals(payload.title, "Ada");
  assertEquals(payload.body, "hello");
  assertEquals(payload.tag, "conversation-1");
  assertEquals(payload.url, "/#/chats/conversation-1");
  // What Safari 18.4+ shows by itself.
  assertEquals(payload.web_push, DECLARATIVE_WEB_PUSH);
  assertEquals(payload.web_push, 8030);
  assertEquals(payload.notification, {
    title: "Ada",
    body: "hello",
    navigate: "https://wecord.example/#/chats/conversation-1",
    silent: false,
    tag: "conversation-1",
  });
});

Deno.test("a circle channel path keeps its query", () => {
  const payload = withDeclarativeFields({
    title: "Rust",
    body: "x",
    url: "/#/circles/c1?c=chan",
  }, site) as unknown as { notification: { navigate: string } };
  assertEquals(
    payload.notification.navigate,
    "https://wecord.example/#/circles/c1?c=chan",
  );
});

Deno.test("no tag means no tag in the notification", () => {
  const payload = withDeclarativeFields({
    title: "Ada",
    body: "",
    url: "/",
  }, site) as unknown as { notification: Record<string, unknown> };
  assert(!("tag" in payload.notification));
  assertEquals(payload.notification.navigate, "https://wecord.example/");
});

Deno.test("a payload that cannot be declarative stays classic", () => {
  for (
    const payload of [
      { title: "", body: "x", url: "/" },
      { body: "x", url: "/" },
      { title: "Ada", body: "x" },
      { title: "Ada", body: "x", url: "https://evil.example/phish" },
      { title: "Ada", body: "x", url: "javascript:alert(1)" },
    ]
  ) {
    const result = withDeclarativeFields(payload, site) as Record<
      string,
      unknown
    >;
    assertEquals(result, payload);
    assert(!("web_push" in result));
  }
});

Deno.test("urls are resolved on the site only", () => {
  assertEquals(absoluteUrl("/a", site), "https://wecord.example/a");
  assertEquals(
    absoluteUrl("https://wecord.example/b", site),
    "https://wecord.example/b",
  );
  assertEquals(absoluteUrl("https://other.example/b", site), null);
  assertEquals(absoluteUrl("//other.example/b", site), null);
  assertEquals(absoluteUrl(undefined, site), null);
  assertEquals(absoluteUrl("", site), null);
});

Deno.test("the site origin falls back to the production site", () => {
  // Without WECORD_SITE_URL (or without permission to read it) it is the
  // production site; with it, that site's origin.
  assertEquals(DEFAULT_SITE_ORIGIN, "https://wecord.jokebear.fyi");
  const origin = siteOriginFromEnv();
  assert(origin.startsWith("https://") || origin.startsWith("http://"));
});
