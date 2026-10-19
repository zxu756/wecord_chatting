import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/notes/notes2_repository.dart';
import 'package:wecord/features/notes/notes_repository.dart';
import 'package:wecord/features/voice/captions/caption_protocol.dart';
import 'package:wecord/features/voice/captions/captions_sheets.dart';
import 'package:wecord/features/voice/captions/captions_strip.dart';
import 'package:wecord/features/voice/captions/recap/meeting_recap_repository.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../notes/notes2_fakes.dart';
import '../../voice_input/fake_voice_recognizer.dart';
import '../../workspace/workspace_fakes.dart';
import 'captions_fakes.dart';

class _Rig {
  _Rig({bool host = true, FakeVoiceRecognizer? recognizer, bool ai = true})
    : recaps = FakeMeetingRecaps(),
      notes = FakeNotesRepository(),
      notes2 = FakeNotes2Repository() {
    world = CaptionsWorld(
      host: host,
      recognizer: recognizer,
      ownContainer: false,
      extraOverrides: [
        meetingRecapRepositoryProvider.overrideWithValue(recaps),
        notesRepositoryProvider.overrideWithValue(notes),
        notes2RepositoryProvider.overrideWithValue(notes2),
        aiAvailableProvider.overrideWith((ref, circleId) => ai),
      ],
    );
  }

  final FakeMeetingRecaps recaps;
  final FakeNotesRepository notes;
  final FakeNotes2Repository notes2;
  late final CaptionsWorld world;

