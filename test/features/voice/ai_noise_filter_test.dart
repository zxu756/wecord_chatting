import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:wecord/features/voice/ai_noise_filter.dart';
import 'package:wecord/features/voice/livekit_voice_call.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/features/voice/voice_settings_screen.dart';

import 'voice_fakes.dart';

class _FakeTrack implements rtc.MediaStreamTrack {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A filter whose calls are recorded and which can be made to throw.
class _FakeProcessor implements lk.TrackProcessor<lk.AudioProcessorOptions> {
  final calls = <String>[];
  final bypasses = <bool>[];
  Object? initError;
  Object? bypassError;
  rtc.MediaStreamTrack? processed;

  @override
  String get name => 'fake';

  @override
  Future<void> init(lk.AudioProcessorOptions options) async {
    calls.add('init');
    if (initError case final error?) {
      throw error;
    }
  }

  @override
  Future<void> restart(lk.AudioProcessorOptions options) async {
    calls.add('restart');
  }

  @override
  Future<void> destroy() async => calls.add('destroy');

  @override
  Future<void> onPublish(lk.Room room) async => calls.add('onPublish');

  @override
  Future<void> onUnpublish() async => calls.add('onUnpublish');

  @override
  rtc.MediaStreamTrack? get processedTrack => processed;

