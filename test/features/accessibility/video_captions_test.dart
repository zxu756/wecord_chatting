import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/file_preview/viewers/video_preview.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_models.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_service.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../file_preview/file_preview_fakes.dart';

/// A player that plays nothing; the test moves its clock.
class _FakeVideoController extends VideoPlayerController {
  _FakeVideoController() : super.networkUrl(Uri.parse('fake://video'));

  @override
  Future<void> initialize() async {
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(seconds: 60),
      size: const Size(360, 640),
    );
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> play() async {
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }

  // The real dispose would talk to a platform player that is not there.
  @override
  // ignore: must_call_super
  Future<void> dispose() async {}
}

SpokenSegment _word(String text, double at, [double length = 0.3]) {
  return SpokenSegment(
    start: Duration(milliseconds: (at * 1000).round()),
    duration: Duration(milliseconds: (length * 1000).round()),
    text: text,
  );
}

PreviewFile _video() => const PreviewFile(
  bucket: 'chat-files',
  path: 'conversation-1/clip.mp4',
  name: 'clip.mp4',
  mimeType: 'video/mp4',
  size: 2048,
  messageId: 'message-1',
  conversationId: 'conversation-1',
);

/// Makes the captions it was given, when asked.
class _FakeMaker implements VideoCaptionMaker {
  _FakeMaker({this.captions});

  VideoCaptions? captions;
  VideoCaptionFailure? failure;
  Completer<void>? gate;
  var made = 0;

  @override
  bool get available => true;

  @override
  Future<VideoCaptions> make(
    PreviewFile file, {
    required Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async {
    made++;
    onProgress?.call(1, 2);
    if (gate case final gate?) {
      await gate.future;
    }
    if (failure case final failure?) {
      throw VideoCaptionException(failure);
    }
    return captions!;
  }
}

VideoCaptions _hello() => VideoCaptions(
  cues: const [
    CaptionCue(
      start: Duration.zero,
      end: Duration(seconds: 30),
      text: 'Hello, can you hear me?',
    ),
  ],
  savedAt: DateTime.utc(2026, 10, 20),
);

void main() {
  group('lines of captions', () {
    test('words are grouped at pauses and when a line gets long', () {
      final cues = cuesFromSegments([
        _word('Good', 0),
        _word('morning', 0.4),
        _word('everyone.', 0.8),
        // A pause, then a new thought.
        _word('Today', 3),
        _word('we', 3.4),
        _word('look', 3.6),
        _word('at', 3.9),
        _word('the', 4.1),
        _word('numbers', 4.3),
        _word('for', 4.7),
        _word('the', 4.9),
        _word('whole', 5.1),
        _word('quarter', 5.4),
        _word('together', 5.8),
      ]);
      expect(cues.first.text, 'Good morning everyone.');
      expect(cues.first.start, Duration.zero);
      // Held a moment after the last word.
      expect(cues.first.end, const Duration(milliseconds: 1600));
      // The rest is one or two lines, never over the limit.
      expect(cues.length, greaterThanOrEqualTo(2));
      for (final cue in cues) {
        expect(cue.text.length, lessThanOrEqualTo(captionLineUnits));
      }
      expect(cues.skip(1).map((c) => c.text).join(' '), contains('Today we'));
    });

    test('Chinese words join without spaces and lines are half as long', () {
      final cues = cuesFromSegments([
        _word('大家', 0),
        _word('早上好', 0.4),
        _word('今天', 1.0),
        _word('我们', 1.3),
        _word('来看看', 1.6),
        _word('这个季度', 2.0),
        _word('的', 2.4),
        _word('数字', 2.5),
        _word('还有', 2.9),
        _word('下个季度', 3.2),
        _word('的计划', 3.6),
      ]);
      expect(cues.first.text.contains(' '), isFalse);
      expect(cues.length, greaterThan(1));
      expect(cues.map((c) => c.text).join(), contains('大家早上好'));
    });

    test('a line never runs into the next one', () {
      final cues = cuesFromSegments([
        _word('First.', 0, 0.5),
        _word('Second', 0.9, 0.5),
        _word('line', 1.4, 0.3),
      ]);
      for (var i = 0; i + 1 < cues.length; i++) {
        expect(cues[i].end <= cues[i + 1].start, isTrue);
      }
    });

    test('nothing heard gives no lines', () {
      expect(cuesFromSegments(const []), isEmpty);
      expect(cuesFromSegments([_word('  ', 0)]), isEmpty);
    });

    test('the line to show is found by the time', () {
      final captions = VideoCaptions(
        cues: const [
          CaptionCue(
            start: Duration(seconds: 1),
            end: Duration(seconds: 3),
            text: 'one',
          ),
          CaptionCue(
            start: Duration(seconds: 4),
            end: Duration(seconds: 6),
            text: 'two',
          ),
        ],
        savedAt: DateTime.utc(2026),
      );
      expect(captions.at(Duration.zero), isNull);
      expect(captions.at(const Duration(seconds: 2))!.text, 'one');
      expect(captions.at(const Duration(seconds: 3)), isNull);
      expect(captions.at(const Duration(milliseconds: 4500))!.text, 'two');
      expect(captions.at(const Duration(seconds: 9)), isNull);
    });

    test('captions survive being kept and read back', () {
      final captions = _hello();
      final back = VideoCaptions.fromJson(captions.toJson())!;
      expect(back.cues.single.text, 'Hello, can you hear me?');
      expect(back.cues.single.end, const Duration(seconds: 30));
      expect(VideoCaptions.fromJson('nonsense'), isNull);
      expect(VideoCaptions.fromJson({'c': 'x'}), isNull);
    });
  });

  group('the system recognizer', () {
    const channel = MethodChannel('wecord/transcribe');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void answer(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
            calls.add(call);
            return handler(call);
          });
    }

    NativeVideoCaptionMaker maker() => NativeVideoCaptionMaker(
      fetcher: FakeFileFetcher(contents: {'conversation-1/clip.mp4': ''}),
      clock: () => DateTime.utc(2026, 10, 20),
    );

    Future<VideoCaptions> make() => maker().make(
      _video(),
      url: () async => Uri.parse('https://files.test/clip.mp4'),
    );

    test('asks for a video, with times, on the device only', () async {
      answer(
        (call) async => {
          'text': 'Hello there',
          'onDevice': true,
          'locale': 'en-US',
          'segments': [
            {'t': 0.2, 'd': 0.4, 's': 'Hello'},
            {'t': 0.7, 'd': 0.4, 's': 'there'},
          ],
        },
      );
      final captions = await make();

      final arguments = calls.single.arguments as Map;
      expect(calls.single.method, 'transcribe');
      expect(arguments['path'], '/cache/clip.mp4');
      expect(arguments['video'], isTrue);
      expect(arguments['segments'], isTrue);
      // The sound is never sent to a server for captions.
      expect(arguments['allowServer'], isFalse);
      expect(captions.cues.single.text, 'Hello there');
      expect(captions.cues.single.start, const Duration(milliseconds: 200));
      expect(captions.locale, 'en-US');
    });

    test('says why it could not', () async {
      Future<VideoCaptionFailure> failureOf(String code) async {
        answer((call) async => throw PlatformException(code: code));
        try {
          await make();
        } on VideoCaptionException catch (error) {
          return error.kind;
        }
        fail('should have failed');
      }

      expect(await failureOf('no_speech'), VideoCaptionFailure.noSpeech);
      expect(
        await failureOf('not_authorized'),
        VideoCaptionFailure.notAuthorized,
      );
      expect(await failureOf('needs_server'), VideoCaptionFailure.language);
      expect(await failureOf('unreadable'), VideoCaptionFailure.unreadable);
      expect(await failureOf('boom'), VideoCaptionFailure.failed);
    });

    test('an answer without words is no speech', () async {
      answer((call) async => {'text': 'hm', 'onDevice': true, 'segments': []});
      await expectLater(
        make(),
        throwsA(
          isA<VideoCaptionException>().having(
            (e) => e.kind,
            'kind',
            VideoCaptionFailure.noSpeech,
          ),
        ),
      );
    });
  });

