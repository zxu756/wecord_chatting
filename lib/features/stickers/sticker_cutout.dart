import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/stickers/sticker_cutout_platform.dart';

/// Why a picture could not be cut out.
enum StickerCutoutFailure {
  /// This device or browser cannot do it.
  unavailable,

  /// Not a picture the system can open.
  unreadable,

  /// Nothing in the picture stood out as a subject.
  noSubject,

  /// Anything else.
  failed,
}

class StickerCutoutException implements Exception {
  const StickerCutoutException(this.failure);

  final StickerCutoutFailure failure;

  @override
  String toString() => 'StickerCutoutException(${failure.name})';
}

/// Cuts the subject out of a picture and leaves the rest transparent, on the
/// device: iPhone and Mac use Apple Vision, the browser uses the MediaPipe
/// segmentation model the camera's background blur already loads. The picture
/// never leaves the device. Tests swap in a fake.
abstract interface class StickerCutout {
  /// Whether this device or browser can cut out subjects. Where it cannot,
  /// the option is not shown.
  Future<bool> isAvailable();

  /// A PNG of the subject of [image] (a picture the platform can open), cut
  /// close to the subject on a transparent background. Throws
  /// [StickerCutoutException].
  Future<Uint8List> cutOut(Uint8List image);
}

/// Where there is no cut-out (Android, Windows and Linux; an Apple OS that is
/// too old answers through the plugin).
class UnsupportedStickerCutout implements StickerCutout {
  const UnsupportedStickerCutout();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<Uint8List> cutOut(Uint8List image) => Future.error(
    const StickerCutoutException(StickerCutoutFailure.unavailable),
  );
}

/// The name of the method channel of the native plugin.
const stickerCutoutChannelName = 'wecord/sticker_cutout';

/// Apple Vision through the Runner apps' `StickerCutoutPlugin` (channel
/// `wecord/sticker_cutout`), which runs a
/// `VNGenerateForegroundInstanceMaskRequest` (iOS 17, macOS 14):
///
///  * `isAvailable` answers a bool: whether this OS has the request.
///  * `cutOut {bytes}` answers `{bytes: PNG, width, height}` (the subject,
///    cropped, on a transparent background) or fails with `unsupported` (an
///    older OS), `unreadable` (not a picture), `noSubject` (nothing found) or
///    `failed`.
class NativeStickerCutout implements StickerCutout {
  const NativeStickerCutout([
    this._channel = const MethodChannel(stickerCutoutChannelName),
  ]);

  final MethodChannel _channel;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<Uint8List> cutOut(Uint8List image) async {
    final Map<String, Object?>? result;
    try {
      result = await _channel.invokeMapMethod<String, Object?>('cutOut', {
        'bytes': image,
      });
    } on MissingPluginException {
      throw const StickerCutoutException(StickerCutoutFailure.unavailable);
    } on PlatformException catch (error) {
      throw StickerCutoutException(stickerCutoutFailureFromCode(error.code));
    }
    return stickerCutoutFromChannel(result);
  }
}

/// The failure a native error code stands for.
StickerCutoutFailure stickerCutoutFailureFromCode(String code) {
  return switch (code) {
    'unsupported' => StickerCutoutFailure.unavailable,
    'unreadable' => StickerCutoutFailure.unreadable,
    'noSubject' => StickerCutoutFailure.noSubject,
    _ => StickerCutoutFailure.failed,
  };
}

/// The PNG bytes of what the native plugin answers; throws when it answered
/// nothing usable.
Uint8List stickerCutoutFromChannel(Map<String, Object?>? result) {
  final bytes = result?['bytes'];
  if (bytes is Uint8List && bytes.isNotEmpty) {
    return bytes;
  }
  throw const StickerCutoutException(StickerCutoutFailure.failed);
}

bool get _isApple =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// The cut-out of the native apps: Apple Vision on iOS and macOS, nothing
/// elsewhere. (The browser's is `WebStickerCutout`.)
StickerCutout nativeStickerCutout() {
  return _isApple
      ? const NativeStickerCutout()
      : const UnsupportedStickerCutout();
}

/// How subjects are cut out here. Tests override it.
final stickerCutoutProvider = Provider<StickerCutout>(
  (ref) => platformStickerCutout(),
);

/// Whether the cut-out option is offered at all on this device.
final stickerCutoutAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(stickerCutoutProvider).isAvailable(),
);
