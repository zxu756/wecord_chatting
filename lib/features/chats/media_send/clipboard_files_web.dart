import 'dart:async';
import 'dart:js_interop';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:web/web.dart' as web;
import 'package:wecord/features/chats/media_send/media_picker.dart';

ClipboardFiles createClipboardFiles() => WebClipboardFiles();

/// Listens to the browser's paste event (capturing, before the text field
/// sees it) and hands over the files and pictures in it. A paste of text
/// goes on to the text field as usual.
class WebClipboardFiles implements ClipboardFiles {
  final _controller = StreamController<List<XFile>>.broadcast();
  late final JSFunction _listener = _onPaste.toJS;
  var _listening = false;

  @override
  bool get isSupported => true;

  @override
  Future<List<XFile>> read() async => const [];

  @override
  Stream<List<XFile>> get pasted {
    if (!_listening) {
      _listening = true;
      web.document.addEventListener(
        'paste',
        _listener,
        web.AddEventListenerOptions(capture: true),
      );
    }
    return _controller.stream;
  }

  void _onPaste(web.ClipboardEvent event) {
    final list = event.clipboardData?.files;
    if (list == null || list.length == 0 || !_controller.hasListener) {
      return;
    }
    final files = <XFile>[];
    for (var i = 0; i < list.length; i++) {
      final file = list.item(i);
      if (file == null) {
        continue;
      }
      files.add(
        XFile(
          web.URL.createObjectURL(file),
          name: file.name.isEmpty ? 'pasted-image.png' : file.name,
          mimeType: file.type.isEmpty ? null : file.type,
          length: file.size,
        ),
      );
    }
    if (files.isNotEmpty) {
      event.preventDefault();
      _controller.add(files);
    }
  }
}