  Future<void> setBypass(bool bypass) async {
    if (bypassError case final error?) {
      throw error;
    }
    bypasses.add(bypass);
  }
}

lk.AudioProcessorOptions _options() =>
    lk.AudioProcessorOptions(track: _FakeTrack());

Future<AiNoiseFilter> _open(
  _FakeProcessor processor, {
  bool needsProcessedTrack = false,
}) async {
  final filter = await AiNoiseFilter.open(
    (url, token) async =>
        AiNoiseBackend(processor: processor, setBypass: processor.setBypass),
    url: 'wss://example.livekit.cloud',
    token: 'token',
    needsProcessedTrack: needsProcessedTrack,
  );
  return filter!;
}

void main() {
  group('microphone options', () {
    const noise = VoiceAudioProcessing();

    test('attach the filter and leave WebRTC noise suppression off', () async {
      final filter = await _open(_FakeProcessor());
      final options = liveKitCaptureOptions(
        const lk.AudioCaptureOptions(),
        noise,
        filter: filter,
        web: false,
      );
      expect(options.processor, same(filter));
      expect(options.noiseSuppression, isFalse);
      expect(options.voiceIsolation, isTrue);
      expect(options.echoCancellation, isTrue);
      expect(options.autoGainControl, isTrue);
    });

    test('keep the browser noise suppression until the filter runs', () async {
      final filter = await _open(_FakeProcessor());
      final options = liveKitCaptureOptions(
        const lk.AudioCaptureOptions(),
        noise,
        filter: filter,
        web: true,
      );
      expect(options.processor, same(filter));
      expect(options.noiseSuppression, isTrue);
    });

    test('use the standard noise suppression without a filter', () {
      final options = liveKitCaptureOptions(
        const lk.AudioCaptureOptions(),
        noise,
        web: false,
      );
      expect(options.processor, isNull);
      expect(options.noiseSuppression, isTrue);
      final off = liveKitCaptureOptions(
        const lk.AudioCaptureOptions(),
        const VoiceAudioProcessing(noiseSuppression: false),
        web: false,
      );
      expect(off.noiseSuppression, isFalse);
      expect(off.voiceIsolation, isFalse);
    });

    test('go back to the standard noise suppression once it fails', () async {
      final processor = _FakeProcessor()..initError = StateError('no');
      final filter = await _open(processor);
      await filter.init(_options());
      final options = liveKitCaptureOptions(
        const lk.AudioCaptureOptions(),
        noise,
        filter: filter,
        web: false,
      );
      expect(options.noiseSuppression, isTrue);
    });
  });

  group('AiNoiseFilter', () {
    test('is not used when it cannot be created', () async {
      final filter = await AiNoiseFilter.open(
        (url, token) async =>
            throw const AiNoiseUnavailable('not on this plan'),
        url: 'wss://example.livekit.cloud',
        token: 'token',
      );
      expect(filter, isNull);
    });

    test('the Noise suppression setting bypasses it', () async {
      final processor = _FakeProcessor();
      final filter = await _open(processor);
      await filter.setEnabled(false);
      await filter.setEnabled(true);
      expect(processor.bypasses, [true, false]);
      expect(filter.working, isTrue);
    });

    test('stops working quietly when it throws', () async {
      final processor = _FakeProcessor()..initError = StateError('boom');
      final filter = await _open(processor);
      var notified = 0;
      filter.addListener(() => notified++);
      await filter.init(_options());
      expect(filter.working, isFalse);
      expect(notified, 1);
      // From now on it does nothing and does not throw.
      await filter.restart(_options());
      await filter.setEnabled(false);
      expect(processor.calls, ['init']);
      expect(processor.bypasses, isEmpty);
      expect(filter.processedTrack, isNull);
      await filter.destroy();
      expect(processor.calls, ['init', 'destroy']);
    });

    test('stops working when switching it fails', () async {
      final processor = _FakeProcessor()..bypassError = StateError('boom');
      final filter = await _open(processor);
      await filter.setEnabled(false);
      expect(filter.working, isFalse);
    });

    test('a browser filter that did not start counts as failed', () async {
      final processor = _FakeProcessor();
      final filter = await _open(processor, needsProcessedTrack: true);
      await filter.init(_options());
      expect(filter.working, isFalse);

      final running = _FakeProcessor()..processed = _FakeTrack();
      final started = await _open(running, needsProcessedTrack: true);
      await started.init(_options());
      expect(started.working, isTrue);
      expect(started.processedTrack, same(running.processed));
    });

    test('is switched on again when the microphone restarts', () async {
      final processor = _FakeProcessor();
      final filter = await _open(processor);
      final room = lk.Room();
      await filter.setEnabled(false);
      await filter.init(_options());
      // Never published: nothing to tell the filter yet.
      expect(processor.calls, ['init']);
      await filter.onPublish(room);
      expect(processor.calls, ['init', 'onPublish']);
      expect(processor.bypasses.last, isTrue);
      await filter.destroy();
      await filter.init(_options());
      expect(processor.calls, [
        'init',
        'onPublish',
        'destroy',
        'init',
        'onPublish',
      ]);
      expect(processor.bypasses.last, isTrue);
      await room.dispose();
    });
  });

  group('LiveKitVoiceCallConnector', () {
    test('asks for the filter with the room it joins', () async {
      final asked = <String>[];
      final connector = LiveKitVoiceCallConnector(
        noiseBackend: (url, token) async {
          asked.add('$url $token');
          return AiNoiseBackend(
            processor: _FakeProcessor(),
            setBypass: (_) async {},
          );
        },
      );
      await expectLater(
        connector.connect(
          url: 'ws://127.0.0.1:1',
          token: 'abc',
          microphoneEnabled: false,
        ),
        throwsA(anything),
      );
      expect(asked, ['ws://127.0.0.1:1 abc']);
    });

    test('still joins when the filter cannot be created', () async {
      final connector = LiveKitVoiceCallConnector(
        noiseBackend: (url, token) async => throw StateError('no filter'),
      );
      // Fails only because nothing listens there, not because of the
      // filter.
      await expectLater(
        connector.connect(
          url: 'ws://127.0.0.1:1',
          token: 'abc',
          microphoneEnabled: false,
        ),
        throwsA(isNot(isA<StateError>())),
      );
    });
  });

  group('Settings → Voice note', () {
    Future<void> open(
      WidgetTester tester, {
      required FakeVoiceCallConnector connector,
      bool noiseSuppression = true,
    }) async {
      final store = InMemoryVoiceSettingsStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceCallConnectorProvider.overrideWithValue(connector),
            voiceSettingsStoreProvider.overrideWithValue(store),
          ],
          child: const MaterialApp(home: VoiceSettingsScreen()),
        ),
      );
      await tester.pump();
      if (!noiseSuppression) {
        await tester.tap(find.byKey(const ValueKey('voice-noise-suppression')));
      }
      await tester.pumpAndSettle();
    }

    testWidgets('says AI noise suppression is active', (tester) async {
      await open(tester, connector: FakeVoiceCallConnector()..aiNoise = true);
      expect(find.textContaining('AI noise suppression active'), findsOne);
    });

    testWidgets('says the standard one is used where AI is not available', (
      tester,
    ) async {
      await open(tester, connector: FakeVoiceCallConnector());
      expect(
        find.textContaining(
          'Standard noise suppression (AI not available on this device)',
        ),
        findsOne,
      );
    });

    testWidgets('says nothing with noise suppression off', (tester) async {
      await open(
        tester,
        connector: FakeVoiceCallConnector()..aiNoise = true,
        noiseSuppression: false,
      );
      expect(find.textContaining('AI noise suppression'), findsNothing);
      expect(find.text('Filters out background noise.'), findsOne);
    });
  });
}
