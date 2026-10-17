import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/chats/voice_message_player.dart';
import 'package:wecord/features/ai/ai_settings.dart';
import 'package:wecord/features/transcribe/transcribe_controller.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';
import 'package:wecord/features/transcribe/transcript_cache.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../ai/ai_chat_app.dart';
import '../ai/ai_fakes.dart';
import 'transcribe_fakes.dart';

void main() {
  late FakeVoiceTranscriber transcriber;
  late InMemoryTranscriptCache cache;
  late InMemoryAutoTranscribeStore autoStore;

  setUp(() {
    transcriber = FakeVoiceTranscriber();
    cache = InMemoryTranscriptCache();
    autoStore = InMemoryAutoTranscribeStore();
  });

  Widget app({String? messageId = 'message-1', bool card = false}) {
    return ProviderScope(
      overrides: transcribeOverrides(
        transcriber,
        cache: cache,
        autoStore: autoStore,
        ai: FakeAiRepository(),
      ),
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: VoiceMessagePlayer(
                attachment: testVoice,
                messageId: messageId,
                conversationId: 'conversation-1',
                card: card,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> tapTranscribe(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('voice-transcribe-button')));
    await tester.pump();
  }

  testWidgets('a Transcribe button sits next to the player', (tester) async {
    await tester.pumpWidget(app());
    expect(find.byTooltip('Play voice message'), findsOneWidget);
    expect(find.byTooltip('Transcribe'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-transcript')), findsNothing);
  });

  testWidgets('a voice message still sending has no Transcribe button', (
    tester,
  ) async {
    await tester.pumpWidget(app(messageId: null));
    expect(find.byTooltip('Play voice message'), findsOneWidget);
    expect(find.byTooltip('Transcribe'), findsNothing);
  });

  testWidgets('shows progress, then the text under the waveform, then hides', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    transcriber.gate = Completer<void>();
    await tester.pumpWidget(app());

    await tapTranscribe(tester);
    await tester.pump();
    expect(find.text('Transcribing…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // The button now offers to hide it again.
    expect(find.byTooltip('Hide transcript'), findsOneWidget);

    transcriber.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Transcribing…'), findsNothing);
    expect(find.text('Lunch at noon?'), findsOneWidget);
    expect(find.text('Transcribed on this device'), findsOneWidget);
    // Under the waveform, inside the same bubble.
    final player = tester.getRect(find.byType(VoiceMessagePlayer));
    final text = tester.getRect(find.text('Lunch at noon?'));
    expect(player.contains(text.center), isTrue);
    expect(
      text.top,
      greaterThan(tester.getRect(find.byTooltip('Play voice message')).bottom),
    );

    // A screen reader reads the transcript, as a live region.
    expect(find.bySemanticsLabel('Transcript: Lunch at noon?'), findsOneWidget);
    final node = tester.getSemantics(
      find.bySemanticsLabel('Transcript: Lunch at noon?'),
    );
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);

    await tester.tap(find.byKey(const ValueKey('voice-transcript-hide')));
    await tester.pumpAndSettle();
    expect(find.text('Lunch at noon?'), findsNothing);
    expect(find.byTooltip('Transcribe'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('showing it again is instant and does not transcribe again', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tapTranscribe(tester);
    await tester.pumpAndSettle();
    expect(find.text('Lunch at noon?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-transcribe-button')));
    await tester.pumpAndSettle();
    expect(find.text('Lunch at noon?'), findsNothing);

    await tapTranscribe(tester);
    await tester.pump();
    expect(find.text('Lunch at noon?'), findsOneWidget);
    expect(find.text('Transcribing…'), findsNothing);
    expect(transcriber.transcribeCalls, hasLength(1));
    expect(cache.entries['message-1']?.text, 'Lunch at noon?');
  });

  testWidgets('an error offers Try again, and a retry can succeed', (
    tester,
  ) async {
    transcriber.error = const TranscribeException(TranscribeFailureKind.failed);
    await tester.pumpWidget(app());
    await tapTranscribe(tester);
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voice-transcript-retry')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('voice-transcript-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Lunch at noon?'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-transcript-error')), findsNothing);
  });

  testWidgets('no speech and a denied permission are explained', (
    tester,
  ) async {
    transcriber.error = const TranscribeException(
      TranscribeFailureKind.noSpeech,
    );
    await tester.pumpWidget(app());
    await tapTranscribe(tester);
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't find any speech in this voice message."),
      findsOneWidget,
    );
    // Nothing a retry would change.
    expect(find.byKey(const ValueKey('voice-transcript-retry')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('voice-transcript-dismiss')));
    await tester.pumpAndSettle();

    transcriber.error = const TranscribeException(
      TranscribeFailureKind.notAuthorized,
    );
    await tapTranscribe(tester);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Speech recognition is turned off for WeCord'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('voice-transcript-retry')),
      findsOneWidget,
    );
  });

  testWidgets('where it can not work, says so and can be dismissed', (
    tester,
  ) async {
    transcriber.planValue = const TranscribePlan.unavailable(
      TranscribeUnavailable.platform,
    );
    await tester.pumpWidget(app());
    await tapTranscribe(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('Transcription is available in the iPhone and Mac apps.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('voice-transcript-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-transcript')), findsNothing);
  });

  testWidgets('Apple\'s servers are explained first, then used if agreed', (
    tester,
  ) async {
    transcriber.planValue = const TranscribePlan.engine(
      TranscribeEngine.appleServer,
    );
    transcriber.engine = TranscribeEngine.appleServer;
    await tester.pumpWidget(app());
    await tapTranscribe(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining("sent to Apple's speech service"), findsOne);
    expect(transcriber.transcribeCalls, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey('voice-transcript-send-to-apple')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lunch at noon?'), findsOneWidget);
    expect(find.text("Transcribed by Apple's speech service"), findsOneWidget);
    expect(transcriber.transcribeCalls.single.allowServer, isTrue);
  });

  testWidgets('declining Apple\'s servers leaves the message alone', (
    tester,
  ) async {
    transcriber.planValue = const TranscribePlan.engine(
      TranscribeEngine.appleServer,
    );
    await tester.pumpWidget(app());
    await tapTranscribe(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-transcript-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-transcript')), findsNothing);
    expect(transcriber.transcribeCalls, isEmpty);
  });

  testWidgets('works in a card too, and in Chinese', (tester) async {
    AppStrings.isChinese = true;
    addTearDown(() => AppStrings.isChinese = false);
    await tester.pumpWidget(app(card: true));
    expect(find.byTooltip('转文字'), findsOneWidget);
    await tapTranscribe(tester);
    await tester.pumpAndSettle();
    expect(find.text('Lunch at noon?'), findsOneWidget);
    expect(find.text('已在本设备上转写'), findsOneWidget);
    expect(find.text('收起文字'), findsOneWidget);
  });

  group('auto-transcribe', () {
    testWidgets('does nothing while the switch is off', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-transcript')), findsNothing);
      expect(transcriber.planCalls, isEmpty);
    });

    testWidgets('transcribes a voice message that appears, on the device', (
      tester,
    ) async {
      await autoStore.save(true);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Lunch at noon?'), findsOneWidget);
      expect(transcriber.transcribeCalls.single.allowServer, isFalse);
    });

    testWidgets('starts when the switch is turned on while it is visible', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(VoiceMessagePlayer)),
      );
      await container.read(autoTranscribeProvider.notifier).set(true);
      await tester.pumpAndSettle();
      expect(find.text('Lunch at noon?'), findsOneWidget);
    });

    testWidgets('does not use a server on its own', (tester) async {
      await autoStore.save(true);
      transcriber.planValue = const TranscribePlan.engine(
        TranscribeEngine.aiServer,
        canAutoStart: true,
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-transcript')), findsNothing);
      expect(transcriber.transcribeCalls, isEmpty);
    });
  });

  group('in a chat', () {
    void useDesktopSize(WidgetTester tester) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1300, 900);
      addTearDown(tester.view.reset);
    }

    AiChatHarness harness() {
      return AiChatHarness(
        FakeAiRepository(),
        extraOverrides: transcribeOverrides(
          transcriber,
          cache: cache,
          autoStore: autoStore,
        ),
        messages: [
          ChatMessage(
            id: 'message-1',
            conversationId: 'conversation-1',
            senderId: 'user-2',
            type: MessageType.voice,
            body: '',
            createdAt: DateTime.utc(2026, 5, 18, 4, 1),
            attachment: testVoice.toJson(),
          ),
          AiChatHarness.message('message-2', 'user-2', 'A text message', 2),
        ],
      );
    }

    testWidgets('the message menu offers Transcribe, then Hide transcript', (
      tester,
    ) async {
      useDesktopSize(tester);
      await tester.pumpWidget(harness().build());
      await tester.pumpAndSettle();

      await tester.tap(
        find.byType(VoiceMessagePlayer),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-transcribe')));
      await tester.pumpAndSettle();
      expect(find.text('Lunch at noon?'), findsOneWidget);

      await tester.tap(
        find.byType(VoiceMessagePlayer),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Hide transcript'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('message-transcribe')));
      await tester.pumpAndSettle();
      expect(find.text('Lunch at noon?'), findsNothing);
    });

    testWidgets('text messages have no Transcribe entry', (tester) async {
      useDesktopSize(tester);
      await tester.pumpWidget(harness().build());
      await tester.pumpAndSettle();
      await tester.tap(find.text('A text message'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('message-transcribe')), findsNothing);
    });
  });

  group('Settings → AI', () {
    List<Override> overrides() => [
      ...transcribeOverrides(
        transcriber,
        cache: cache,
        autoStore: autoStore,
        ai: FakeAiRepository(),
      ),
      aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
    ];

    Future<void> openGroup(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: const Scaffold(
              body: SingleChildScrollView(child: AiSettingsGroup()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('has an Auto-transcribe switch, off by default', (
      tester,
    ) async {
      await openGroup(tester);
      expect(find.text('Auto-transcribe voice messages'), findsOneWidget);
      expect(
        tester
            .widget<WeCordSwitch>(
              find.descendant(
                of: find.byKey(const ValueKey('auto-transcribe-switch')),
                matching: find.byType(WeCordSwitch),
              ),
            )
            .value,
        isFalse,
      );
    });

    testWidgets('turning it on is kept on this device', (tester) async {
      await openGroup(tester);
      await tester.tap(find.byKey(const ValueKey('auto-transcribe-switch')));
      await tester.pumpAndSettle();
      expect(await autoStore.load(), isTrue);
    });

    testWidgets('is left out where the device can not transcribe', (
      tester,
    ) async {
      transcriber.runsOnDevice = false;
      await openGroup(tester);
      expect(find.text('Auto-transcribe voice messages'), findsNothing);
    });
  });
}
