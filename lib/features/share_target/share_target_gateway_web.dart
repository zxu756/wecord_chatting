import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:wecord/features/share_target/share_target_gateway.dart';
import 'package:wecord/features/share_target/shared_content.dart';

ShareTargetGateway createPlatformShareTargetGateway() =>
    BrowserShareTargetGateway();

/// Reads the inbox the service worker fills when another app shares to
/// WeCord (see `receiveShare` in web/wecord_sw.js): the cache
/// `wecord-share-inbox` holds `share-meta` (JSON: title, text, url, the
/// files' names, types and sizes, how many were skipped) and each file's
/// bytes under the path the meta names.
class BrowserShareTargetGateway implements ShareTargetGateway {
  static const _cacheName = 'wecord-share-inbox';
  static const _metaPath = 'share-meta';

  bool get _supported => !globalContext['caches'].isUndefinedOrNull;

  String _url(String path) => '${web.window.location.origin}/$path';

  @override
  Future<SharedContent?> read() async {
    if (!_supported) {
      return null;
    }
    try {
      final cache = await web.window.caches.open(_cacheName).toDart;
      final response = await cache.match(_url(_metaPath).toJS).toDart;
      if (response == null) {
        return null;
      }
      final json =
          jsonDecode((await response.text().toDart).toDart)
              as Map<String, dynamic>;
      return SharedContent(
        title: json['title'] as String? ?? '',
        text: json['text'] as String? ?? '',
        url: json['url'] as String? ?? '',
        skippedFiles: (json['skipped'] as num?)?.toInt() ?? 0,
        files: [
          for (final file in (json['files'] as List<dynamic>? ?? const []))
            _file(cache, file as Map<String, dynamic>),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  SharedFile _file(web.Cache cache, Map<String, dynamic> json) {
    final path = json['path'] as String;
    return SharedFile(
      name: json['name'] as String? ?? 'file',
      mimeType: json['type'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      read: () async {
        final response = await cache.match(_url(path).toJS).toDart;
        if (response == null) {
          throw StateError('The shared file is gone.');
        }
        final buffer = await response.arrayBuffer().toDart;
        return Uint8List.view(buffer.toDart);
      },
    );
  }

  @override
  Future<void> clear() async {
    if (!_supported) {
      return;
    }
    try {
      await web.window.caches.delete(_cacheName).toDart;
    } catch (_) {
      // Replaced by the next share anyway.
    }
  }
}
