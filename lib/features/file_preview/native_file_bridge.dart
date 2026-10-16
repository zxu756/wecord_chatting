import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Runner apps' small native side for files (channel
/// `wecord/quicklook`): Quick Look previews, "Open in…", saving a copy
/// and video poster frames. iOS and macOS only; tests swap in a fake.
abstract interface class NativeFileBridge {
  /// Whether this platform has the native side at all.
  bool get isSupported;

  /// Whether Quick Look can show the local file at [path].
  Future<bool> canPreview(String path);

  /// Shows the local file at [path] in Quick Look (QLPreviewController on
  /// iOS, the Quick Look panel on macOS); completes when it is closed.
  Future<void> preview(String path, {required String title});

  /// Offers the apps that open the file (iOS), or opens it in its default
  /// app (macOS). False when nothing can.
  Future<bool> openIn(String path, {Rect? anchor});

  /// Asks where to save a copy (document picker on iOS, save panel on
  /// macOS). False when cancelled.
  Future<bool> exportCopy(String path, {required String name});

  /// A JPEG frame from early in the (remote or local) video, or null.
  Future<Uint8List?> videoPoster(Uri url, {int maxSize = 480});
}

final nativeFileBridgeProvider = Provider<NativeFileBridge>((ref) {
  return const MethodChannelFileBridge();
});

bool get _isApple =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

class MethodChannelFileBridge implements NativeFileBridge {
  const MethodChannelFileBridge({
    this._channel = const MethodChannel('wecord/quicklook'),
  });

  final MethodChannel _channel;

  @override
  bool get isSupported => _isApple;

  @override
  Future<bool> canPreview(String path) async {
    if (!isSupported) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('canPreview', {'path': path}) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> preview(String path, {required String title}) async {
    await _channel.invokeMethod<void>('preview', {
      'path': path,
      'title': title,
    });
  }

  @override
  Future<bool> openIn(String path, {Rect? anchor}) async {
    return await _channel.invokeMethod<bool>('openIn', {
          'path': path,
          if (anchor != null) ...{
            'x': anchor.left,
            'y': anchor.top,
            'width': anchor.width,
            'height': anchor.height,
          },
        }) ??
        false;
  }

  @override
  Future<bool> exportCopy(String path, {required String name}) async {
    return await _channel.invokeMethod<bool>('exportCopy', {
          'path': path,
          'name': name,
        }) ??
        false;
  }

  @override
  Future<Uint8List?> videoPoster(Uri url, {int maxSize = 480}) async {
    if (!isSupported) {
      return null;
    }
    try {
      return await _channel.invokeMethod<Uint8List>('videoPoster', {
        'url': url.toString(),
        'maxSize': maxSize,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
