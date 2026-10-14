// WeCord web push: shows a notification for each push unless a WeCord tab
// is focused (the app shows its own then), and opens the chat on click.
self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = {};
  }
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });
    if (windows.some((client) => client.focused)) {
      return;
    }
    await self.registration.showNotification(data.title || 'WeCord', {
      body: data.body || '',
      tag: data.tag,
      renotify: Boolean(data.tag),
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      data: { url: data.url || '/' },
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
        await client.focus();
        client.postMessage({ type: 'wecord-open', url });
        return;
      }
    }
    await self.clients.openWindow(url);
  })());
});
