import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:wecord/features/storage/disk_cache.dart';

/// The browser keeps no files of its own for the app.
DiskCache openPlatformDiskCache() => const NoDiskCache();

/// `navigator.storage.estimate()`: what this site uses (IndexedDB, caches,
/// the service worker) and the most it may.
Future<BrowserEstimate?> estimatePlatformBrowserStorage() async {
  try {
    final estimate = await web.window.navigator.storage.estimate().toDart;
    final usage = estimate.usage;
    final quota = estimate.quota;
    if (usage < 0 || quota <= 0) {
      return null;
    }
    return BrowserEstimate(usage: usage, quota: quota);
  } on Object {
    return null;
  }
}
