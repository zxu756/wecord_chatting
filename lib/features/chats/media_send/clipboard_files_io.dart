import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';

ClipboardFiles createClipboardFiles() {
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
      ? const MacosClipboardFiles()
      : const NoClipboardFiles();
}

/// Asks the macOS pasteboard (MainFlutterWindow.swift, channel
/// `wecord/clipboard`) for copied files and screenshots. Text on the
/// pasteboard is left to the text field.
class MacosClipboardFiles implements ClipboardFiles {
  const MacosClipboardFiles({
    this._channel = const MethodChannel('wecord/clipboard'),
  });

  final MethodChannel _channel;

  @override
  bool get isSupported => true;

  @override
  Stream<List<XFile>> get pasted => const Stream.empty();

  @override
  Future<List<XFile>> read() async {
    try {
      final result = await _channel.invokeMethod<List<Object?>>('readFiles');
      return xFilesFromClipboard([
        for (final item in result ?? const <Object?>[])
          if (item is Map && item['bytes'] is Uint8List)
            (
              name: (item['name'] as String?) ?? 'pasted-image.png',
              bytes: item['bytes'] as Uint8List,
            ),
      ]);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
