// Start-up and scrolling benchmark for the WeCord web builds (L5,
// docs/wasm-report.md). Needs Node 22+ (global WebSocket and fetch) and Google
// Chrome; it installs nothing and talks to Chrome over the DevTools protocol.
//
//   node tool/web_bench/bench.mjs --dir build/web --mode startup --runs 5
//   node tool/web_bench/bench.mjs --dir /tmp/wc_bench --mode scroll --wasm 0
//
// --dir      a built web folder (`flutter build web ...`), served on a
//            throw-away local port with Brotli, ETag and must-revalidate, like
//            Cloudflare's static assets do.
// --mode     startup: cold and warm load until Flutter's first frame, plus the
//                     bytes that crossed the (throttled) network.
//            offline: with ?sw=1 (the service worker is off on localhost
//                     otherwise) load, let wecord_sw.js cache the shell, go
//                     offline, reload and see that the app starts. Serve a
//                     build stamped the way tool/deploy_web.sh does (the
//                     worker caches nothing while its version is the
//                     placeholder).
//            smoke:   load once, list the console errors and uncaught
//                     exceptions, and save a screenshot (--shot file.png).
//            scroll:  open the scroll benchmark app (see scroll_bench.dart)
//                     and read its frame timings.
// --wasm     1 (default): let the loader choose (wasm where the browser can).
//            0: open with ?wasm=0, which forces the JS (CanvasKit) build.
// --isolate  send Cross-Origin-Opener-Policy: same-origin and
//            Cross-Origin-Embedder-Policy: require-corp (--coep credentialless
//            for that variant), which turns skwasm's worker threads on.
// --nowasmgc pretend the browser has no WasmGC (WebAssembly.validate says no),
//            to see the loader fall back to the JS build.
// --net      none (default), broadband (30 Mbit/s, 20 ms) or 4g (9 Mbit/s,
//            85 ms).
// --cpu      CPU slowdown factor (1 default; 4 is a typical mid-range phone).
// --runs     repeats (default 3); the report shows each run and the median.
// --query    extra query string for the page, e.g. "items=8000&seconds=20".
// --chrome   path to the Chrome binary.
//
// Prints one JSON document on stdout. Nothing is written outside a temporary
// Chrome profile that is removed afterwards.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import crypto from 'node:crypto';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((pairs, arg, i, all) => {
    if (arg.startsWith('--')) {
      const next = all[i + 1];
      pairs.push([arg.slice(2), next && !next.startsWith('--') ? next : true]);
    }
    return pairs;
  }, []),
);

const dir = path.resolve(String(args.dir ?? 'build/web'));
const mode = String(args.mode ?? 'startup');
const wasm = String(args.wasm ?? '1') !== '0';
const isolate = Boolean(args.isolate);
const coep = String(args.coep ?? 'require-corp');
const net = String(args.net ?? 'none');
const cpu = Number(args.cpu ?? 1);
const runs = Number(args.runs ?? 3);
const extraQuery = String(args.query ?? '');
const chrome = String(
  args.chrome ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
);

const NETWORKS = {
  none: null,
  broadband: { latency: 20, down: (30 * 1000 * 1000) / 8 },
  '4g': { latency: 85, down: (9 * 1000 * 1000) / 8 },
};
if (!(net in NETWORKS)) throw new Error(`unknown --net ${net}`);

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.json': 'application/json',
  '.png': 'image/png',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.symbols': 'text/plain',
};
const COMPRESSIBLE = new Set(['.html', '.js', '.mjs', '.wasm', '.json', '.otf', '.ttf', '.symbols']);

// ---- a static server that behaves like Cloudflare's static assets ----

