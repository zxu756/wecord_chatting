// The cut-out this platform has: a browser segments the picture itself with
// MediaPipe; iOS and macOS use Apple Vision through a plugin; the rest have
// none.
import 'package:wecord/features/stickers/sticker_cutout.dart';
import 'package:wecord/features/stickers/sticker_cutout_native.dart'
    if (dart.library.js_interop) 'package:wecord/features/stickers/sticker_cutout_web.dart';

/// The cut-out of the platform this app runs on.
StickerCutout platformStickerCutout() => createPlatformStickerCutout();
