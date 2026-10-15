// How loud a remote participant plays: native WebRTC scales the track
// itself (1 as sent); browsers play LiveKit's audio elements, which go
// through a gain node above 100%.
export 'package:wecord/features/voice/voice_volume_native.dart'
    if (dart.library.js_interop) 'package:wecord/features/voice/voice_volume_web.dart';
