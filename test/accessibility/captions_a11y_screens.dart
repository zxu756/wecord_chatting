// Call captions and the call recap (E1: the caption bar, the sheet that
// turns captions on, the caption settings, the transcript, the question
// when they are turned off, the recap), for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/notes/notes2_repository.dart';
import 'package:wecord/features/notes/notes_repository.dart';
import 'package:wecord/features/voice/captions/caption_protocol.dart';
import 'package:wecord/features/voice/captions/captions_controller.dart';
import 'package:wecord/features/voice/captions/captions_sheets.dart';
import 'package:wecord/features/voice/captions/captions_strip.dart';
import 'package:wecord/features/voice/captions/recap/meeting_recap_repository.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

import '../features/notes/notes2_fakes.dart';
import '../features/voice/captions/captions_fakes.dart';
import '../features/voice_input/fake_voice_recognizer.dart';
import '../features/workspace/workspace_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// What the caption screens need around the voice room.
List<Override> captionsOverrides({
  FakeVoiceRecognizer? recognizer,
  FakeMeetingRecaps? recaps,
}) => [
  voiceRecognizerProvider.overrideWithValue(
    recognizer ?? FakeVoiceRecognizer(),
  ),
  meetingRecapRepositoryProvider.overrideWithValue(
    recaps ?? FakeMeetingRecaps(),
  ),
  notesRepositoryProvider.overrideWithValue(FakeNotesRepository()),
  notes2RepositoryProvider.overrideWithValue(FakeNotes2Repository()),
  aiAvailableProvider.overrideWith((ref, circleId) => true),
];

/// A call with [host] (whether this user may turn captions on) and Bart and
/// Grace in it.
void captionsWorld(PhoneWorld world, {bool host = true}) {
  world.voiceCalls.prepare = (call) {
    call.localCaptionsHost = host;
    call.remotes = [
      VoiceCallParticipant(
        userId: bart.id,
        name: 'Bart',
        isSpeaking: true,
        microphoneEnabled: true,
        captionsHost: !host,
      ),
      VoiceCallParticipant(
        userId: grace.id,
        name: 'Grace',
        microphoneEnabled: true,
      ),
    ];
  };
}

/// The caption button and bar on the voice room's dark backdrop, with the
/// user joined to the lounge. Returns the app's container.
Future<ProviderContainer> pumpCaptionRoom(
  WidgetTester tester,
  PhoneWorld world, {
  FakeVoiceRecognizer? recognizer,
  FakeMeetingRecaps? recaps,
}) async {
  await pumpStandalone(
    tester,
    world,
    VoiceRoomTheme(
      child: Scaffold(
        backgroundColor: WeCordTokens.dark.colors.paper,
        body: const SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CaptionsButton(),
                ),
              ),
              CaptionStrip(),
            ],
          ),
        ),
      ),
    ),
    extraOverrides: captionsOverrides(recognizer: recognizer, recaps: recaps),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold)),
  );
  await container
      .read(voiceSessionProvider.notifier)
      .join(
        circleId: 'circle-1',
        channelId: 'ch-lounge',
        conversationId: 'conv-lounge',
        channelName: 'Lounge',
      );
  await settle(tester);
  return container;
}

/// Bart and Grace say something, as their devices send it.
void _say(
  PhoneWorld world,
  ProviderContainer container, {
  bool livePartial = true,
}) {
  final call = world.voiceCalls.last;
  final now = DateTime.now();
  call
    ..receiveData(
      bart.id,
      captionTopic,
      encodeCaptionLine(
        id: 0,
        text: 'Did everyone get the new budget numbers?',
        at: now,
        isFinal: true,
      ),
    )
    ..receiveData(
      grace.id,
      captionTopic,
      encodeCaptionLine(
        id: 0,
        text: 'I did. They look tighter than last quarter.',
        at: now,
        isFinal: true,
      ),
    );
  if (livePartial) {
    call.receiveData(
      bart.id,
      captionTopic,
      encodeCaptionLine(
        id: 1,
        text: 'Then let us move the launch to Friday',
        at: now,
        isFinal: false,
      ),
    );
  }
}

