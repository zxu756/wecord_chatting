import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/media_send/chat_drop_zone.dart';
import 'package:wecord/features/chats/media_send/clipboard_files_io.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MacosClipboardFiles', () {
    const channel = MethodChannel('wecord/clipboard');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void answer(Object? Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => handler(call));
    }

    test('turns what the pasteboard holds into files', () async {
      answer((call) {
        expect(call.method, 'readFiles');
        return [
          {
            'name': 'Screenshot.png',
            'bytes': Uint8List.fromList([1, 2, 3]),
          },
          {
            'name': 'notes.txt',
            'bytes': Uint8List.fromList([4]),
          },
          {'name': 'broken'},
        ];
      });

      final files = await const MacosClipboardFiles().read();

      expect(files.map((file) => file.name), ['Screenshot.png', 'notes.txt']);
      expect(await files.first.readAsBytes(), [1, 2, 3]);
      expect(await files.first.length(), 3);
    });

    test('text on the pasteboard is nothing to attach', () async {
      answer((call) => <Object?>[]);
      expect(await const MacosClipboardFiles().read(), isEmpty);
    });

    test('a pasteboard that cannot be read is empty, not an error', () async {
      answer((call) => throw PlatformException(code: 'x'));
      expect(await const MacosClipboardFiles().read(), isEmpty);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(await const MacosClipboardFiles().read(), isEmpty);
    });
  });

  test('other platforms have no clipboard files', () async {
    const none = NoClipboardFiles();
    expect(none.isSupported, isFalse);
    expect(await none.read(), isEmpty);
    expect(await none.pasted.isEmpty, isTrue);
    expect(createClipboardFiles().isSupported, isFalse);
  });

  test('drag and drop is for the desktop and the web only', () {
    // The tests run as Android.
    expect(dropIsSupported, isFalse);
  });
}
