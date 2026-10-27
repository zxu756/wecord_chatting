// WeCord's app-shell service worker (scope: the whole site).
//
// What it does
// - Keeps the app shell (index.html, flutter_bootstrap.js, main.dart.js,
//   CanvasKit, fonts, icons) in a cache named after this deploy, so the
//   second load is instant and the app opens with no network (chats come
//   from the app's own IndexedDB copy).
// - Shows a friendly offline page when the shell is not cached and the
//   network is down.
// - Tells open pages when a new deploy has finished downloading
//   ({type: 'wecord-update-ready'}); the page's "Update available -
//   Reload" toast answers {type: 'wecord-skip-waiting'}.
// - Receives "Share to WeCord" (the manifest's share_target, Android and
//   ChromeOS): a POST to /share-target carrying text, a link and files. It
//   keeps them in the cache "wecord-share-inbox" (never touched by the
//   deploy cleanup below) and redirects to the app's #/share page, which
//   reads and clears them. Works whether or not this copy is stamped.
//
// What it never touches: anything that is not on this origin (Supabase's
// API, signed storage URLs, Edge Functions, LiveKit, jsDelivr, ...) and any
// non-GET request. Those go straight to the network, uncached.
//
// Web push lives in push_sw.js, a separate worker registered under the
// scope "push/" (see lib/features/push/push_gateway_web.dart). Nothing here
// replaces it: push subscriptions belong to that registration.
//
// tool/deploy_web.sh replaces the version below with a hash of the build,
// so every deploy that changes the app gets its own cache and an update.
// An unstamped copy (a plain `flutter build web`, a dev server) does no
// caching at all, so it can never serve a stale app.
'use strict';

const VERSION = '__WECORD_VERSION__';
const STAMPED = !VERSION.startsWith('__');
const CACHE_PREFIX = 'wecord-shell-';
const CACHE = CACHE_PREFIX + VERSION;
// What older WeCord builds (Flutter's own service worker) left behind.
const LEGACY_CACHE = /^flutter-/;

const SCOPE = new URL(self.registration.scope);
const SHELL_URL = new URL('./', SCOPE).href;

// Web Share Target: where the manifest sends shares, the cache they wait in
// until the app opens, and the app route that shows them. At most this many
// files are kept; the page says how many were left out.
const SHARE_PATH = 'share-target';
const SHARE_CACHE = 'wecord-share-inbox';
const SHARE_META = 'share-meta';
const SHARE_ROUTE = './#/share';
const SHARE_MAX_FILES = 10;
// The largest file a chat takes (maxChatFileBytes in the app).
const SHARE_MAX_BYTES = 50 * 1024 * 1024;

// The shell: install fails (and is retried later) unless these are cached.
const REQUIRED = ['./', 'flutter_bootstrap.js', 'manifest.json'];
// Cached too, but a miss does not fail the install.
const OPTIONAL = [
  'main.dart.js',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/apple-touch-icon.png',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'assets/fonts/MaterialIcons-Regular.otf',
];

// Same-origin paths (below the scope) that are app files and safe to keep:
// everything is versioned by the deploy, so cache-first is correct.
const APP_FILES =
  /^(?:main\.dart\.js[^/]*|flutter(?:_bootstrap)?\.js|manifest\.json|favicon\.png|icons\/.*|canvaskit\/.*|assets\/.*|blur\/.*)$/;

// Never cached even if they were somehow served from this origin: the
// Supabase API families, and any URL carrying a signature or token.
const NEVER_CACHE_PATH =
  /\/(?:rest|auth|storage|functions|realtime|graphql)\/v1\//;
const NEVER_CACHE_QUERY =
  /^(?:token|signature|sig|x-amz-.*|x-goog-.*|expires|jwt|access_token|apikey)$/i;

function appPath(url) {
  return url.pathname.slice(SCOPE.pathname.length);
}

function isCacheableAppFile(url) {
  if (url.origin !== SCOPE.origin) return false;
  if (NEVER_CACHE_PATH.test(url.pathname)) return false;
  for (const key of url.searchParams.keys()) {
    if (NEVER_CACHE_QUERY.test(key)) return false;
  }
  return APP_FILES.test(appPath(url));
}

// A redirected response can't answer a navigation, so store a clean copy.
async function cleanCopy(response) {
  if (!response.redirected) return response;
  return new Response(await response.blob(), {
    status: response.status,
    statusText: response.statusText,
    headers: response.headers,
  });
}