const cache = new Map();
function load(file) {
  if (cache.has(file)) return cache.get(file);
  const raw = fs.readFileSync(file);
  const ext = path.extname(file);
  const entry = {
    raw,
    type: TYPES[ext] ?? 'application/octet-stream',
    etag: `"${crypto.createHash('sha1').update(raw).digest('hex').slice(0, 16)}"`,
    br: COMPRESSIBLE.has(ext)
      ? zlib.brotliCompressSync(raw, {
          params: {
            [zlib.constants.BROTLI_PARAM_QUALITY]: 5,
            [zlib.constants.BROTLI_PARAM_SIZE_HINT]: raw.length,
          },
        })
      : null,
  };
  cache.set(file, entry);
  return entry;
}

function serve() {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    let file = path.join(dir, decodeURIComponent(url.pathname));
    if (!file.startsWith(dir)) {
      res.writeHead(403).end();
      return;
    }
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      file = path.join(dir, 'index.html');
    }
    const entry = load(file);
    const headers = {
      'Content-Type': entry.type,
      ETag: entry.etag,
      'Cache-Control': 'public, max-age=0, must-revalidate',
      Vary: 'Accept-Encoding',
    };
    if (isolate) {
      headers['Cross-Origin-Opener-Policy'] = 'same-origin';
      headers['Cross-Origin-Embedder-Policy'] = coep;
    }
    if (req.headers['if-none-match'] === entry.etag) {
      res.writeHead(304, headers).end();
      return;
    }
    const useBr = entry.br && String(req.headers['accept-encoding'] ?? '').includes('br');
    if (useBr) headers['Content-Encoding'] = 'br';
    const body = useBr ? entry.br : entry.raw;
    headers['Content-Length'] = body.length;
    res.writeHead(200, headers).end(body);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

// ---- Chrome over the DevTools protocol ----

async function launch() {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wecord-bench-'));
  const port = 9300 + Math.floor(Math.random() * 500);
  const child = spawn(
    chrome,
    [
      '--headless=new',
      `--remote-debugging-port=${port}`,
      `--user-data-dir=${profile}`,
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-extensions',
      '--disable-background-networking',
      '--window-size=1280,800',
      'about:blank',
    ],
    { stdio: 'ignore' },
  );
  let version;
  for (let i = 0; i < 100 && !version; i++) {
    try {
      version = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
    } catch {
      await new Promise((r) => setTimeout(r, 100));
    }
  }
  if (!version) throw new Error('Chrome did not start');
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = targets.find((t) => t.type === 'page');
  const socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.onopen = resolve;
    socket.onerror = reject;
  });
  let id = 0;
  const pending = new Map();
  const listeners = [];
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) reject(new Error(JSON.stringify(message.error)));
      else resolve(message.result);
    } else if (message.method) {
      for (const listener of listeners) listener(message);
    }
  };
  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const n = ++id;
      pending.set(n, { resolve, reject });
      socket.send(JSON.stringify({ id: n, method, params }));
    });
  const close = async () => {
    try {
      await send('Browser.close');
    } catch {
      /* already gone */
    }
    socket.close();
    child.kill();
    await new Promise((r) => setTimeout(r, 300));
    fs.rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
  };
  return { send, listeners, close, product: version.Browser };
}

const INJECT = `
(() => {
  const bench = (window.__bench = { first: null, raf: [], measureStart: null, measureEnd: null });
  window.addEventListener('flutter-first-frame', () => { bench.first = performance.now(); }, { once: true });
  let state;
  Object.defineProperty(window, '__wecordBenchState', {
    get() { return state; },
    set(v) {
      state = v;
      if (v === 'measuring') bench.measureStart = performance.now();
      if (v === 'done') bench.measureEnd = performance.now();
    },
  });
  const tick = (t) => { bench.raf.push(t); requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
})();
`;

async function evaluate(browser, expression) {
  const { result, exceptionDetails } = await browser.send('Runtime.evaluate', {
    expression,
    returnByValue: true,
  });
  if (exceptionDetails) throw new Error(JSON.stringify(exceptionDetails));
  return result.value;
}

async function until(browser, expression, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = await evaluate(browser, expression);
    if (value) return value;
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error(`timed out waiting for ${label}`);
}

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted.length ? sorted[Math.floor((sorted.length - 1) / 2)] : null;
}