Future<ProviderContainer> _captionsOn(
  WidgetTester tester,
  PhoneWorld world, {
  bool host = true,
  FakeVoiceRecognizer? recognizer,
}) async {
  captionsWorld(world, host: host);
  final container = await pumpCaptionRoom(
    tester,
    world,
    recognizer: recognizer,
  );
  if (host) {
    await container.read(captionsProvider.notifier).start();
  } else {
    world.voiceCalls.last.receiveData(
      bart.id,
      captionTopic,
      encodeCaptionControl(on: true),
    );
  }
  await settle(tester);
  return container;
}

Future<void> _bar(WidgetTester tester, PhoneWorld world) async {
  final container = await _captionsOn(tester, world);
  _say(world, container);
  await settle(tester);
}

Future<void> _barJoinedLate(WidgetTester tester, PhoneWorld world) async {
  final container = await _captionsOn(tester, world, host: false);
  _say(world, container);
  await settle(tester);
}

Future<void> _barNotices(WidgetTester tester, PhoneWorld world) async {
  final container = await _captionsOn(
    tester,
    world,
    recognizer: FakeVoiceRecognizer(supported: false),
  );
  world.voiceCalls.last
    ..receiveData(bart.id, captionTopic, encodeCaptionSupport(supported: false))
    ..receiveData(
      grace.id,
      captionTopic,
      encodeCaptionLine(
        id: 0,
        text: 'Can you see the captions on your side?',
        at: DateTime.now(),
        isFinal: true,
      ),
    );
  await settle(tester);
  expect(container.read(captionsProvider).mic, CaptionMic.unsupported);
}

Future<void> _barConsent(WidgetTester tester, PhoneWorld world) async {
  await _captionsOn(
    tester,
    world,
    recognizer: FakeVoiceRecognizer(engine: VoiceInputEngine.appleServer),
  );
}

Future<void> _barHidden(WidgetTester tester, PhoneWorld world) async {
  final container = await _captionsOn(tester, world);
  container.read(captionsProvider.notifier).setHidden(true);
  await settle(tester);
}

Future<void> _startSheet(WidgetTester tester, PhoneWorld world) async {
  captionsWorld(world);
  await pumpCaptionRoom(tester, world);
  await tester.tap(find.byKey(const ValueKey('voice-captions-button')));
  await settle(tester);
}

Future<void> _settingsSheet(WidgetTester tester, PhoneWorld world) async {
  final container = await _captionsOn(tester, world);
  _say(world, container, livePartial: false);
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('caption-strip-settings')));
  await settle(tester);
}

Future<void> _settingsSheetGuest(WidgetTester tester, PhoneWorld world) async {
  await _captionsOn(tester, world, host: false);
  await tester.tap(find.byKey(const ValueKey('caption-strip-settings')));
  await settle(tester);
}

Future<void> _transcript(WidgetTester tester, PhoneWorld world) async {
  await _settingsSheet(tester, world);
  await tester.tap(find.byKey(const ValueKey('captions-transcript')));
  await settle(tester);
}

Future<void> _stopDialog(WidgetTester tester, PhoneWorld world) async {
  await _settingsSheet(tester, world);
  final call = world.voiceCalls.last;
  call.receiveData(
    bart.id,
    captionTopic,
    encodeCaptionLine(
      id: 5,
      text: 'We will ship on Friday and review on Monday.',
      at: DateTime.now(),
      isFinal: true,
    ),
  );
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('captions-stop')));
  await settle(tester);
}

Future<void> _recap(WidgetTester tester, PhoneWorld world) async {
  await _stopDialog(tester, world);
  await tester.tap(find.byKey(const ValueKey('captions-stop-recap')));
  await settle(tester);
}

final captionsA11yScreens = <A11yScreen>[
  A11yScreen('captions-bar', _bar),
  A11yScreen('captions-bar-late-joiner', _barJoinedLate),
  A11yScreen('captions-bar-notices', _barNotices),
  A11yScreen('captions-bar-consent', _barConsent),
  A11yScreen('captions-bar-hidden', _barHidden),
  A11yScreen('captions-start-sheet', _startSheet),
  A11yScreen('captions-settings-sheet', _settingsSheet),
  A11yScreen('captions-settings-sheet-guest', _settingsSheetGuest),
  A11yScreen('captions-transcript', _transcript),
  A11yScreen('captions-stop-dialog', _stopDialog),
  A11yScreen('captions-recap-sheet', _recap),
  A11yScreen(
    'captions-bar-desktop',
    _bar,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'captions-settings-sheet-desktop',
    _settingsSheet,
    viewport: desktopViewport,
    desktop: true,
  ),
];
