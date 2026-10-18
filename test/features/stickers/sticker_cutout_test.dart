import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/stickers/sticker_cutout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(stickerCutoutChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('the channel is the one the native plugins register', () {
    expect(stickerCutoutChannelName, 'wecord/sticker_cutout');
  });

  group('isAvailable', () {
    test('asks the plugin', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'isAvailable');
        return true;
      });
      expect(await const NativeStickerCutout().isAvailable(), isTrue);
    });

    test('an older OS answers false, and the option is hidden', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      expect(await const NativeStickerCutout().isAvailable(), isFalse);
    });

    test('no plugin at all is not available', () async {
      expect(await const NativeStickerCutout().isAvailable(), isFalse);
    });

    test('a plugin error is not available', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'failed');
      });
      expect(await const NativeStickerCutout().isAvailable(), isFalse);
    });

    test('the web and other platforms in tests have none', () async {
      expect(await const UnsupportedStickerCutout().isAvailable(), isFalse);
      await expectLater(
        const UnsupportedStickerCutout().cutOut(Uint8List(1)),
        throwsA(
          isA<StickerCutoutException>().having(
            (e) => e.failure,
            'failure',
            StickerCutoutFailure.unavailable,
          ),
        ),
      );
    });
  });

  group('cutOut', () {
    test('sends the picture and returns the PNG the plugin answers', () async {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      Object? arguments;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'cutOut');
        arguments = call.arguments;
        return {'bytes': png, 'width': 10, 'height': 12};
      });
      final input = Uint8List.fromList([1, 2, 3, 4]);
      final result = await const NativeStickerCutout().cutOut(input);
      expect(result, png);
      expect((arguments! as Map)['bytes'], input);
    });

    for (final (code, failure) in [
      ('unsupported', StickerCutoutFailure.unavailable),
      ('unreadable', StickerCutoutFailure.unreadable),
      ('noSubject', StickerCutoutFailure.noSubject),
      ('failed', StickerCutoutFailure.failed),
      ('something-else', StickerCutoutFailure.failed),
    ]) {
      test('the plugin error $code is $failure', () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: code);
        });
        await expectLater(
          const NativeStickerCutout().cutOut(Uint8List(2)),
          throwsA(
            isA<StickerCutoutException>().having(
              (e) => e.failure,
              'failure',
              failure,
            ),
          ),
        );
      });
    }

    test('a missing plugin is unavailable', () async {
      await expectLater(
        const NativeStickerCutout().cutOut(Uint8List(2)),
        throwsA(
          isA<StickerCutoutException>().having(
            (e) => e.failure,
            'failure',
            StickerCutoutFailure.unavailable,
          ),
        ),
      );
    });

    test('an empty answer is a failure', () {
      expect(
        () => stickerCutoutFromChannel({'bytes': Uint8List(0)}),
        throwsA(isA<StickerCutoutException>()),
      );
      expect(
        () => stickerCutoutFromChannel(null),
        throwsA(isA<StickerCutoutException>()),
      );
      expect(
        stickerCutoutFromChannel({
          'bytes': Uint8List.fromList([1]),
        }),
        Uint8List.fromList([1]),
      );
    });
  });

  test('error codes map to failures', () {
    expect(
      stickerCutoutFailureFromCode('noSubject'),
      StickerCutoutFailure.noSubject,
    );
    expect(
      stickerCutoutFailureFromCode('unsupported'),
      StickerCutoutFailure.unavailable,
    );
    expect(stickerCutoutFailureFromCode('x'), StickerCutoutFailure.failed);
  });
}
