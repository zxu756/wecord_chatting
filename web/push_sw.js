// WeCord web push: shows a notification for each push unless a WeCord tab
// is focused (the app shows its own then), and opens the chat on click.
//
// The payload carries two descriptions of the same notification (see
// supabase/functions/push/declarative.ts): the classic top-level fields
// (title, body, tag, url) this worker reads, and the Declarative Web Push
// ones (web_push: 8030, notification: {...}) that Safari 18.4 and later show
// by themselves, without waking this worker, which is what keeps an iPhone
// home screen app's subscription alive. Older browsers ignore the second
// and run this worker as before.

// Safari (iPhone, iPad, Mac) drops a subscription whose pushes do not each
// show a notification, so there a push is always shown, even with the app
// in front. Chrome and Edge allow skipping it while a window is visible.
function mustAlwaysShow() {
  const agent = (self.navigator && self.navigator.userAgent) || '';
  return /AppleWebKit/.test(agent) && !/Chrome|Chromium|Edg|OPR|Firefox/.test(agent);
}

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = {};
  }
  // A declarative push also lists its fields under "notification"; take
  // them when the classic ones are missing.
  const declared =
    data && typeof data.notification === 'object' && data.notification
      ? data.notification
      : {};
  const title = data.title || declared.title || 'WeCord';
  const body = data.body || declared.body || '';
  const tag = data.tag || declared.tag;
  const target = data.url || declared.navigate || '/';
  event.waitUntil((async () => {
    if (!mustAlwaysShow()) {
      const windows = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });
      if (windows.some((client) => client.focused)) {
        return;
      }
    }
    await self.registration.showNotification(title, {
      body,
      tag,
      renotify: Boolean(tag),
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      data: { url: target },
    });
  })());
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL(
    (event.notification.data && event.notification.data.url) || '/',
    self.location.origin,
  ).href;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });
    for (const client of windows) {
      if (new URL(client.url).origin === self.location.origin) {
        try {
          await client.focus();
          client.postMessage({ type: 'wecord-open', url });
          return;
        } catch (_) {
          // A window that cannot be focused (a suspended home screen app):
          // open the chat in a new one below.
        }
      }
    }
    await self.clients.openWindow(url);
  })());
});

// The browser replaced or dropped the subscription (Safari and Firefox do
// this now and then). Take a new one with the same key so pushes keep
// coming; the app saves it on the server the next time it starts.
self.addEventListener('pushsubscriptionchange', (event) => {
  event.waitUntil((async () => {
    const options = event.oldSubscription && event.oldSubscription.options;
    const key = options && options.applicationServerKey;
    if (!key) {
      return;
    }
    try {
      await self.registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: key,
      });
    } catch (_) {
      // Permission was withdrawn: the app shows push as off.
    }
  })());
});
