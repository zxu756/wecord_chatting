// The background effects this platform has: a browser blurs the camera
// itself; iOS and macOS open the system's video effects; the rest have none.
export 'package:wecord/features/voice/background/video_background_native.dart'
    if (dart.library.js_interop) 'package:wecord/features/voice/background/video_background_web.dart';
