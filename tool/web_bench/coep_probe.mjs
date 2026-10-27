// What cross-origin isolation (COOP/COEP) would block on a page (L5,
// docs/wasm-report.md). Serves a small page on one local port and a few
// cross-origin resources on another, loads the page in headless Chrome under
// three header sets and prints, for each, which resources loaded:
//
//   node tool/web_bench/coep_probe.mjs
//
// The resources stand for what WeCord loads from other sites: an image from a
// host with no CORS or CORP headers (a link preview, an avatar), one that sends
// CORS only (OpenStreetMap tiles), one that sends CORP (CDN scripts), an
// embedded page (an iframe). Needs Node 22+ and Chrome.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

const chrome =
  process.argv[2] ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  'base64',
);

function listen(handler) {
  const server = http.createServer(handler);
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

const other = await listen((req, res) => {
  const url = new URL(req.url, 'http://x');
  const headers = {};
  if (url.pathname === '/plain.png') {
    // Nothing: like most image hosts.
  } else if (url.pathname === '/cors.png') {
    headers['Access-Control-Allow-Origin'] = '*';
  } else if (url.pathname === '/corp.js') {
    headers['Cross-Origin-Resource-Policy'] = 'cross-origin';
  } else if (url.pathname === '/plain.js') {
    // No CORP.
  }
  if (url.pathname.endsWith('.png')) {
    res.writeHead(200, { 'Content-Type': 'image/png', ...headers }).end(PNG);
  } else if (url.pathname.endsWith('.js')) {
    res
      .writeHead(200, { 'Content-Type': 'text/javascript', ...headers })
      .end('window.__loaded = (window.__loaded || []).concat(["' + url.pathname + '"]);');
  } else if (url.pathname === '/frame.html') {
    res.writeHead(200, { 'Content-Type': 'text/html' }).end('<p>framed</p>');
  } else {
    res.writeHead(404).end();
  }
});
const otherOrigin = `http://127.0.0.1:${other.address().port}`;

let variant = {};
const page = await listen((req, res) => {
  const headers = { 'Content-Type': 'text/html' };
  if (variant.coop) headers['Cross-Origin-Opener-Policy'] = variant.coop;
  if (variant.coep) headers['Cross-Origin-Embedder-Policy'] = variant.coep;
  res.writeHead(200, headers).end(`<!doctype html><body>
<img id="plain" src="${otherOrigin}/plain.png">
<img id="cors-attr" crossorigin="anonymous" src="${otherOrigin}/cors.png">
<img id="cors-no-attr" src="${otherOrigin}/cors.png">
<script src="${otherOrigin}/corp.js"></script>
<script src="${otherOrigin}/plain.js"></script>
<iframe id="frame" src="${otherOrigin}/frame.html"></iframe>
</body>`);
});
const pageOrigin = `http://127.0.0.1:${page.address().port}`;

const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wecord-coep-'));
const port = 9800 + Math.floor(Math.random() * 100);
const child = spawn(
  chrome,
  ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--no-first-run', 'about:blank'],
  { stdio: 'ignore' },
);
let targets;
for (let i = 0; i < 100 && !targets; i++) {
  try {
    targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  } catch {
    await new Promise((r) => setTimeout(r, 100));
  }
}
const socket = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl);
await new Promise((resolve) => (socket.onopen = resolve));
let n = 0;
const pending = new Map();
let events = [];
socket.onmessage = (event) => {
  const m = JSON.parse(event.data);
  if (m.id && pending.has(m.id)) {
    pending.get(m.id)(m.result);
    pending.delete(m.id);
  } else if (m.method) events.push(m);
};
const send = (method, params = {}) =>
  new Promise((resolve) => {
    const id = ++n;
    pending.set(id, resolve);
    socket.send(JSON.stringify({ id, method, params }));
  });
await send('Page.enable');
await send('Network.enable');
await send('Runtime.enable');

const variants = {
  'no headers (today)': {},
  'COOP same-origin + COEP require-corp': { coop: 'same-origin', coep: 'require-corp' },
  'COOP same-origin + COEP credentialless': { coop: 'same-origin', coep: 'credentialless' },
};

const out = {};
for (const [name, headers] of Object.entries(variants)) {
  variant = headers;
  events = [];
  await send('Page.navigate', { url: 'about:blank' });
  await send('Page.navigate', { url: `${pageOrigin}/?${Date.now()}` });
  await new Promise((r) => setTimeout(r, 1500));
  const { result } = await send('Runtime.evaluate', {
    returnByValue: true,
    expression: `({
      isolated: window.crossOriginIsolated,
      plainPng: document.getElementById('plain').complete && document.getElementById('plain').naturalWidth > 0,
      corsPngWithCrossorigin: document.getElementById('cors-attr').complete && document.getElementById('cors-attr').naturalWidth > 0,
      corsPngWithoutCrossorigin: document.getElementById('cors-no-attr').complete && document.getElementById('cors-no-attr').naturalWidth > 0,
      scriptWithCorp: (window.__loaded || []).includes('/corp.js'),
      scriptWithoutCorp: (window.__loaded || []).includes('/plain.js'),
    })`,
  });
  const urls = new Map(
    events
      .filter((e) => e.method === 'Network.requestWillBeSent')
      .map((e) => [e.params.requestId, new URL(e.params.request.url).pathname]),
  );
  const blocked = events
    .filter((e) => e.method === 'Network.loadingFailed' && e.params.blockedReason)
    .map((e) => `${urls.get(e.params.requestId)}: ${e.params.blockedReason}`);
  out[name] = { ...result.value, blockedByTheBrowser: [...new Set(blocked)].sort() };
}
console.log(JSON.stringify(out, null, 2));
socket.close();
child.kill();
await new Promise((r) => setTimeout(r, 500));
fs.rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
other.close();
page.close();
process.exit(0);