  /// The caption button and bar, in the dark voice room.
  Future<void> pump(
    WidgetTester tester, {
    double textScale = 1,
    bool disableAnimations = false,
    Size size = const Size(420, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: world.overrides,
        child: MaterialApp(
          theme: WeCordTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
            ),
            child: child!,
          ),
          home: VoiceRoomTheme(
            child: Scaffold(
              body: SafeArea(
                child: Column(
                  children: const [
                    Row(children: [CaptionsButton()]),
                    CaptionStrip(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    world.adopt(
      ProviderScope.containerOf(tester.element(find.byType(Scaffold))),
    );
    await world.join(tester);
    await tester.pump();
  }
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Finder get _button => find.byKey(const ValueKey('voice-captions-button'));
Finder get _strip => find.byKey(const ValueKey('caption-strip'));

void captionsUiTest(
  String name,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(name, (tester) async {
    AppStrings.isChinese = false;
    await body(tester);
    await currentCaptionsWorld?.shutdown(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void main() {
  captionsUiTest('someone who may host turns captions on from the button', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);
    expect(_strip, findsNothing);
    expect(_button, findsOneWidget);

    await tester.tap(_button);
    await settle(tester);
    // It says what captions are before they start.
    expect(find.text('Turn on captions?'), findsOneWidget);
    expect(
      find.text('Everyone in the call sees that captions are on.'),
      findsOneWidget,
    );
    expect(rig.world.state.active, isFalse);

    await tester.tap(find.byKey(const ValueKey('captions-start')));
    await settle(tester);
    expect(rig.world.state.active, isTrue);
    expect(_strip, findsOneWidget);
    expect(find.text('Captions are on'), findsOneWidget);
    expect(find.text('Waiting for someone to speak…'), findsOneWidget);
  });

  captionsUiTest('someone who may not host sees no button until it is on', (
    tester,
  ) async {
    final rig = _Rig(host: false);
    await rig.pump(tester);
    expect(_button, findsNothing);
    expect(_strip, findsNothing);

    rig.world.makeHost('user-2');
    await rig.world.receive('user-2', encodeCaptionControl(on: true));
    await settle(tester);
    expect(_strip, findsOneWidget);
    expect(find.text('Captions are on · Bart'), findsOneWidget);
    // Everyone gets the settings, but not the switch-off.
    expect(_button, findsOneWidget);
    await tester.tap(_button);
    await settle(tester);
    expect(find.byKey(const ValueKey('captions-share')), findsOneWidget);
    expect(find.byKey(const ValueKey('captions-stop')), findsNothing);
  });

  captionsUiTest('lines show who said them, newest last', (tester) async {
    final rig = _Rig();
    await rig.pump(tester);
    await rig.world.captions.start();
    await settle(tester);
    final at = rig.world.now;
    await rig.world.receive(
      'user-2',
      encodeCaptionLine(
        id: 0,
        text: 'Is the plan ready?',
        at: at,
        isFinal: true,
      ),
    );
    await rig.world.receive(
      'user-3',
      encodeCaptionLine(
        id: 0,
        text: 'Almost, give me ten',
        at: at,
        isFinal: false,
      ),
    );
    await settle(tester);
    expect(
      find.textContaining('Is the plan ready?', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Bart', findRichText: true), findsWidgets);
    expect(find.byKey(const ValueKey('caption-live-user-3')), findsOneWidget);
    expect(find.text('Waiting for someone to speak…'), findsNothing);
    // The line still being spoken is not read out; the settled one is.
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('caption-line-user-2-0')),
    );
    expect(semantics.label, contains('Is the plan ready?'));
  });

  captionsUiTest('only the three newest settled lines are on the bar', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);
    await rig.world.captions.start();
    await settle(tester);
    for (var i = 0; i < 5; i++) {
      await rig.world.receive(
        'user-2',
        encodeCaptionLine(
          id: i,
          text: 'sentence number $i',
          at: rig.world.now,
          isFinal: true,
        ),
      );
    }
    await settle(tester);
    expect(
      find.textContaining('sentence number 4', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('sentence number 2', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('sentence number 1', findRichText: true),
      findsNothing,
    );
    // The transcript keeps all of them.
    await tester.tap(find.byKey(const ValueKey('caption-strip-settings')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('captions-transcript')));
    await settle(tester);
    expect(
      find.textContaining('sentence number 0', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('sentence number 4', findRichText: true),
      findsWidgets,
    );
  });

  captionsUiTest(
    'a device that can not make captions says so, and so do others',
    (tester) async {
      final rig = _Rig(recognizer: FakeVoiceRecognizer(supported: false));
      await rig.pump(tester);
      await rig.world.captions.start();
      await settle(tester);
      expect(find.byKey(const ValueKey('caption-notice')), findsOneWidget);
      expect(
        find.textContaining("Your device can't make captions"),
        findsOneWidget,
      );
      await rig.world.receive('user-2', encodeCaptionSupport(supported: false));
      await settle(tester);
      expect(
        find.text("Bart's device doesn't support captions"),
        findsOneWidget,
      );
      await rig.world.receive('user-3', encodeCaptionSupport(supported: false));
      await settle(tester);
      expect(
        find.text("Bart, Grace: their devices don't support captions"),
        findsOneWidget,
      );
    },
  );

  captionsUiTest('a speech service asks first, and Not now stops sharing', (
    tester,
  ) async {
    final rig = _Rig(
      recognizer: FakeVoiceRecognizer(engine: VoiceInputEngine.appleServer),
    );
    await rig.pump(tester);
    await rig.world.captions.start();
    await settle(tester);
    expect(find.byKey(const ValueKey('caption-allow-service')), findsOneWidget);
    expect(rig.world.recognizer.starts, isEmpty);

    await tester.tap(find.byKey(const ValueKey('caption-decline-service')));
    await settle(tester);
    expect(rig.world.state.sharing, isFalse);
    expect(find.text("You're not sharing your captions."), findsOneWidget);
    expect(rig.world.recognizer.starts, isEmpty);
  });

  captionsUiTest('sharing and the language are changed in the settings', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);
    await rig.world.captions.start();
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('caption-strip-settings')));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('captions-share')));
    await settle(tester);
    expect(rig.world.state.sharing, isFalse);
    await tester.tap(find.text(VoiceInputLanguage.chinese.label));
    await settle(tester);
    expect(rig.world.state.language, VoiceInputLanguage.chinese);
  });

  captionsUiTest('captions can be hidden on one screen and shown again', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);
    await rig.world.captions.start();
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('caption-strip-settings')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('captions-hide')));
    await settle(tester);
    expect(_strip, findsNothing);
    expect(find.byKey(const ValueKey('caption-strip-hidden')), findsOneWidget);
    // Still on for the call.
    expect(rig.world.state.active, isTrue);

    await tester.tap(find.byKey(const ValueKey('caption-strip-show')));
    await settle(tester);
    expect(_strip, findsOneWidget);
  });

  captionsUiTest('turning captions off asks about a recap and writes it', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);
    await rig.world.captions.start();
    await settle(tester);
    for (var i = 0; i < 3; i++) {
      await rig.world.receive(
        'user-2',
        encodeCaptionLine(
          id: i,
          text: 'We ship on Friday $i',
          at: rig.world.now,
          isFinal: true,
        ),
      );
    }
    await tester.tap(find.byKey(const ValueKey('caption-strip-settings')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('captions-stop')));
    await settle(tester);
    expect(find.byKey(const ValueKey('captions-stop-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('captions-stop-recap')));
    await settle(tester);
    // Captions are off for everyone and the words went to the recap.
    expect(rig.world.state.active, isFalse);
    expect(sent(rig.world.call).last['k'], 'off');
    expect(rig.recaps.asked, hasLength(1));
    expect(rig.recaps.asked.single.conversationId, 'conv-lounge');
    expect(rig.recaps.asked.single.entries.map((e) => e['text']), [
      'We ship on Friday 0',
      'We ship on Friday 1',
      'We ship on Friday 2',
    ]);
    expect(find.text('The launch is on Friday.'), findsOneWidget);
    expect(find.text('Ship on Friday.'), findsOneWidget);
    expect(find.textContaining('Send the plan'), findsOneWidget);

    // Saving makes a note and posts its card in the chat.
    await tester.tap(find.byKey(const ValueKey('recap-save')));
    await settle(tester);
    expect(rig.notes2.createdFromBlocks, hasLength(1));
    final note = rig.notes2.createdFromBlocks.single;
    expect(note.title, 'Launch sync');
    expect(note.blocks.map((b) => b.text), contains('Send the plan - Bart'));
    expect(rig.notes.shared.single.$2, 'conv-lounge');
    expect(find.text('Saved and shared'), findsOneWidget);
  });

  captionsUiTest('Turn off without a recap just turns them off', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);
    await rig.world.captions.start();
    await settle(tester);
    for (var i = 0; i < 3; i++) {
      await rig.world.receive(
        'user-2',
        encodeCaptionLine(
          id: i,
          text: 'line $i',
          at: rig.world.now,
          isFinal: true,
        ),
      );
    }
    await tester.tap(find.byKey(const ValueKey('caption-strip-settings')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('captions-stop')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('captions-stop-only')));
    await settle(tester);
    expect(rig.world.state.active, isFalse);
    expect(rig.recaps.asked, isEmpty);
    expect(_strip, findsNothing);
  });

