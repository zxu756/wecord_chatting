// Runs web/wecord_sw.js against a fake service worker environment and checks
// what it caches, what it leaves alone and what it tells the pages.
//
//   node test/web/wecord_sw_harness.mjs web/wecord_sw.js
//
// Called by test/web/wecord_sw_test.dart (skipped where node is missing).
// Exits 0 when every check passes; prints each failed check otherwise.
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(process.argv[2], 'utf8');
const ORIGIN = 'https://wecord.test';
const failures = [];
let checks = 0;

function check(name, ok) {
  checks++;
  if (!ok) failures.push(name);
}

class FakeCache {
  constructor() {
    this.entries = new Map();
  }
  static key(request, ignoreSearch) {
    const url = new URL(typeof request === 'string' ? request : request.url);
    if (ignoreSearch) url.search = '';
    return url.href;
  }
  async put(request, response) {
    this.entries.set(FakeCache.key(request, false), response);
  }
  async match(request, options = {}) {
    const wanted = FakeCache.key(request, options.ignoreSearch);
    for (const [key, response] of this.entries) {
      if (FakeCache.key(key, options.ignoreSearch) === wanted) {
        return response.clone();
      }
    }
    return undefined;
  }
  async keys() {
    return [...this.entries.keys()].map((url) => new Request(url));
  }
}

function makeWorker({ stamped = true, active = false, existingCaches = [] }) {
  const handlers = {};
  const stores = new Map(existingCaches.map((name) => [name, new FakeCache()]));
  const posted = [];
  const network = { online: true, requests: [], files: new Map() };
  const state = { skipWaiting: 0, claimed: 0 };

  const fakeSelf = {
    registration: { scope: `${ORIGIN}/`, active: active ? {} : null },
    location: new URL(`${ORIGIN}/wecord_sw.js`),
    clients: {
      matchAll: async () => [{ postMessage: (message) => posted.push(message) }],
      claim: async () => {
        state.claimed++;
      },
    },
    skipWaiting: () => {
      state.skipWaiting++;
    },
    addEventListener: (type, handler) => {
      handlers[type] = handler;
    },
  };
  const sandbox = {
    self: fakeSelf,
    caches: {
      open: async (name) => {
        if (!stores.has(name)) stores.set(name, new FakeCache());
        return stores.get(name);
      },
      keys: async () => [...stores.keys()],
      delete: async (name) => stores.delete(name),
    },
    fetch: async (request) => {
      const url = typeof request === 'string' ? request : request.url;
      network.requests.push({ url, cache: request.cache });
      if (!network.online) throw new TypeError('offline');
      const body = network.files.get(url);
      if (body === undefined) return new Response('missing', { status: 404 });
      const response = new Response(body, { status: 200 });
      // Same-origin responses are 'basic'; Node's constructor says 'default'.
      Object.defineProperty(response, 'type', { value: 'basic' });
      return response;
    },
    Response,
    Request,
    Headers,
    URL,
    Promise,
    Set,
    Array,
    Map,
    console,
  };
  const code = stamped
    ? source.replace('__WECORD_VERSION__', 'v1')
    : source;
  vm.runInNewContext(code, sandbox);
  for (const path of [
    '/',
    '/flutter_bootstrap.js',
    '/manifest.json',
    '/main.dart.js',
    '/icons/Icon-192.png',
    '/canvaskit/canvaskit.js',
  ]) {
    network.files.set(`${ORIGIN}${path}`, `body of ${path}`);
  }
  return { handlers, stores, posted, network, state };
}

async function fire(worker, type, extra = {}) {
  const waits = [];
  const event = {
    ...extra,
    waits,
    responded: null,
    waitUntil: (promise) => waits.push(promise),
    respondWith(promise) {
      this.responded = promise;
    },
  };
  worker.handlers[type](event);
  await Promise.all(waits);
  return event;
}

function request(url, { method = 'GET', mode = 'no-cors', range = false } = {}) {
  const headers = new Headers();
  if (range) headers.set('range', 'bytes=0-10');
  return { url, method, mode, headers };
}

// First install: caches the shell, takes over at once.
{
  const worker = makeWorker({});
  await fire(worker, 'install');
  const cache = worker.stores.get('wecord-shell-v1');
  check('install creates the versioned cache', Boolean(cache));
  check('install caches the shell', Boolean(await cache.match(`${ORIGIN}/`)));
  check(
    'install caches flutter_bootstrap.js',
    Boolean(await cache.match(`${ORIGIN}/flutter_bootstrap.js`)),
  );
  check(
    'install keeps going when an optional file is missing',
    !(await cache.match(`${ORIGIN}/assets/FontManifest.json`)),
  );
  check('first install skips waiting', worker.state.skipWaiting === 1);
  check('first install announces no update', worker.posted.length === 0);
}

// An install fails (and retries later) when the shell cannot be fetched.
{
  const worker = makeWorker({});
  worker.network.online = false;
  let failed = false;
  try {
    await fire(worker, 'install');
  } catch (_) {
    failed = true;
  }
  check('install fails without the shell', failed);
}

