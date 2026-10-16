import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wecord/features/chats/media_send/album_layout.dart';
import 'package:wecord/features/chats/media_send/media_draft.dart';
import 'package:wecord/features/file_preview/native_file_bridge.dart';
import 'package:wecord/features/file_preview/preview_platform_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/file_preview/preview_platform_web.dart'
    as platform;

/// Lets the user choose several photos, videos or files at once.
abstract interface class ChatMediaPicker {
  /// The photo library (iOS), or an image and video chooser (macOS, web);
  /// up to [limit] items. Empty when cancelled.
  Future<List<XFile>> pickPhotosAndVideos({int limit = maxAlbumItems});

  /// A file chooser for anything; empty when cancelled.
  Future<List<XFile>> pickFiles();
}

final chatMediaPickerProvider = Provider<ChatMediaPicker>((ref) {
  return SystemChatMediaPicker(ImagePicker());
});

class SystemChatMediaPicker implements ChatMediaPicker {
  SystemChatMediaPicker(this._picker);

  final ImagePicker _picker;

  @override
  Future<List<XFile>> pickPhotosAndVideos({int limit = maxAlbumItems}) {
    return _picker.pickMultipleMedia(limit: limit < 2 ? null : limit);
  }

  @override
  Future<List<XFile>> pickFiles() => openFiles();
}

/// A still frame of a video file for its poster, made on the device:
/// AVFoundation on iOS and macOS (through the app's native bridge), a
/// canvas on the web; null elsewhere.
final videoPosterReaderProvider = Provider<VideoPosterReader>((ref) {
  final bridge = ref.watch(nativeFileBridgeProvider);
  return (XFile file) async {
    if (kIsWeb) {
      return platform.captureWebVideoPoster(Uri.parse(file.path), 480);
    }
    if (file.path.isEmpty) {
      return null;
    }
    return bridge.videoPoster(Uri.file(file.path), maxSize: 480);
  };
});

/// Files copied or screenshotted to the clipboard, and pasted into the
/// composer.
abstract interface class ClipboardFiles {
  /// Whether this platform can read pasted pictures and files.
  bool get isSupported;

  /// What a paste would bring (macOS: asked of the pasteboard when Cmd+V is
  /// pressed); empty when the clipboard holds no files or pictures.
  Future<List<XFile>> read();

  /// Files pasted by the browser (the web); never emits elsewhere.
  Stream<List<XFile>> get pasted;
}

/// Where the clipboard cannot hand over files.
class NoClipboardFiles implements ClipboardFiles {
  const NoClipboardFiles();

  @override
  bool get isSupported => false;

  @override
  Future<List<XFile>> read() async => const [];

  @override
  Stream<List<XFile>> get pasted => const Stream.empty();
}

/// For a list of bytes and names, as XFiles (what a native clipboard
/// channel returns).
List<XFile> xFilesFromClipboard(List<({String name, Uint8List bytes})> items) {
  return [
    for (final item in items)
      // The path carries the name: it is all `name` is made from outside
      // the web. The bytes are used when the file is read.
      XFile.fromData(
        item.bytes,
        name: item.name,
        path: item.name,
        length: item.bytes.length,
      ),
  ];
}
