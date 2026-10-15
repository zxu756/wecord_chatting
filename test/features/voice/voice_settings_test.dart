import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/features/voice/voice_settings_screen.dart';

void main() {
  test('settings survive a round trip and clamp volumes', () {
    const settings = VoiceSettings(
      inputMode: VoiceInputMode.pushToTalk,
      pushToTalkKeyId: 0x00000060,
      noiseSuppression: false,
      userVolumes: {'user-2': 1.5},
    );
    expect(VoiceSettings.fromJson(settings.toJson()), settings);
    final loaded = VoiceSettings.fromJson({
      'user_volumes': {'user-2': 7, 'user-3': -1},
    });
    expect(loaded.volumeFor('user-2'), 2);
    expect(loaded.volumeFor('user-3'), 0);
    expect(loaded.volumeFor('user-4'), 1);
    expect(loaded.inputMode, VoiceInputMode.voiceActivity);
    expect(loaded.noiseSuppression, isTrue);
  });

  test('a volume back at 100% is forgotten', () async {
    final store = InMemoryVoiceSettingsStore();
    final container = ProviderContainer(
      overrides: [voiceSettingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final controller = container.read(voiceSettingsProvider.notifier);

    await controller.setUserVolume('user-2', 1.8);
    expect(store.saved!.userVolumes, {'user-2': 1.8});
    await controller.setUserVolume('user-2', 3);
    expect(store.saved!.userVolumes, {'user-2': 2});
    await controller.setUserVolume('user-2', 1);
    expect(store.saved!.userVolumes, isEmpty);
  });

  Future<InMemoryVoiceSettingsStore> pumpScreen(WidgetTester tester) async {
    final store = InMemoryVoiceSettingsStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [voiceSettingsStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: VoiceSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('switches and input mode are saved', (tester) async {
    final store = await pumpScreen(tester);

    await tester.tap(find.byKey(const ValueKey('voice-noise-suppression')));
    await tester.pumpAndSettle();
    expect(store.saved!.noiseSuppression, isFalse);
    await tester.tap(find.byKey(const ValueKey('voice-echo-cancellation')));
    await tester.tap(find.byKey(const ValueKey('voice-auto-gain')));
    await tester.pumpAndSettle();
    expect(store.saved!.echoCancellation, isFalse);
    expect(store.saved!.autoGainControl, isFalse);

    await tester.tap(find.text('Push to talk'));
    await tester.pumpAndSettle();
    expect(store.saved!.inputMode, VoiceInputMode.pushToTalk);
    // Phones hold a button in the voice view instead of a key.
    expect(find.byKey(const ValueKey('voice-push-to-talk-key')), findsNothing);
    expect(
      find.textContaining('Hold the talk button in the voice view'),
      findsOneWidget,
    );
  });

  testWidgets('on desktop a push to talk key is recorded', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final store = await pumpScreen(tester);

    await tester.tap(find.text('Push to talk'));
    await tester.pumpAndSettle();
    expect(find.text('Not set'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-record-key')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-key-recorder')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.backquote);
    await tester.pumpAndSettle();

    expect(store.saved!.pushToTalkKey, LogicalKeyboardKey.backquote);
    expect(find.text('`'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