  group('in the video viewer', () {
    late _FakeMaker maker;
    late InMemoryVideoCaptionCache cache;
    late InMemoryVideoCaptionsPreferenceStore preference;

    List<Override> overrides() => [
      ...filePreviewOverrides(),
      videoControllerFactoryProvider.overrideWithValue(
        ({url, localPath}) => _FakeVideoController(),
      ),
      videoCaptionMakerProvider.overrideWithValue(maker),
      videoCaptionCacheProvider.overrideWithValue(cache),
      videoCaptionsPreferenceStoreProvider.overrideWithValue(preference),
    ];

    /// Taps [key]. The viewer's double-tap (full screen) makes the press wait
    /// out the double-tap time first.
    Future<void> press(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => unawaited(
                    openFilePreview(context, file: _video(), gallery: const []),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    setUp(() {
      maker = _FakeMaker(captions: _hello());
      cache = InMemoryVideoCaptionCache();
      preference = InMemoryVideoCaptionsPreferenceStore();
    });

    testWidgets('a button turns captions on, makes them and keeps them', (
      tester,
    ) async {
      await open(tester);
      expect(find.byKey(const ValueKey('video-captions')), findsOneWidget);
      expect(find.byKey(const ValueKey('video-caption-line')), findsNothing);

      await press(tester, 'video-captions');
      expect(maker.made, 1);
      expect(find.text('Hello, can you hear me?'), findsOneWidget);
      expect(preference.on, isTrue);
      expect((await cache.read(_video().key))!.cues, hasLength(1));

      // Off again: the line goes, the choice is remembered.
      await press(tester, 'video-captions');
      expect(find.byKey(const ValueKey('video-caption-line')), findsNothing);
      expect(preference.on, isFalse);
    });

    testWidgets('while they are made the viewer says so', (tester) async {
      maker.gate = Completer<void>();
      await open(tester);
      await press(tester, 'video-captions');

      expect(
        find.byKey(const ValueKey('video-captions-working')),
        findsOneWidget,
      );
      expect(find.text('Making captions on this device…'), findsWidgets);

      maker.gate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Hello, can you hear me?'), findsOneWidget);
    });

    testWidgets('captions kept from before show at once', (tester) async {
      await cache.write(_video().key, _hello());
      preference.on = true;
      await open(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Hello, can you hear me?'), findsOneWidget);
      // Nothing was made again.
      expect(maker.made, 0);
    });

    testWidgets('a failure is explained, not left silent', (tester) async {
      maker.failure = VideoCaptionFailure.noSpeech;
      await open(tester);
      await press(tester, 'video-captions');

      expect(find.text('There is no speech in this video.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('video-caption-failed')),
        findsOneWidget,
      );
    });

    testWidgets('there is no button where captions cannot be made', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...filePreviewOverrides(),
            videoControllerFactoryProvider.overrideWithValue(
              ({url, localPath}) => _FakeVideoController(),
            ),
            videoCaptionMakerProvider.overrideWithValue(
              const UnsupportedVideoCaptionMaker(),
            ),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => unawaited(
                    openFilePreview(context, file: _video(), gallery: const []),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('video-captions')), findsNothing);
    });
  });
}
