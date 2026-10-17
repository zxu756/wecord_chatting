// The browser's speech recognition (Web Speech API) for dictation; nothing on
// the other platforms.
export 'package:wecord/features/voice_input/web_speech_stub.dart'
    if (dart.library.js_interop) 'package:wecord/features/voice_input/web_speech_web.dart';
