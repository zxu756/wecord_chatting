import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/image_text/image_text_models.dart';
import 'package:wecord/features/image_text/image_text_recognizer.dart';

const _channel = MethodChannel(imageTextChannelName);

void _answer(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  group('channel mapping', () {
    test('lines come back in order, trimmed', () {
      final text = imageTextFromChannel({
        'lines': [
          {'text': '  Opening hours ', 'confidence': 1.0},
          {'text': 'Mon–Fri 9:00–18:00', 'confidence': 0.5},
          {'text': '周末休息', 'confidence': 1},
        ],
      });
      expect(text.lines, ['Opening hours', 'Mon–Fri 9:00–18:00', '周末休息']);
      expect(text.text, 'Opening hours\nMon–Fri 9:00–18:00\n周末休息');
      expect(text.isEmpty, isFalse);
    });

    test('empty lines and lines the recognizer barely believes are left out', () {
      final text = imageTextFromChannel({
        'lines': [
          {'text': '   ', 'confidence': 1.0},
          {'text': 'noise', 'confidence': 0.05},
          {'text': 'Sale', 'confidence': 0.9},
          {'text': '', 'confidence': 1.0},
        ],
      });
      expect(text.lines, ['Sale']);
    });

    test('plain strings and missing confidence are accepted', () {
      expect(
        imageTextFromChannel({
          'lines': [
            'First',
            {'text': 'Second'},
          ],
        }).lines,
        ['First', 'Second'],
      );
    });

    test('nothing sensible gives an empty text', () {
      expect(imageTextFromChannel(null).isEmpty, isTrue);
      expect(imageTextFromChannel({}).isEmpty, isTrue);
      expect(imageTextFromChannel({'lines': 'oops'}).isEmpty, isTrue);
      expect(
        imageTextFromChannel({
          'lines': [1, null, <String, Object?>{}],
        }).isEmpty,
        isTrue,
      );
    });
  });

  group('the native recognizer', () {
    test('asks Vision for Chinese and English and reads the answer', () async {
      MethodCall? seen;
      _answer((call) async {
        seen = call;
        return {
          'lines': [
            {'text': 'Hello 你好', 'confidence': 0.9},
          ],
          'languages': ['zh-Hans', 'zh-Hant', 'en-US'],
        };
      });
      final text = await const NativeImageTextRecognizer().recognize(
        '/cache/a.jpg',
      );
      expect(text.text, 'Hello 你好');
      expect(seen!.method, 'recognize');
      expect(seen!.arguments, {
        'path': '/cache/a.jpg',
        'languages': ['zh-Hans', 'zh-Hant', 'en-US'],
      });
      expect(imageTextLanguages, ['zh-Hans', 'zh-Hant', 'en-US']);
    });

    test('a picture with no lines holds no text', () async {
      _answer((call) async => {'lines': <Object?>[], 'languages': <String>[]});
      await expectLater(
        const NativeImageTextRecognizer().recognize('/a.jpg'),
        throwsA(
          isA<ImageTextException>().having(
            (e) => e.kind,
            'kind',
            ImageTextFailure.noText,
          ),
        ),
      );
    });

    test('a null answer holds no text', () async {
      _answer((call) async => null);
      await expectLater(
        const NativeImageTextRecognizer().recognize('/a.jpg'),
        throwsA(isA<ImageTextException>()),
      );
    });

    for (final (code, kind) in [
      ('unreadable', ImageTextFailure.unreadable),
      ('unsupported', ImageTextFailure.unavailable),
      ('failed', ImageTextFailure.failed),
      ('something_else', ImageTextFailure.failed),
    ]) {
      test('the error "$code" is $kind', () async {
        _answer((call) async => throw PlatformException(code: code));
        await expectLater(
          const NativeImageTextRecognizer().recognize('/a.jpg'),
          throwsA(
            isA<ImageTextException>().having((e) => e.kind, 'kind', kind),
          ),
        );
      });
    }

    test('without the native plugin it is unavailable', () async {
      // No handler: the channel answers "missing plugin".
      await expectLater(
        const NativeImageTextRecognizer().recognize('/a.jpg'),
        throwsA(
          isA<ImageTextException>().having(
            (e) => e.kind,
            'kind',
            ImageTextFailure.unavailable,
          ),
        ),
      );
    });
  });

  group('where there is no recognizer', () {
    test('the web and others never read anything', () async {
      const recognizer = UnsupportedImageTextRecognizer();
      expect(recognizer.isSupported, isFalse);
      await expectLater(
        recognizer.recognize('/a.jpg'),
        throwsA(
          isA<ImageTextException>().having(
            (e) => e.kind,
            'kind',
            ImageTextFailure.unavailable,
          ),
        ),
      );
    });
  });
}