// Serving.
{
  const worker = makeWorker({});
  await fire(worker, 'install');

  const nav = await fire(worker, 'fetch', {
    request: request(`${ORIGIN}/circles/abc`, { mode: 'navigate' }),
  });
  const shell = await nav.responded;
  check('navigations get the cached shell', (await shell.text()) === 'body of /');

  worker.network.online = false;
  const offlineNav = await fire(worker, 'fetch', {
    request: request(`${ORIGIN}/`, { mode: 'navigate' }),
  });
  check(
    'the shell opens offline',
    (await (await offlineNav.responded).text()) === 'body of /',
  );

  worker.network.online = true;
  worker.network.requests.length = 0;
  const first = await fire(worker, 'fetch', {
    request: request(`${ORIGIN}/canvaskit/canvaskit.js`),
  });
  await first.responded;
  await Promise.all(first.waits);
  check('an uncached app file is fetched once', worker.network.requests.length === 1);
  const second = await fire(worker, 'fetch', {
    request: request(`${ORIGIN}/canvaskit/canvaskit.js`),
  });
  await second.responded;
  check('and then served from the cache', worker.network.requests.length === 1);
  const precached = await fire(worker, 'fetch', {
    request: request(`${ORIGIN}/main.dart.js`),
  });
  check(
    'precached files never touch the network',
    (await (await precached.responded).text()) === 'body of /main.dart.js' &&
      worker.network.requests.length === 1,
  );

  for (const [name, req] of [
    ['cross-origin API calls', request('https://abc.supabase.co/rest/v1/messages')],
    ['signed storage URLs', request('https://abc.supabase.co/storage/v1/object/sign/x?token=t')],
    ['Edge Function calls', request('https://abc.supabase.co/functions/v1/push')],
    ['posts', request(`${ORIGIN}/main.dart.js`, { method: 'POST' })],
    ['range requests', request(`${ORIGIN}/main.dart.js`, { range: true })],
    ['same-origin API paths', request(`${ORIGIN}/rest/v1/messages`)],
    ['the push worker', request(`${ORIGIN}/push_sw.js`)],
    ['unknown files', request(`${ORIGIN}/something.bin`)],
  ]) {
    const event = await fire(worker, 'fetch', { request: req });
    check(`${name} are left to the network`, event.responded === null);
  }
}

// Offline with no shell: the friendly page.
{
  const worker = makeWorker({});
  worker.network.online = false;
  const nav = await fire(worker, 'fetch', {
    request: request(`${ORIGIN}/`, { mode: 'navigate' }),
  });
  const page = await nav.responded;
  const html = await page.text();
  check('offline page is served', page.status === 503 && html.includes('offline'));
  check('offline page is bilingual', html.includes('你已离线'));
}

// An update: waits, tells the pages, keeps the old cache's extra files.
{
  const worker = makeWorker({ active: true, existingCaches: ['wecord-shell-v0'] });
  const old = worker.stores.get('wecord-shell-v0');
  await old.put(`${ORIGIN}/icons/Icon-192.png`, new Response('old'));
  await old.put(`${ORIGIN}/main.dart.js_1.part.js`, new Response('old'));
  worker.network.files.set(`${ORIGIN}/main.dart.js_1.part.js`, 'new part');
  await fire(worker, 'install');
  const cache = worker.stores.get('wecord-shell-v1');
  check('an update does not skip waiting by itself', worker.state.skipWaiting === 0);
  check(
    'an update tells open pages',
    worker.posted.length === 1 &&
      worker.posted[0].type === 'wecord-update-ready' &&
      worker.posted[0].version === 'v1',
  );
  check(
    'an update carries over what the old version cached',
    Boolean(await cache.match(`${ORIGIN}/main.dart.js_1.part.js`)),
  );
  check(
    'an update fetches from the network',
    worker.network.requests.every((r) => r.cache === 'reload'),
  );

  worker.handlers.message({ data: { type: 'wecord-skip-waiting' }, waitUntil() {} });
  check('skip-waiting is honoured', worker.state.skipWaiting === 1);

  await fire(worker, 'activate');
  check(
    'activate removes the old cache',
    !worker.stores.has('wecord-shell-v0') && worker.stores.has('wecord-shell-v1'),
  );
  check('activate takes over the pages', worker.state.claimed === 1);
}

// Legacy Flutter caches are removed.
{
  const worker = makeWorker({ existingCaches: ['flutter-app-cache', 'unrelated'] });
  await fire(worker, 'activate');
  check(
    'activate clears the old Flutter caches only',
    !worker.stores.has('flutter-app-cache') && worker.stores.has('unrelated'),
  );
}

// Pages can hand over what they loaded before the worker existed.
{
  const worker = makeWorker({});
  await fire(worker, 'install');
  worker.network.files.set(`${ORIGIN}/canvaskit/canvaskit.wasm`, 'wasm');
  worker.network.files.set('https://evil.test/canvaskit/canvaskit.wasm', 'x');
  worker.network.files.set(`${ORIGIN}/rest/v1/x`, 'x');
  await fire(worker, 'message', {
    data: {
      type: 'wecord-cache-urls',
      urls: [
        `${ORIGIN}/canvaskit/canvaskit.wasm`,
        'https://evil.test/canvaskit/canvaskit.wasm',
        `${ORIGIN}/rest/v1/x`,
      ],
    },
  });
  const cache = worker.stores.get('wecord-shell-v1');
  check('handed-over app files are cached', Boolean(await cache.match(`${ORIGIN}/canvaskit/canvaskit.wasm`)));
  check('handed-over foreign files are not', !(await cache.match('https://evil.test/canvaskit/canvaskit.wasm')));
  check('handed-over API paths are not', !(await cache.match(`${ORIGIN}/rest/v1/x`)));
}

// An unstamped copy does nothing.
{
  const worker = makeWorker({ stamped: false });
  await fire(worker, 'install');
  check('unstamped install caches nothing', worker.stores.size === 0);
  const event = await fire(worker, 'fetch', {
    request: request(`${ORIGIN}/`, { mode: 'navigate' }),
  });
  check('unstamped worker serves nothing', event.responded === null);
}

if (failures.length > 0) {
  console.error(`${failures.length} of ${checks} checks failed:`);
  for (const name of failures) console.error(`  - ${name}`);
  process.exit(1);
}
console.log(`${checks} checks passed`);
