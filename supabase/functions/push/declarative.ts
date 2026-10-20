// Declarative Web Push (https://webkit.org/blog/16535/), shown by Safari 18.4
// and later (iPhone, iPad and Mac) without running any script. It is what
// keeps a home screen web app's subscription alive: Safari drops a
// subscription whose service worker ever receives a push and shows nothing.
//
// A declarative message is JSON with `web_push: 8030` and the notification
// under `notification`, whose `navigate` is an absolute URL. Browsers that
// do not know it read the classic top-level fields (title, body, tag, url)
// the service worker (web/push_sw.js) shows, so both are sent in one message
// and every browser takes what it understands.
//
// No `app_badge`: a badge is the number of unread chats, which the server
// does not count for web push yet (the app sets the badge itself while it
// runs); a wrong number would be worse than none.

/// The magic number that marks a message as a declarative push.
export const DECLARATIVE_WEB_PUSH = 8030;

/// Where WeCord is served, the origin `navigate` URLs point at. Overridden
/// with the function secret WECORD_SITE_URL (for a staging site).
export const DEFAULT_SITE_ORIGIN = "https://wecord.jokebear.fyi";

/// The classic payload every sender builds.
export interface ClassicPushPayload {
  title?: unknown;
  body?: unknown;
  tag?: unknown;
  url?: unknown;
}

/// The site's origin from the environment, or the default when none is set
/// (or the environment cannot be read).
export function siteOriginFromEnv(): string {
  try {
    const value = Deno.env.get("WECORD_SITE_URL")?.trim();
    if (value) {
      const origin = new URL(value).origin;
      return origin === "null" ? DEFAULT_SITE_ORIGIN : origin;
    }
  } catch {
    // No permission, or not a URL: the default.
  }
  return DEFAULT_SITE_ORIGIN;
}

/// [payload] with the declarative fields added next to the classic ones.
/// A payload that cannot be shown declaratively (no title, or a URL that is
/// not a path or on the site) is returned as it is.
export function withDeclarativeFields<T extends ClassicPushPayload>(
  payload: T,
  siteOrigin: string = DEFAULT_SITE_ORIGIN,
): T | (T & { web_push: number; notification: Record<string, unknown> }) {
  const title = typeof payload.title === "string" ? payload.title.trim() : "";
  const navigate = absoluteUrl(payload.url, siteOrigin);
  if (title === "" || navigate === null) {
    return payload;
  }
  const notification: Record<string, unknown> = {
    title,
    body: typeof payload.body === "string" ? payload.body : "",
    navigate,
    silent: false,
  };
  if (typeof payload.tag === "string" && payload.tag !== "") {
    notification.tag = payload.tag;
  }
  return { ...payload, web_push: DECLARATIVE_WEB_PUSH, notification };
}

/// [url] (a path like `/#/chats/x`, or a full URL on the site) as an
/// absolute URL on [siteOrigin]; null for anything else.
export function absoluteUrl(url: unknown, siteOrigin: string): string | null {
  if (typeof url !== "string" || url === "") {
    return null;
  }
  try {
    const base = new URL(siteOrigin);
    const resolved = new URL(url, base);
    return resolved.origin === base.origin ? resolved.href : null;
  } catch {
    return null;
  }
}
