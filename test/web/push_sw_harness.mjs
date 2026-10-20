// Runs web/push_sw.js against a fake service worker environment and checks
// what it shows for classic and declarative payloads, when it stays quiet,
// and where a click goes.
//
//   node test/web/push_sw_harness.mjs web/push_sw.js
//
// Called by test/web/wecord_sw_test.dart (skipped where node is missing).
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(process.argv[2], 'utf8');
const ORIGIN = 'https://wecord.test';
const SAFARI =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_4 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1';
const CHROME =
  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/130.0.0.0 Mobile Safari/537.36';
const CHROME_MAC =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/130.0.0.0 Safari/537.36';
const failures = [];
let checks = 0;

function check(name, ok) {
  checks++;
  if (!ok) failures.push(name);
}

function makeWorker({ userAgent, windows = [] }) {
  const handlers = {};
  const shown = [];
  const opened = [];
  const subscribed = [];
  const fakeSelf = {
    location: new URL(`${ORIGIN}/push_sw.js`),
    navigator: { userAgent },
    registration: {
      showNotification: async (title, options) => {
        shown.push({ title, options });
      },
      pushManager: {
        subscribe: async (options) => {
          subscribed.push(options);
          return {};
        },
      },
    },
    clients: {
      matchAll: async () => windows,
      openWindow: async (url) => {
        opened.push(url);
      },
    },
    addEventListener: (type, handler) => {
      handlers[type] = handler;
    },
  };
  vm.runInNewContext(source, {
    self: fakeSelf,
    URL,
    Boolean,
    RegExp,
    Promise,
  });
  return { handlers, shown, opened, subscribed };
}

async function push(worker, payload) {
  const waits = [];
  worker.handlers.push({
    data: { json: () => payload },
    waitUntil: (promise) => waits.push(promise),
  });
  await Promise.all(waits);
}

async function click(worker, url) {
  const waits = [];
  let closed = false;
  worker.handlers.notificationclick({
    notification: { close: () => (closed = true), data: { url } },
    waitUntil: (promise) => waits.push(promise),
  });
  await Promise.all(waits);
  return closed;
}

const classic = {
  title: 'Ada',
  body: 'hello',
  tag: 'c1',
  url: '/#/chats/c1',
};
const declarative = {
  ...classic,
  web_push: 8030,
  notification: {
    title: 'Ada',
    body: 'hello',
    navigate: `${ORIGIN}/#/chats/c1`,
    silent: false,
    tag: 'c1',
  },
};
const focusedWindow = { url: `${ORIGIN}/`, focused: true };

// A classic push shows its fields and remembers where it leads.
{
  const worker = makeWorker({ userAgent: CHROME });
  await push(worker, classic);
  check('a classic push is shown', worker.shown.length === 1);
  check(
    'a classic push shows its title, body and tag',
    worker.shown[0].title === 'Ada' &&
      worker.shown[0].options.body === 'hello' &&
      worker.shown[0].options.tag === 'c1' &&
      worker.shown[0].options.renotify === true,
  );
  check(
    'a classic push opens its url when clicked',
    worker.shown[0].options.data.url === '/#/chats/c1',
  );
}

// A push with both descriptions is shown once, from the classic fields.
{
  const worker = makeWorker({ userAgent: CHROME });
  await push(worker, declarative);
  check(
    'a declarative push still shows through the worker where it runs',
    worker.shown.length === 1 &&
      worker.shown[0].title === 'Ada' &&
      worker.shown[0].options.data.url === '/#/chats/c1',
  );
}

// A push that only has the declarative fields is still shown.
{
  const worker = makeWorker({ userAgent: CHROME });
  await push(worker, {
    web_push: 8030,
    notification: { title: 'Bo', body: 'hi', navigate: `${ORIGIN}/#/chats/c2` },
  });
  check(
    'a push with only the declarative fields is shown',
    worker.shown.length === 1 &&
      worker.shown[0].title === 'Bo' &&
      worker.shown[0].options.body === 'hi' &&
      worker.shown[0].options.data.url === `${ORIGIN}/#/chats/c2`,
  );
}