function percentile(sorted, p) {
  return sorted.length ? sorted[Math.min(sorted.length - 1, Math.round((sorted.length - 1) * p))] : null;
}

async function prepare(browser) {
  await browser.send('Page.enable');
  await browser.send('Network.enable');
  await browser.send('Runtime.enable');
  await browser.send('Page.addScriptToEvaluateOnNewDocument', { source: INJECT });
  if (args.nowasmgc) {
    await browser.send('Page.addScriptToEvaluateOnNewDocument', {
      source: 'WebAssembly.validate = () => false;',
    });
  }
  const profile = NETWORKS[net];
  await browser.send('Network.emulateNetworkConditions', {
    offline: false,
    latency: profile?.latency ?? 0,
    downloadThroughput: profile?.down ?? -1,
    uploadThroughput: profile?.down ?? -1,
  });
  if (cpu > 1) await browser.send('Emulation.setCPUThrottlingRate', { rate: cpu });
}

// Loads the page once and returns what was measured.
async function load1(browser, url, { cacheDisabled }) {
  await browser.send('Network.setCacheDisabled', { cacheDisabled });
  const sizes = new Map();
  const urls = new Map();
  let finished = 0;
  const listener = (message) => {
    if (message.method === 'Network.requestWillBeSent') {
      urls.set(message.params.requestId, message.params.request.url);
    } else if (message.method === 'Network.loadingFinished') {
      sizes.set(message.params.requestId, message.params.encodedDataLength);
      finished++;
    }
  };
  browser.listeners.push(listener);
  await browser.send('Page.navigate', { url: 'about:blank' });
  const started = Date.now();
  await browser.send('Page.navigate', { url });
  await until(browser, 'window.__bench && window.__bench.first !== null', 90000, 'first frame');
  const wallMs = Date.now() - started;
  const first = await evaluate(browser, 'window.__bench.first');
  const paints = await evaluate(
    browser,
    `performance.getEntriesByType('paint').map(p => [p.name, p.startTime])`,
  );
  // Let late requests finish (fonts, deferred parts) before counting bytes.
  await new Promise((r) => setTimeout(r, 1500));
  browser.listeners.splice(browser.listeners.indexOf(listener), 1);
  let bytes = 0;
  const files = [];
  for (const [requestId, size] of sizes) {
    const requested = urls.get(requestId) ?? '';
    bytes += size;
    files.push({ url: requested.replace(/^https?:\/\/[^/]+/, ''), bytes: size });
  }
  files.sort((a, b) => b.bytes - a.bytes);
  const usedWasm = files.some((f) => f.url.includes('main.dart.wasm'));
  const usedJs = files.some((f) => /main\.dart\.js(\?|$)/.test(f.url));
  return {
    firstFrameMs: Math.round(first),
    fcpMs: Math.round((paints.find(([n]) => n === 'first-contentful-paint') ?? [0, 0])[1]),
    wallMs,
    transferKB: Math.round(bytes / 1024),
    requests: finished,
    engine: usedWasm ? 'wasm' : usedJs ? 'js' : 'unknown',
    isolated: await evaluate(browser, 'window.crossOriginIsolated'),
    biggest: files.slice(0, 5),
  };
}

async function startup(base) {
  const results = [];
  for (let i = 0; i < runs; i++) {
    const browser = await launch();
    try {
      await prepare(browser);
      const query = `?${wasm ? '' : 'wasm=0&'}${extraQuery}`;
      const cold = await load1(browser, `${base}/${query}`, { cacheDisabled: true });
      // Same browser, HTTP cache on: every file revalidates (304) like a return visit.
      await browser.send('Network.clearBrowserCache').catch(() => {});
      const first = await load1(browser, `${base}/${query}`, { cacheDisabled: false });
      const warm = await load1(browser, `${base}/${query}`, { cacheDisabled: false });
      results.push({ cold, populate: first, warm });
    } finally {
      await browser.close();
    }
  }
  return {
    runs: results,
    median: {
      coldFirstFrameMs: median(results.map((r) => r.cold.firstFrameMs)),
      coldTransferKB: median(results.map((r) => r.cold.transferKB)),
      warmFirstFrameMs: median(results.map((r) => r.warm.firstFrameMs)),
      warmTransferKB: median(results.map((r) => r.warm.transferKB)),
    },
  };
}

