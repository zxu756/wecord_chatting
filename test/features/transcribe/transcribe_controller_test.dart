import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/transcribe/transcribe_controller.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';
import 'package:wecord/features/transcribe/transcript_cache.dart';

import '../ai/ai_fakes.dart';
import 'transcribe_fakes.dart';

void main() {
  late FakeVoiceTranscriber transcriber;
  late InMemoryTranscriptCache cache;
  late InMemoryAutoTranscribeStore autoStore;
  late ProviderContainer container;

  ProviderContainer makeContainer() {
    final created = ProviderContainer(
      overrides: [
        ...transcribeOverrides(
          transcriber,
          cache: cache,
          autoStore: autoStore,
          ai: FakeAiRepository(),
        ),
        aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
      ],
    );
    addTearDown(created.dispose);
    return created;
  }

  setUp(() {
    transcriber = FakeVoiceTranscriber();
    cache = InMemoryTranscriptCache();
    autoStore = InMemoryAutoTranscribeStore();
    container = makeContainer();
  });

  TranscriptState? stateOf([String id = 'message-1']) =>
      container.read(transcriptsProvider)[id];

  TranscriptController controller() =>
      container.read(transcriptsProvider.notifier);

  test('show runs the transcriber, shows the text and saves it', () async {
    transcriber.gate = Completer<void>();
    final future = controller().show(testRequest());
    await pumpEventQueue();
    expect(stateOf()?.phase, TranscriptPhase.loading);

    transcriber.gate!.complete();
    await future;
    expect(stateOf()?.phase, TranscriptPhase.done);
    expect(stateOf()?.text, 'Lunch at noon?');
    expect(stateOf()?.engine, TranscribeEngine.onDevice);
    expect(cache.entries['message-1']?.text, 'Lunch at noon?');
    expect(transcriber.transcribeCalls.single.allowServer, isFalse);
  });

  test('a saved transcript shows again without transcribing', () async {
    await controller().show(testRequest());
    controller().hide('message-1');
    expect(stateOf(), isNull);
    expect(controller().isShown('message-1'), isFalse);

    await controller().show(testRequest());
    expect(stateOf()?.text, 'Lunch at noon?');
    expect(transcriber.transcribeCalls, hasLength(1));
    expect(transcriber.planCalls, hasLength(1));
  });

  test('a transcript made earlier is found in the saved ones', () async {
    cache.entries['message-1'] = CachedTranscript(
      text: 'From last week',
      engine: TranscribeEngine.appleServer,
      savedAt: DateTime.utc(2026, 10, 10),
    );
    await controller().show(testRequest());
    expect(stateOf()?.text, 'From last week');
    expect(stateOf()?.engine, TranscribeEngine.appleServer);
    expect(transcriber.planCalls, isEmpty);
  });

  test('a failure is shown, and trying again can succeed', () async {
    transcriber.error = const TranscribeException(TranscribeFailureKind.failed);
    await controller().show(testRequest());
    expect(stateOf()?.phase, TranscriptPhase.failed);
    expect(transcribeCanRetry(stateOf()!.error!), isTrue);
    expect(cache.entries, isEmpty);

    await controller().show(testRequest());
    expect(stateOf()?.phase, TranscriptPhase.done);
    expect(transcriber.transcribeCalls, hasLength(2));
  });

  test('no speech and an unreadable file cannot be retried', () {
    for (final kind in [
      TranscribeFailureKind.noSpeech,
      TranscribeFailureKind.unreadable,
    ]) {
      expect(transcribeCanRetry(TranscribeException(kind)), isFalse);
    }
    expect(transcribeCanRetry(const AiLimitReachedException()), isFalse);
    expect(transcribeCanRetry(const AiBusyException()), isTrue);
  });

  test('a plan with no engine says why nothing is transcribed', () async {
    transcriber.planValue = const TranscribePlan.unavailable(
      TranscribeUnavailable.platform,
    );
    await controller().show(testRequest());
    expect(stateOf()?.phase, TranscriptPhase.unavailable);
    expect(stateOf()?.unavailable, TranscribeUnavailable.platform);
    expect(transcriber.transcribeCalls, isEmpty);
  });

  test("Apple's servers are only used after the person agrees", () async {
    transcriber.planValue = const TranscribePlan.engine(
      TranscribeEngine.appleServer,
    );
    await controller().show(testRequest());
    expect(stateOf()?.phase, TranscriptPhase.needsConsent);
    expect(transcriber.transcribeCalls, isEmpty);

    transcriber.engine = TranscribeEngine.appleServer;
    await controller().confirmServerRecognition(testRequest());
    expect(stateOf()?.phase, TranscriptPhase.done);
    expect(stateOf()?.engine, TranscribeEngine.appleServer);
    expect(transcriber.transcribeCalls.single.allowServer, isTrue);
  });

  test('the device saying it needs the server asks for consent', () async {
    transcriber.error = const TranscribeException(
      TranscribeFailureKind.needsServer,
    );
    await controller().show(testRequest());
    expect(stateOf()?.phase, TranscriptPhase.needsConsent);
  });

  test('the server engine follows the Settings AI switch', () async {
    transcriber.planValue = const TranscribePlan.engine(
      TranscribeEngine.aiServer,
    );
    transcriber.engine = TranscribeEngine.aiServer;
    await controller().show(testRequest());
    expect(stateOf()?.phase, TranscriptPhase.done);
    expect(stateOf()?.engine, TranscribeEngine.aiServer);

    controller().hide('message-1');
    cache.entries.clear();
    await container.read(aiEnabledProvider.notifier).set(false);
    await controller().show(testRequest());
    expect(stateOf()?.phase, TranscriptPhase.unavailable);
    expect(stateOf()?.unavailable, TranscribeUnavailable.aiOff);
  });

  test('hiding while it runs drops the late answer', () async {
    transcriber.gate = Completer<void>();
    final future = controller().show(testRequest());
    await pumpEventQueue();
    controller().hide('message-1');
    transcriber.gate!.complete();
    await future;
    expect(stateOf(), isNull);
  });

  group('auto-transcribe', () {
    Future<void> turnOn() async {
      await container.read(autoTranscribeProvider.notifier).set(true);
    }

    test('is off until the person turns it on', () async {
      expect(container.read(autoTranscribeProvider), isFalse);
      controller().autoTranscribe(testRequest());
      await pumpEventQueue();
      expect(stateOf(), isNull);
      expect(transcriber.planCalls, isEmpty);
    });

    test('transcribes on the device by itself when on', () async {
      await turnOn();
      controller().autoTranscribe(testRequest());
      await pumpEventQueue();
      expect(stateOf()?.text, 'Lunch at noon?');
      expect(transcriber.transcribeCalls.single.allowServer, isFalse);
    });

    test('never goes to a server or Apple on its own', () async {
      await turnOn();
      for (final engine in [
        TranscribeEngine.aiServer,
        TranscribeEngine.appleServer,
      ]) {
        transcriber.planValue = TranscribePlan.engine(
          engine,
          canAutoStart: true,
        );
        controller().autoTranscribe(testRequest());
        await pumpEventQueue();
        expect(stateOf(), isNull, reason: '$engine');
      }
      expect(transcriber.transcribeCalls, isEmpty);
    });

    test('stays quiet when speech recognition is not allowed', () async {
      await turnOn();
      transcriber.planValue = const TranscribePlan.engine(
        TranscribeEngine.onDevice,
      );
      controller().autoTranscribe(testRequest());
      await pumpEventQueue();
      expect(stateOf(), isNull);
      expect(transcriber.transcribeCalls, isEmpty);
    });

    test('a failure leaves the message as it was', () async {
      await turnOn();
      transcriber.error = const TranscribeException(
        TranscribeFailureKind.notAuthorized,
      );
      controller().autoTranscribe(testRequest());
      await pumpEventQueue();
      expect(stateOf(), isNull);
    });

    test('leaves a transcript the person hid hidden', () async {
      await turnOn();
      await controller().show(testRequest());
      controller().hide('message-1');

      controller().autoTranscribe(testRequest());
      await pumpEventQueue();
      expect(stateOf(), isNull);
    });

    test('shows a saved transcript without transcribing again', () async {
      await turnOn();
      cache.entries['message-2'] = CachedTranscript(
        text: 'Saved text',
        engine: TranscribeEngine.onDevice,
        savedAt: DateTime.utc(2026, 10, 10),
      );
      controller().autoTranscribe(testRequest('message-2'));
      await pumpEventQueue();
      expect(stateOf('message-2')?.text, 'Saved text');
      expect(transcriber.planCalls, isEmpty);
      expect(transcriber.transcribeCalls, isEmpty);
    });

    test('works through the voice messages one at a time', () async {
      await turnOn();
      transcriber.gate = Completer<void>();
      controller().autoTranscribe(testRequest('a'));
      controller().autoTranscribe(testRequest('b'));
      await pumpEventQueue();
      expect(transcriber.transcribeCalls.map((c) => c.messageId), ['a']);
      expect(stateOf('a')?.phase, TranscriptPhase.loading);
      expect(stateOf('b'), isNull);

      transcriber.gate!.complete();
      await pumpEventQueue();
      expect(transcriber.transcribeCalls.map((c) => c.messageId), ['a', 'b']);
      expect(stateOf('b')?.phase, TranscriptPhase.done);
    });

    test('the switch is kept', () async {
      await turnOn();
      expect(await autoStore.load(), isTrue);
      final again = makeContainer();
      expect(again.read(autoTranscribeProvider), isFalse);
      await pumpEventQueue();
      expect(again.read(autoTranscribeProvider), isTrue);
    });
  });
}