// Nothing to read: a generic notification, never nothing.
{
  const worker = makeWorker({ userAgent: CHROME });
  await push(worker, {});
  check(
    'an empty push still shows a notification',
    worker.shown.length === 1 && worker.shown[0].title === 'WeCord',
  );
}

// With the app in front, Chrome and Edge stay quiet (the app shows its own).
for (const [name, agent] of [['Chrome on Android', CHROME], ['Chrome on a Mac', CHROME_MAC]]) {
  const worker = makeWorker({ userAgent: agent, windows: [focusedWindow] });
  await push(worker, classic);
  check(`${name} shows nothing while a WeCord window is focused`, worker.shown.length === 0);
}

// Safari drops a subscription that gets a push and shows nothing.
{
  const worker = makeWorker({ userAgent: SAFARI, windows: [focusedWindow] });
  await push(worker, classic);
  check(
    'Safari is shown a notification even while a window is focused',
    worker.shown.length === 1,
  );
}

// Clicks.
{
  const window = {
    url: `${ORIGIN}/`,
    focused: false,
    focus: async () => {
      window.focusCalls++;
    },
    focusCalls: 0,
    messages: [],
    postMessage(message) {
      this.messages.push(message);
    },
  };
  const worker = makeWorker({ userAgent: CHROME, windows: [window] });
  const closed = await click(worker, '/#/chats/c1');
  check('a click closes the notification', closed);
  check(
    'a click focuses the open app and tells it where to go',
    window.focusCalls === 1 &&
      window.messages.length === 1 &&
      window.messages[0].type === 'wecord-open' &&
      window.messages[0].url === `${ORIGIN}/#/chats/c1` &&
      worker.opened.length === 0,
  );
}
{
  const worker = makeWorker({ userAgent: CHROME, windows: [] });
  await click(worker, '/#/chats/c1');
  check(
    'a click opens the chat in a new window when the app is closed',
    worker.opened.length === 1 && worker.opened[0] === `${ORIGIN}/#/chats/c1`,
  );
}
{
  const stuck = {
    url: `${ORIGIN}/`,
    focus: async () => {
      throw new TypeError('not allowed');
    },
    postMessage() {
      throw new Error('must not be told');
    },
  };
  const worker = makeWorker({ userAgent: SAFARI, windows: [stuck] });
  await click(worker, '/#/chats/c1');
  check(
    'a window that cannot be focused is replaced by a new one',
    worker.opened.length === 1 && worker.opened[0] === `${ORIGIN}/#/chats/c1`,
  );
}
{
  const foreign = { url: 'https://other.test/', focus: async () => {}, postMessage() {} };
  const worker = makeWorker({ userAgent: CHROME, windows: [foreign] });
  await click(worker, '/');
  check('a window of another site is never used', worker.opened.length === 1);
}

// The browser replacing the subscription: take a new one with the same key.
{
  const worker = makeWorker({ userAgent: SAFARI });
  const waits = [];
  const key = new Uint8Array([4, 1, 2, 3]);
  worker.handlers.pushsubscriptionchange({
    oldSubscription: { options: { applicationServerKey: key } },
    waitUntil: (promise) => waits.push(promise),
  });
  await Promise.all(waits);
  check(
    'a replaced subscription is renewed with the same key',
    worker.subscribed.length === 1 &&
      worker.subscribed[0].userVisibleOnly === true &&
      worker.subscribed[0].applicationServerKey === key,
  );
  const none = makeWorker({ userAgent: SAFARI });
  const more = [];
  none.handlers.pushsubscriptionchange({
    oldSubscription: null,
    waitUntil: (promise) => more.push(promise),
  });
  await Promise.all(more);
  check('without the old key nothing is subscribed', none.subscribed.length === 0);
}

if (failures.length > 0) {
  console.error(`${failures.length} of ${checks} checks failed:`);
  for (const name of failures) console.error(`  - ${name}`);
  process.exit(1);
}
console.log(`${checks} checks passed`);