async function offline(base) {
  const browser = await launch();
  try {
    await prepare(browser);
    const query = `?sw=1&${wasm ? '' : 'wasm=0&'}${extraQuery}`;
    await browser.send('Page.navigate', { url: `${base}/${query}` });
    await until(browser, 'window.__bench && window.__bench.first !== null', 90000, 'first frame');
    // The worker caches on its install and from the page's list of loaded files.
    await new Promise((r) => setTimeout(r, 8000));
    const controlled = await evaluate(browser, 'Boolean(navigator.serviceWorker.controller)');
    const { result } = await browser.send('Runtime.evaluate', {
      expression: `(async () => {
        const names = await caches.keys();
        const out = {};
        for (const name of names) {
          out[name] = (await (await caches.open(name)).keys()).map((r) => new URL(r.url).pathname);
        }
        return out;
      })()`,
      awaitPromise: true,
      returnByValue: true,
    });
    await browser.send('Network.emulateNetworkConditions', {
      offline: true,
      latency: 0,
      downloadThroughput: -1,
      uploadThroughput: -1,
    });
    await browser.send('Page.navigate', { url: 'about:blank' });
    await browser.send('Page.navigate', { url: `${base}/${query}` });
    let restarted = true;
    try {
      await until(browser, 'window.__bench && window.__bench.first !== null', 30000, 'offline first frame');
    } catch {
      restarted = false;
    }
    const info = restarted
      ? await evaluate(
          browser,
          `({ isolated: window.crossOriginIsolated, skwasm: typeof window._flutter_skwasmInstance !== 'undefined' })`,
        )
      : null;
    const names = Object.keys(result.value ?? {});
    return {
      pageControlledByTheWorker: controlled,
      caches: Object.fromEntries(
        names.map((name) => [
          name,
          {
            files: result.value[name].length,
            wasm: result.value[name].filter((p) => /main\.dart\.(wasm|mjs)$/.test(p)),
            js: result.value[name].filter((p) => /main\.dart\.js$/.test(p)),
            canvaskit: result.value[name].filter((p) => p.startsWith('/canvaskit/')),
          },
        ]),
      ),
      startsOffline: restarted,
      afterOffline: info,
    };
  } finally {
    await browser.close();
  }
}

async function smoke(base) {
  const browser = await launch();
  const messages = [];
  browser.listeners.push((message) => {
    if (message.method === 'Runtime.exceptionThrown') {
      const d = message.params.exceptionDetails;
      messages.push({ kind: 'exception', text: d.exception?.description ?? d.text });
    } else if (message.method === 'Runtime.consoleAPICalled') {
      const { type, args: a } = message.params;
      if (type === 'error' || type === 'warning' || type === 'assert') {
        messages.push({
          kind: type,
          text: a.map((x) => x.value ?? x.description ?? '').join(' ').slice(0, 400),
        });
      }
    } else if (message.method === 'Network.loadingFailed') {
      messages.push({ kind: 'network', text: `${message.params.errorText} ${message.params.requestId}` });
    }
  });
  try {
    await prepare(browser);
    const query = `?${wasm ? '' : 'wasm=0&'}${extraQuery}`;
    await browser.send('Page.navigate', { url: `${base}/${query}` });
    await until(browser, 'window.__bench && window.__bench.first !== null', 90000, 'first frame');
    await new Promise((r) => setTimeout(r, 3000));
    const info = await evaluate(
      browser,
      `({ isolated: window.crossOriginIsolated, skwasm: typeof window._flutter_skwasmInstance !== 'undefined',
          text: document.body.innerText.slice(0, 200),
          scripts: performance.getEntriesByType('resource').map(r => new URL(r.name).pathname).filter(p => /main\\.dart\\.(js|wasm)$/.test(p)),
          glass: document.querySelectorAll('flt-glass-pane').length,
          semantics: document.querySelectorAll('flt-semantics').length })`,
    );
    if (args.shot) {
      const { data } = await browser.send('Page.captureScreenshot', { format: 'png' });
      fs.writeFileSync(String(args.shot), Buffer.from(data, 'base64'));
    }
    return { info, messages };
  } finally {
    await browser.close();
  }
}