  captionsUiTest('with nothing to write about, turning off is direct', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);
    await rig.world.captions.start();
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('caption-strip-settings')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('captions-stop')));
    await settle(tester);
    expect(find.byKey(const ValueKey('captions-stop-dialog')), findsNothing);
    expect(rig.world.state.active, isFalse);
  });

  captionsUiTest('a recap that fails can be tried again', (tester) async {
    final rig = _Rig();
    rig.recaps.error = const AiFailedException();
    await rig.pump(tester);
    await rig.world.captions.start();
    await settle(tester);
    for (var i = 0; i < 3; i++) {
      await rig.world.receive(
        'user-2',
        encodeCaptionLine(
          id: i,
          text: 'line $i',
          at: rig.world.now,
          isFinal: true,
        ),
      );
    }
    await tester.tap(find.byKey(const ValueKey('caption-strip-settings')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('captions-stop')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('captions-stop-recap')));
    await settle(tester);
    expect(find.byKey(const ValueKey('recap-error')), findsOneWidget);

    rig.recaps.error = null;
    await tester.tap(find.byKey(const ValueKey('recap-retry')));
    await settle(tester);
    expect(find.byKey(const ValueKey('recap-save')), findsOneWidget);
    expect(rig.recaps.asked, hasLength(2));
  });

  captionsUiTest('without AI there is no recap offer', (tester) async {
    final rig = _Rig(ai: false);
    await rig.pump(tester);
    await rig.world.captions.start();
    await settle(tester);
    for (var i = 0; i < 4; i++) {
      await rig.world.receive(
        'user-2',
        encodeCaptionLine(
          id: i,
          text: 'line $i',
          at: rig.world.now,
          isFinal: true,
        ),
      );
    }
    await tester.tap(find.byKey(const ValueKey('caption-strip-settings')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('captions-stop')));
    await settle(tester);
    expect(find.byKey(const ValueKey('captions-stop-dialog')), findsNothing);
    expect(rig.world.state.active, isFalse);
  });

  captionsUiTest('large text scrolls instead of overflowing', (tester) async {
    final rig = _Rig();
    await rig.pump(tester, textScale: 2, size: const Size(360, 640));
    await rig.world.captions.start();
    await settle(tester);
    for (var i = 0; i < 4; i++) {
      await rig.world.receive(
        'user-2',
        encodeCaptionLine(
          id: i,
          text:
              'A fairly long sentence number $i that wraps over several lines when the text is large',
          at: rig.world.now,
          isFinal: true,
        ),
      );
    }
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(_strip, findsOneWidget);
    final box = tester.getRect(_strip);
    expect(box.bottom, lessThan(640));
  });

  captionsUiTest('reduced motion draws the bar at once', (tester) async {
    final rig = _Rig();
    await rig.pump(tester, disableAnimations: true);
    await rig.world.captions.start();
    await tester.pump();
    expect(_strip, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  captionsUiTest('Chinese labels', (tester) async {
    final rig = _Rig();
    await rig.pump(tester);
    AppStrings.isChinese = true;
    await rig.world.captions.start();
    await settle(tester);
    expect(find.text('字幕已开启'), findsOneWidget);
    expect(find.text('等人说话…'), findsOneWidget);
  });

  test('the caption notice constants stay in step with the server', () {
    // The host repeats itself well inside the time others wait for it.
    expect(
      captionHeartbeat * 3,
      lessThan(captionHostTimeout + captionHeartbeat),
    );
    expect(minRecapLines, greaterThan(0));
    expect(captionBarLines, 3);
    expect(
      const VoiceCallParticipant(userId: 'x', name: 'x').captionsHost,
      isFalse,
    );
  });
}