async function addToCache(cache, path, mode) {
  const url = new URL(path, SCOPE).href;
  const response = await fetch(new Request(url, { cache: mode }));
  if (!response.ok) throw new Error(`${url}: ${response.status}`);
  await cache.put(url, await cleanCopy(response));
}

self.addEventListener('install', (event) => {
  if (!STAMPED) {
    self.skipWaiting();
    return;
  }
  // First install: files the page just downloaded come from the browser's
  // HTTP cache. Update: go to the network, the new deploy has new files.
  const firstInstall = !self.registration.active;
  const mode = firstInstall ? 'default' : 'reload';
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      await Promise.all(REQUIRED.map((path) => addToCache(cache, path, mode)));

      // Everything the last version had cached (CanvasKit's variant for this
      // browser, deferred parts, ...) comes along, so an update keeps the
      // app as offline-ready as it was.
      const extra = new Set(OPTIONAL.map((path) => new URL(path, SCOPE).href));
      for (const name of await caches.keys()) {
        if (!name.startsWith(CACHE_PREFIX) || name === CACHE) continue;
        for (const request of await (await caches.open(name)).keys()) {
          extra.add(request.url);
        }
      }
      for (const path of REQUIRED) extra.delete(new URL(path, SCOPE).href);
      await Promise.allSettled(
        [...extra].map((url) => addToCache(cache, url, mode)),
      );

      if (firstInstall) {
        self.skipWaiting();
        return;
      }
      // A version is waiting: tell the open pages, which offer a reload.
      const pages = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });
      for (const page of pages) {
        page.postMessage({ type: 'wecord-update-ready', version: VERSION });
      }
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const name of await caches.keys()) {
        const old = name.startsWith(CACHE_PREFIX)
          ? name !== CACHE
          : LEGACY_CACHE.test(name);
        if (old) await caches.delete(name);
      }
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('message', (event) => {
  const data = event.data;
  if (!data || typeof data !== 'object') return;
  if (data.type === 'wecord-skip-waiting') {
    self.skipWaiting();
  } else if (data.type === 'wecord-cache-urls' && STAMPED) {
    // The page lists what it loaded before this worker existed (the first
    // visit), so the next visit works offline.
    const urls = Array.isArray(data.urls) ? data.urls : [];
    event.waitUntil(
      (async () => {
        const cache = await caches.open(CACHE);
        await Promise.allSettled(
          urls.map(async (value) => {
            const url = new URL(String(value), SCOPE);
            if (!isCacheableAppFile(url)) return;
            if (await cache.match(url.href)) return;
            await addToCache(cache, url.href, 'default');
          }),
        );
      })(),
    );
  }
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method === 'POST') {
    // The only post this worker answers: a share from another app.
    const target = new URL(request.url);
    if (target.origin === SCOPE.origin && appPath(target) === SHARE_PATH) {
      event.respondWith(receiveShare(request));
    }
    return;
  }
  if (!STAMPED) return;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  // Supabase, storage, Edge Functions, CDNs: not ours, not cached.
  if (url.origin !== SCOPE.origin) return;
  // Media and downloads use ranges; leave them to the network.
  if (request.headers.has('range')) return;

  // The developer documentation is a plain static page, not the app.
  if (url.pathname.startsWith('/developers/')) return;

  if (request.mode === 'navigate') {
    event.respondWith(shellFor(request));
  } else if (isCacheableAppFile(url)) {
    event.respondWith(cacheFirst(request, event));
  }
});

// Keeps what another app shared (title, text, link, files) for the app's
// #/share page, then sends the browser there. Whatever goes wrong, the
// browser still lands in the app (the page shows there is nothing to share).
async function receiveShare(request) {
  try {
    const form = await request.formData();
    const text = (name) => {
      const value = form.get(name);
      return typeof value === 'string' ? value : '';
    };
    const cache = await caches.open(SHARE_CACHE);
    // A new share replaces any older one that was never opened.
    for (const key of await cache.keys()) await cache.delete(key);
    const picked = form
      .getAll('files')
      .filter((value) => value && typeof value !== 'string');
    const files = [];
    let skipped = 0;
    for (const file of picked) {
      if (files.length >= SHARE_MAX_FILES || (file.size || 0) > SHARE_MAX_BYTES) {
        skipped++;
        continue;
      }
      const path = 'share-file-' + files.length;
      await cache.put(
        new URL(path, SCOPE).href,
        new Response(file, {
          headers: { 'Content-Type': file.type || 'application/octet-stream' },
        }),
      );
      files.push({
        path,
        name: file.name || 'file',
        type: file.type || '',
        size: file.size || 0,
      });
    }
    const meta = {
      title: text('title'),
      text: text('text'),
      url: text('url'),
      files,
      skipped,
      received: Date.now(),
    };
    await cache.put(
      new URL(SHARE_META, SCOPE).href,
      new Response(JSON.stringify(meta), {
        headers: { 'Content-Type': 'application/json' },
      }),
    );
  } catch (_) {
    // Opens the app with nothing to show.
  }
  return Response.redirect(new URL(SHARE_ROUTE, SCOPE).href, 303);
}

