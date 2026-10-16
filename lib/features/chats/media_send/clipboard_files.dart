import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/media_send/clipboard_files_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/chats/media_send/clipboard_files_web.dart'
    as platform;
import 'package:wecord/features/chats/media_send/media_picker.dart';

/// Reads pictures and files pasted into the composer: the pasteboard on
/// macOS, the browser's paste event on the web.
final clipboardFilesProvider = Provider<ClipboardFiles>((ref) {
  return platform.createClipboardFiles();
});