async function scroll(base) {
  const results = [];
  for (let i = 0; i < runs; i++) {
    const browser = await launch();
    try {
      await prepare(browser);
      const query = `?${wasm ? '' : 'wasm=0&'}${extraQuery}`;
      await browser.send('Page.navigate', { url: `${base}/${query}` });
      await until(browser, 'window.__bench && window.__bench.first !== null', 90000, 'first frame');
      const seconds = Number(new URLSearchParams(extraQuery).get('seconds') ?? 12);
      const warmup = Number(new URLSearchParams(extraQuery).get('warmup') ?? 3);
      await until(browser, `window.__wecordBenchState === 'done'`, (seconds + warmup + 60) * 1000 * Math.max(1, cpu), 'benchmark');
      const dart = JSON.parse(await evaluate(browser, 'window.__wecordBenchResult'));
      const raf = await evaluate(
        browser,
        `(() => { const b = window.__bench;
           return b.raf.filter(t => t >= b.measureStart && t <= b.measureEnd); })()`,
      );
      const gaps = [];
      for (let k = 1; k < raf.length; k++) gaps.push(raf[k] - raf[k - 1]);
      const sorted = [...gaps].sort((a, b) => a - b);
      const span = raf.length > 1 ? (raf[raf.length - 1] - raf[0]) / 1000 : 0;
      results.push({
        engineFrames: dart,
        rafFps: Number((raf.length / (span || 1)).toFixed(1)),
        rafGapMs: {
          p50: percentile(sorted, 0.5),
          p95: percentile(sorted, 0.95),
          p99: percentile(sorted, 0.99),
          max: sorted.at(-1) ?? null,
        },
        gapsOver20ms: gaps.filter((g) => g > 20).length,
        gapsOver34ms: gaps.filter((g) => g > 34).length,
        isolated: await evaluate(browser, 'window.crossOriginIsolated'),
      });
    } finally {
      await browser.close();
    }
  }
  const pick = (f) => median(results.map(f));
  return {
    runs: results,
    median: {
      rafFps: pick((r) => r.rafFps),
      rafGapP95Ms: pick((r) => r.rafGapMs.p95),
      rafGapP99Ms: pick((r) => r.rafGapMs.p99),
      gapsOver34ms: pick((r) => r.gapsOver34ms),
      buildP90Ms: pick((r) => r.engineFrames.build.p90),
      rasterP90Ms: pick((r) => r.engineFrames.raster.p90),
      totalP50Ms: pick((r) => r.engineFrames.total.p50),
      totalP90Ms: pick((r) => r.engineFrames.total.p90),
      totalP99Ms: pick((r) => r.engineFrames.total.p99),
      slowFrames33: pick((r) => r.engineFrames.slowFrames33),
      frames: pick((r) => r.engineFrames.frames),
    },
  };
}

const server = await serve();
const base = `http://127.0.0.1:${server.address().port}`;
try {
  const body =
    mode === 'scroll'
      ? await scroll(base)
      : mode === 'smoke'
        ? await smoke(base)
        : mode === 'offline'
          ? await offline(base)
          : await startup(base);
  console.log(
    JSON.stringify(
      { mode, dir, wasmRequested: wasm, isolate: isolate ? coep : false, net, cpu, ...body },
      null,
      2,
    ),
  );
} finally {
  server.close();
  process.exit(0);
}