// Every page of the single-page app is the same shell.
async function shellFor(request) {
  const cache = await caches.open(CACHE);
  const shell = await cache.match(SHELL_URL);
  if (shell) return shell;
  try {
    return await fetch(request);
  } catch (_) {
    return offlineResponse();
  }
}

async function cacheFirst(request, event) {
  const cache = await caches.open(CACHE);
  const hit = await cache.match(request, { ignoreSearch: true });
  if (hit) return hit;
  const response = await fetch(request);
  if (response.ok && response.type === 'basic') {
    event.waitUntil(cache.put(request, response.clone()).catch(() => {}));
  }
  return response;
}

// The page shown instead of the browser's error. Inline, so it exists
// whenever this worker does. English or Chinese by the browser's language.
function offlineResponse() {
  return new Response(OFFLINE_HTML, {
    status: 503,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  });
}

const OFFLINE_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>WeCord</title>
<style>
  :root { --paper:#F5F4F1; --panel:#FFFFFF; --ink:#17171A; --muted:#5F5E66;
          --line:#E4E2DD; --accent:#2F6BF6; --on-accent:#FFFFFF; }
  @media (prefers-color-scheme: dark) {
    :root { --paper:#111113; --panel:#1B1B1E; --ink:#F3F2EF; --muted:#A3A1AA;
            --line:#2C2C31; --accent:#6E95FF; --on-accent:#111113; }
  }
  * { box-sizing: border-box; }
  html, body { height: 100%; margin: 0; background: var(--paper); color: var(--ink);
    font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC",
      "Microsoft YaHei", Roboto, sans-serif; }
  main { min-height: 100%; display: flex; flex-direction: column; align-items: center;
    justify-content: center; text-align: center; padding: 32px 24px; }
  .card { background: var(--panel); border: 1px solid var(--line); border-radius: 22px;
    padding: 32px 28px; max-width: 360px; }
  .mark { width: 64px; height: 64px; border-radius: 18px; margin: 0 auto 20px;
    background: var(--accent); display: grid; place-items: center; }
  .mark svg { width: 34px; height: 34px; }
  h1 { font-size: 24px; line-height: 1.2; font-weight: 800; letter-spacing: -0.02em;
    margin: 0 0 8px; }
  p { margin: 0 0 24px; color: var(--muted); }
  button { appearance: none; border: 0; cursor: pointer; font: inherit; font-weight: 700;
    min-height: 44px; padding: 0 24px; border-radius: 999px; background: var(--ink);
    color: var(--paper); }
  button:focus-visible { outline: 3px solid var(--accent); outline-offset: 2px; }
  [lang=zh] { display: none; }
  html.zh [lang=en] { display: none; }
  html.zh [lang=zh] { display: initial; }
</style>
</head>
<body>
<main role="main">
  <div class="card">
    <div class="mark" aria-hidden="true">
      <svg viewBox="0 0 24 24" fill="none" stroke="var(--on-accent)" stroke-width="3"
        stroke-linecap="round" stroke-linejoin="round"><path d="M3 6l4.5 12L12 9l4.5 9L21 6"/></svg>
    </div>
    <h1><span lang="en">You're offline</span><span lang="zh">你已离线</span></h1>
    <p><span lang="en">WeCord can't reach the internet right now. It will pick up where you left off as soon as you're back online.</span><span lang="zh">WeCord 暂时连不上网络。恢复网络后，会从你离开的地方继续。</span></p>
    <button type="button" id="retry"><span lang="en">Try again</span><span lang="zh">重试</span></button>
  </div>
</main>
<script>
  if (/^zh/i.test(navigator.language || '')) document.documentElement.classList.add('zh');
  document.getElementById('retry').addEventListener('click', function () { location.reload(); });
  window.addEventListener('online', function () { location.reload(); });
</script>
</body>
</html>`;
