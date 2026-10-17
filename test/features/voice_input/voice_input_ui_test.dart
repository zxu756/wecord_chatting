import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/settings/chat_settings.dart';
import 'package:wecord/features/voice_input/voice_input_button.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/features/voice_input/voice_input_panel.dart';
import 'package:wecord/features/voice_input/voice_input_settings.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'fake_voice_recognizer.dart';

class _Host extends StatefulWidget {
  const _Host({this.panelOwner = 'chat-1'});

  final String panelOwner;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final controller = TextEditingController(text: 'Hi');
  final focus = FocusNode();

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            VoiceInputPanel(owner: widget.panelOwner),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('field'),
                    controller: controller,
                    focusNode: focus,
                  ),
                ),
                VoiceInputButton(
                  owner: 'chat-1',
                  field: controller,
                  focus: focus,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<FakeVoiceRecognizer> pumpHost(
  WidgetTester tester, {
  FakeVoiceRecognizer? recognizer,
  String panelOwner = 'chat-1',
  InMemoryVoiceInputStore? store,
}) async {
  final fake = recognizer ?? FakeVoiceRecognizer();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        voiceRecognizerProvider.overrideWithValue(fake),
        voiceInputStoreProvider.overrideWithValue(
          store ?? InMemoryVoiceInputStore(),
        ),
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: _Host(panelOwner: panelOwner),
      ),
    ),
  );
  return fake;
}

String fieldText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('field')))
    .controller!
    .text;

