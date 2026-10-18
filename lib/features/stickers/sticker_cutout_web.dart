import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:wecord/features/stickers/sticker_cutout.dart';

StickerCutout createPlatformStickerCutout() => const WebStickerCutout();

/// Cuts a subject out in the browser with MediaPipe's selfie segmentation:
/// the same model and code the camera's background blur loads (see
/// `lib/features/voice/background/video_background_web.dart` and the import
/// map in `web/index.html`). `web/stickers/cutout.js` does the work:
/// `cutOut(Uint8List)` resolves with a PNG of the subject, cropped, on a
/// transparent background, and rejects with an error whose message is
/// `no_subject` when nobody is in the picture. The picture never leaves the
/// browser; MediaPipe's code, wasm and model are fetched the first time.
///
/// The model finds people, so on the web a cut-out works on portraits and
/// selfies; the iPhone and Mac apps cut out any subject.
class WebStickerCutout implements StickerCutout {
  const WebStickerCutout();

  @override
  Future<bool> isAvailable() async {
    try {
      final global = globalContext;
      return global.has('OffscreenCanvas') &&
          global.has('createImageBitmap') &&
          global.has('WebAssembly');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List> cutOut(Uint8List image) async {
    final JSObject module;
    try {
      module = await _loadModule().timeout(const Duration(seconds: 30));
    } catch (error) {
      debugPrint('Sticker cut-out: could not load the model: $error');
      throw const StickerCutoutException(StickerCutoutFailure.unavailable);
    }
    try {
      final result =
          await (module.callMethod('cutOut'.toJS, image.toJS)!
                  as JSPromise<JSUint8Array>)
              .toDart
              .timeout(const Duration(seconds: 60));
      return result.toDart;
    } catch (error) {
      final text = '$error';
      if (text.contains('no_subject')) {
        throw const StickerCutoutException(StickerCutoutFailure.noSubject);
      }
      if (text.contains('unreadable')) {
        throw const StickerCutoutException(StickerCutoutFailure.unreadable);
      }
      debugPrint('Sticker cut-out failed: $error');
      throw const StickerCutoutException(StickerCutoutFailure.failed);
    }
  }
}

Future<JSObject>? _loading;

/// Loads `stickers/cutout.js` once; a failed load can be tried again.
Future<JSObject> _loadModule() {
  return _loading ??= () async {
    try {
      final url = Uri.base.resolve('stickers/cutout.js').toString();
      return await importModule(url.toJS).toDart;
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }();
}
