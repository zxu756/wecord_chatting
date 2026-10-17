import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';
import 'package:wecord/features/transcribe/transcript_cache.dart';
import 'package:wecord/features/transcribe/voice_transcriber.dart';

import '../ai/ai_fakes.dart';
import 'transcribe_fakes.dart';

CachedTranscript _transcript(String text, [int day = 1]) => CachedTranscript(
  text: text,
  engine: TranscribeEngine.onDevice,
  savedAt: DateTime.utc(2026, 10, day),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('transcript cache', () {
    test('keeps a transcript across a restart, per message', () async {
      final first = SharedPreferencesTranscriptCache(userId: 'user-1');
      await first.write('m1', _transcript('Hello there'));
      await first.write('m2', _transcript('Second'));

      final restarted = SharedPreferencesTranscriptCache(userId: 'user-1');
      final read = await restarted.read('m1');
      expect(read?.text, 'Hello there');
      expect(read?.engine, TranscribeEngine.onDevice);
      expect(read?.savedAt, DateTime.utc(2026, 10));
      expect((await restarted.read('m2'))?.text, 'Second');
      expect(await restarted.read('m3'), isNull);
    });

    test('is private to the signed-in user', () async {
      await SharedPreferencesTranscriptCache(
        userId: 'user-1',
      ).write('m1', _transcript('Mine'));
      final other = SharedPreferencesTranscriptCache(userId: 'user-2');
      expect(await other.read('m1'), isNull);
    });

    test('keeps nothing without a signed-in user', () async {
      final cache = SharedPreferencesTranscriptCache();
      await cache.write('m1', _transcript('Gone'));
      expect((await cache.read('m1'))?.text, 'Gone');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('keeps the newest entries when it grows past the limit', () async {
      final cache = SharedPreferencesTranscriptCache(
        userId: 'user-1',
        maxEntries: 2,
      );
      await cache.write('old', _transcript('old', 1));
      await cache.write('mid', _transcript('mid', 2));
      await cache.write('new', _transcript('new', 3));
      final restarted = SharedPreferencesTranscriptCache(userId: 'user-1');
      expect(await restarted.read('old'), isNull);
      expect((await restarted.read('mid'))?.text, 'mid');
      expect((await restarted.read('new'))?.text, 'new');
    });

    test('forgets one transcript', () async {
      final cache = SharedPreferencesTranscriptCache(userId: 'user-1');
      await cache.write('m1', _transcript('a'));
      await cache.remove('m1');
      expect(
        await SharedPreferencesTranscriptCache(userId: 'user-1').read('m1'),
        isNull,
      );
    });

    test('a damaged entry is ignored', () async {
      SharedPreferences.setMockInitialValues({
        'wecord.transcripts.user-1': 'not json',
      });
      final cache = SharedPreferencesTranscriptCache(userId: 'user-1');
      expect(await cache.read('m1'), isNull);
      await cache.write('m1', _transcript('fine'));
      expect((await cache.read('m1'))?.text, 'fine');
    });
  });

  group('on-device transcriber', () {
    late List<MethodCall> calls;
    late Object? Function(MethodCall call) answer;

    NativeVoiceTranscriber transcriber() {
      const channel = MethodChannel('wecord/transcribe-test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return answer(call);
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      return NativeVoiceTranscriber(
        fetchAudio: (request) async => '/tmp/${voiceFileName(request)}',
        channel: channel,
      );
    }

    setUp(() => calls = []);

    test('plans on-device when the language supports it', () async {
      answer = (_) => {
        'supported': true,
        'available': true,
        'onDevice': true,
        'locale': 'en-US',
        'authorization': 'notDetermined',
      };
      final plan = await transcriber().plan(testRequest());
      expect(plan.engine, TranscribeEngine.onDevice);
      expect(plan.canAutoStart, isTrue);
      expect(calls.single.arguments, {
        'locales': ['en-US'],
      });
    });

    test('does not start on its own once speech recognition is denied', () {
      answer = (_) => {
        'supported': true,
        'onDevice': true,
        'authorization': 'denied',
      };
      expect(
        transcriber().plan(testRequest()).then((plan) => plan.canAutoStart),
        completion(isFalse),
      );
    });

    test(
      'plans Apple\'s service when the device can not do the language',
      () async {
        answer = (_) => {
          'supported': true,
          'onDevice': false,
          'authorization': 'authorized',
        };
        final plan = await transcriber().plan(testRequest());
        expect(plan.engine, TranscribeEngine.appleServer);
        expect(plan.canAutoStart, isFalse);
      },
    );

    test('plans nothing for a language without a recognizer', () async {
      answer = (_) => {'supported': false};
      final plan = await transcriber().plan(testRequest());
      expect(plan.engine, isNull);
      expect(plan.unavailable, TranscribeUnavailable.language);
    });

    test('transcribes the downloaded file, on the device by default', () async {
      answer = (_) => {'text': ' Hello ', 'onDevice': true, 'locale': 'en-US'};
      final result = await transcriber().transcribe(testRequest());
      expect(result.text, 'Hello');
      expect(result.engine, TranscribeEngine.onDevice);
      expect(calls.single.method, 'transcribe');
      expect(calls.single.arguments, {
        'path': '/tmp/voice-message-1.wav',
        'locales': ['en-US'],
        'allowServer': false,
      });
    });

    test('says when the answer came from Apple\'s servers', () async {
      answer = (_) => {'text': 'Hi', 'onDevice': false};
      final result = await transcriber().transcribe(
        testRequest(),
        allowServerRecognition: true,
      );
      expect(result.engine, TranscribeEngine.appleServer);
      expect(calls.single.arguments, containsPair('allowServer', true));
    });

    test('maps the plugin\'s errors', () async {
      final expected = {
        'not_authorized': TranscribeFailureKind.notAuthorized,
        'no_speech': TranscribeFailureKind.noSpeech,
        'unreadable': TranscribeFailureKind.unreadable,
        'unavailable': TranscribeFailureKind.unavailable,
        'needs_server': TranscribeFailureKind.needsServer,
        'failed': TranscribeFailureKind.failed,
        'something_else': TranscribeFailureKind.failed,
      };
      for (final MapEntry(:key, :value) in expected.entries) {
        answer = (_) => throw PlatformException(code: key);
        await expectLater(
          transcriber().transcribe(testRequest()),
          throwsA(
            isA<TranscribeException>().having((e) => e.kind, 'kind', value),
          ),
          reason: key,
        );
      }
    });

    test('empty text means no speech', () async {
      answer = (_) => {'text': '  ', 'onDevice': true};
      await expectLater(
        transcriber().transcribe(testRequest()),
        throwsA(
          isA<TranscribeException>().having(
            (e) => e.kind,
            'kind',
            TranscribeFailureKind.noSpeech,
          ),
        ),
      );
    });

    test('names the downloaded file by its format', () {
      TranscribeRequest withMime(String mime, [String path = 'c/a.bin']) =>
          TranscribeRequest(
            messageId: 'm',
            attachment: voiceWith(mime, path),
            locales: const ['en-US'],
          );
      expect(voiceFileName(withMime('audio/wav')), 'voice-m.wav');
      expect(voiceFileName(withMime('audio/mp4')), 'voice-m.m4a');
      expect(voiceFileName(withMime('audio/mpeg')), 'voice-m.mp3');
      expect(voiceFileName(withMime('x/y', 'c/a.ogg')), 'voice-m.ogg');
    });
  });

  group('server transcriber', () {
    test('plans the server only when it has a speech provider', () async {
      final ai = FakeAiRepository();
      final transcriber = ServerVoiceTranscriber(ai);
      ai.statusValue = const AiStatus(dailyLimit: 50, used: 0);
      expect(
        (await transcriber.plan(testRequest())).unavailable,
        TranscribeUnavailable.platform,
      );
      ai.statusValue = const AiStatus(
        dailyLimit: 50,
        used: 0,
        transcribeConfigured: true,
      );
      final plan = await transcriber.plan(testRequest());
      expect(plan.engine, TranscribeEngine.aiServer);
      expect(plan.canAutoStart, isFalse);
      ai.statusError = const AiNotConfiguredException();
      expect(
        (await transcriber.plan(testRequest())).unavailable,
        TranscribeUnavailable.platform,
      );
    });

    test('never runs on the device, so never on its own', () {
      expect(ServerVoiceTranscriber(FakeAiRepository()).runsOnDevice, isFalse);
    });

    test('asks the server for the message and returns its text', () async {
      final ai = FakeAiRepository()..transcribed = 'From the server';
      final result = await ServerVoiceTranscriber(
        ai,
      ).transcribe(testRequest('m-9'));
      expect(result.text, 'From the server');
      expect(result.engine, TranscribeEngine.aiServer);
      expect(ai.transcribeCalls, ['m-9']);
    });

    test('empty text means no speech; server errors pass through', () async {
      final ai = FakeAiRepository()..transcribed = '';
      await expectLater(
        ServerVoiceTranscriber(ai).transcribe(testRequest()),
        throwsA(isA<TranscribeException>()),
      );
      ai.error = const AiLimitReachedException(limit: 50, used: 50);
      await expectLater(
        ServerVoiceTranscriber(ai).transcribe(testRequest()),
        throwsA(isA<AiLimitReachedException>()),
      );
    });

    test('the answer of the ai function becomes an exception', () {
      expect(
        aiExceptionFor(503, {'error': 'transcribe_not_configured'}),
        isA<AiTranscribeNotConfiguredException>(),
      );
      expect(
        aiExceptionFor(413, {'error': 'audio_too_long'}),
        isA<AiRejectedException>(),
      );
    });
  });

  test('the speech locale follows the app language', () {
    expect(speechLocales(), ['en-US']);
  });
}