Future<void> startByTap(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('composer-voice-input-button')));
  await tester.pump();
  await tester.pump();
  // The panel grows in.
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  testWidgets('nothing shows until voice input starts', (tester) async {
    await pumpHost(tester);
    expect(find.byKey(const ValueKey('voice-input-panel')), findsNothing);
    expect(find.byTooltip('Voice input'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('tap to start, the words appear live, Done keeps them', (
    tester,
  ) async {
    final recognizer = await pumpHost(tester);
    await startByTap(tester);

    expect(find.byKey(const ValueKey('voice-input-panel')), findsOneWidget);
    expect(find.text('Listening…'), findsOneWidget);
    expect(find.text('Say something…'), findsOneWidget);
    expect(find.text('Recognized on this device'), findsOneWidget);
    expect(find.byTooltip('Finish voice input'), findsOneWidget);

    recognizer.session
      ..level(0.5)
      ..say('see you at the gate');
    await tester.pump();
    expect(fieldText(tester), 'Hi see you at the gate');
    expect(find.text('see you at the gate'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-done')));
    await tester.pumpAndSettle();
    expect(recognizer.session.stopped, isTrue);
    expect(find.byKey(const ValueKey('voice-input-panel')), findsNothing);
    expect(fieldText(tester), 'Hi see you at the gate');
    await unmount(tester);
  });

  testWidgets('tapping the button again finishes', (tester) async {
    final recognizer = await pumpHost(tester);
    await startByTap(tester);
    recognizer.session.say('yes');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composer-voice-input-button')));
    await tester.pumpAndSettle();
    expect(recognizer.session.stopped, isTrue);
    expect(fieldText(tester), 'Hi yes');
    expect(find.byKey(const ValueKey('voice-input-panel')), findsNothing);
    await unmount(tester);
  });

  testWidgets('Cancel puts the text back', (tester) async {
    final recognizer = await pumpHost(tester);
    await startByTap(tester);
    recognizer.session.say('never mind');
    await tester.pump();
    expect(fieldText(tester), 'Hi never mind');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fieldText(tester), 'Hi');
    expect(recognizer.session.cancelled, isTrue);
    expect(find.byKey(const ValueKey('voice-input-panel')), findsNothing);
    await unmount(tester);
  });

  testWidgets('Esc cancels', (tester) async {
    final recognizer = await pumpHost(tester);
    await startByTap(tester);
    recognizer.session.say('oops');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(fieldText(tester), 'Hi');
    expect(find.byKey(const ValueKey('voice-input-panel')), findsNothing);
    await unmount(tester);
  });

  testWidgets('press and hold dictates while held and finishes on release', (
    tester,
  ) async {
    final recognizer = await pumpHost(tester);
    final button = find.byKey(const ValueKey('composer-voice-input-button'));
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.byKey(const ValueKey('voice-input-panel')), findsOneWidget);
    recognizer.session.say('held words');
    await tester.pump();
    expect(recognizer.session.stopped, isFalse);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(recognizer.session.stopped, isTrue);
    expect(fieldText(tester), 'Hi held words');
    expect(find.byKey(const ValueKey('voice-input-panel')), findsNothing);
    await unmount(tester);
  });

  testWidgets('the language switch listens again in the other language', (
    tester,
  ) async {
    final recognizer = await pumpHost(tester);
    await startByTap(tester);
    expect(recognizer.starts.single.locale, 'en-US');
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-language-chinese')));
    await tester.pump();
    await tester.pump();
    expect(recognizer.starts.last.locale, 'zh-CN');
    recognizer.session.say('你好');
    await tester.pump();
    expect(fieldText(tester), 'Hi你好');
    await unmount(tester);
  });

  testWidgets('it starts in the language of the app', (tester) async {
    AppStrings.isChinese = true;
    final recognizer = await pumpHost(tester);
    await startByTap(tester);
    expect(recognizer.starts.single.locale, 'zh-CN');
    expect(find.text('正在聆听…'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a server language asks first and says who hears it', (
    tester,
  ) async {
    final recognizer = await pumpHost(
      tester,
      recognizer: FakeVoiceRecognizer(engine: VoiceInputEngine.appleServer),
    );
    await startByTap(tester);

    expect(find.byKey(const ValueKey('voice-consent-text')), findsOneWidget);
    expect(
      find.textContaining("sent to Apple's speech service"),
      findsOneWidget,
    );
    expect(recognizer.starts, isEmpty);

    await tester.tap(find.byKey(const ValueKey('voice-consent-continue')));
    await tester.pump();
    await tester.pump();
    expect(recognizer.starts.single.allowServer, isTrue);
    expect(find.text("Processed by Apple's speech service"), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('on the web the browser\'s speech service is named', (
    tester,
  ) async {
    final recognizer = await pumpHost(
      tester,
      recognizer: FakeVoiceRecognizer(engine: VoiceInputEngine.browser),
    );
    await startByTap(tester);
    expect(
      find.textContaining("Your browser's speech service turns what you say"),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('voice-consent-continue')));
    await tester.pump();
    await tester.pump();
    expect(recognizer.starts, hasLength(1));
    expect(
      find.text("Processed by your browser's speech service"),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('Not now closes the question without listening', (tester) async {
    final recognizer = await pumpHost(
      tester,
      recognizer: FakeVoiceRecognizer(engine: VoiceInputEngine.appleServer),
    );
    await startByTap(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(recognizer.starts, isEmpty);
    expect(find.byKey(const ValueKey('voice-input-panel')), findsNothing);
    await unmount(tester);
  });

  testWidgets('a problem is explained and can be retried', (tester) async {
    final fake = FakeVoiceRecognizer()
      ..startError = const VoiceInputException(VoiceInputFailure.micDenied);
    await pumpHost(tester, recognizer: fake);
    await startByTap(tester);

    expect(
      find.text(
        'The microphone is turned off for WeCord. Turn it on in Settings, then try again.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('voice-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Listening…'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  testWidgets('a panel of another chat stays hidden', (tester) async {
    await pumpHost(tester, panelOwner: 'chat-2');
    await startByTap(tester);
    expect(find.byKey(const ValueKey('voice-input-panel')), findsNothing);
    await unmount(tester);
  });

  testWidgets('the panel is labelled for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHost(tester);
    await startByTap(tester);

    expect(find.bySemanticsLabel(RegExp('Voice input')), findsWidgets);
    expect(find.bySemanticsLabel('Cancel'), findsOneWidget);
    expect(find.bySemanticsLabel('Done'), findsOneWidget);
    expect(find.bySemanticsLabel('Language'), findsOneWidget);
    handle.dispose();
    await unmount(tester);
  });

  group('settings', () {
    Future<InMemoryVoiceInputStore> pumpSettings(
      WidgetTester tester, {
      required bool supported,
      bool? show,
    }) async {
      final store = InMemoryVoiceInputStore(show: show);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceRecognizerProvider.overrideWithValue(
              FakeVoiceRecognizer(supported: supported),
            ),
            voiceInputStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: const Scaffold(body: ChatSettingsGroup()),
          ),
        ),
      );
      await tester.pump();
      return store;
    }

    testWidgets('the switch is there where dictation works, on by default', (
      tester,
    ) async {
      await pumpSettings(tester, supported: true);
      expect(find.text('Show voice input'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatSettingsGroup)),
      );
      expect(container.read(showVoiceInputProvider), isTrue);
      expect(container.read(voiceInputAvailableProvider), isTrue);
    });

    testWidgets('it is not offered where dictation is impossible', (
      tester,
    ) async {
      await pumpSettings(tester, supported: false);
      expect(find.text('Show voice input'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatSettingsGroup)),
      );
      expect(container.read(voiceInputAvailableProvider), isFalse);
    });

    testWidgets('turning it off hides the mode and is remembered', (
      tester,
    ) async {
      final store = await pumpSettings(tester, supported: true);
      await tester.tap(find.byKey(const ValueKey('voice-input-switch')));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatSettingsGroup)),
      );
      expect(container.read(showVoiceInputProvider), isFalse);
      expect(container.read(voiceInputAvailableProvider), isFalse);
      expect(store.show, isFalse);
    });

    testWidgets('a saved choice is picked up', (tester) async {
      await pumpSettings(tester, supported: true, show: false);
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatSettingsGroup)),
      );
      expect(container.read(showVoiceInputProvider), isFalse);
    });
  });
}
