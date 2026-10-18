import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/ai_settings.dart';
import 'package:wecord/features/ai/translate_repository.dart';
import 'package:wecord/features/ai/translate_settings.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'ai_fakes.dart';

Widget _scope(FakeAiRepository ai, Widget child, {AiEnabledStore? store}) {
  return ProviderScope(
    overrides: [
      aiRepositoryProvider.overrideWithValue(ai),
      aiEnabledStoreProvider.overrideWithValue(
        store ?? InMemoryAiEnabledStore(),
      ),
    ],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('Settings → AI → Translate to', () {
    testWidgets('follows the app language until one is picked', (tester) async {
      final ai = FakeAiRepository();
      await tester.pumpWidget(_scope(ai, const AiSettingsGroup()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('translate-to-row')), findsOneWidget);
      expect(find.text('App language'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('translate-to-row')));
      await tester.pumpAndSettle();
      // The app language and the six languages.
      expect(find.byKey(const ValueKey('translate-to-app')), findsOneWidget);
      for (final language in AiLanguage.values) {
        expect(
          find.byKey(ValueKey('translate-to-${language.code}')),
          findsOneWidget,
          reason: language.code,
        );
      }

      await tester.tap(find.byKey(const ValueKey('translate-to-ja')));
      await tester.pumpAndSettle();
      expect(ai.savedSettings.last.target, AiLanguage.japanese);
      expect(find.text('Japanese'), findsOneWidget);
    });

    testWidgets('going back to the app language clears the choice', (
      tester,
    ) async {
      final ai = FakeAiRepository()
        ..storedSettings = const AiTranslateSettings(target: AiLanguage.korean);
      await tester.pumpWidget(_scope(ai, const AiSettingsGroup()));
      await tester.pumpAndSettle();
      expect(find.text('Korean'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('translate-to-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('translate-to-app')));
      await tester.pumpAndSettle();
      expect(ai.savedSettings.last.target, isNull);
      expect(find.text('App language'), findsOneWidget);
    });

    testWidgets('the target is the app language, in Chinese too', (
      tester,
    ) async {
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      expect(
        translateTargetOf(const AiTranslateSettings()),
        AiLanguage.chinese,
      );
      expect(
        translateTargetOf(const AiTranslateSettings(target: AiLanguage.french)),
        AiLanguage.french,
      );
    });
  });

  group("Settings → AI → Don't translate", () {
    testWidgets('lists the languages that are left alone', (tester) async {
      final ai = FakeAiRepository()
        ..storedSettings = const AiTranslateSettings(
          noTranslate: {AiLanguage.english, AiLanguage.chinese},
        );
      await tester.pumpWidget(_scope(ai, const AiSettingsGroup()));
      await tester.pumpAndSettle();
      expect(find.text('English, Chinese'), findsOneWidget);
    });

    testWidgets('each language is a switch and the choice is saved', (
      tester,
    ) async {
      final ai = FakeAiRepository();
      await tester.pumpWidget(_scope(ai, const AiSettingsGroup()));
      await tester.pumpAndSettle();
      expect(find.text('None'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('dont-translate-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dont-translate-en')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dont-translate-fr')));
      await tester.pumpAndSettle();
      expect(ai.savedSettings.last.noTranslate, {
        AiLanguage.english,
        AiLanguage.french,
      });
      final english = tester.widget<WeCordSwitch>(
        find.descendant(
          of: find.byKey(const ValueKey('dont-translate-en')),
          matching: find.byType(WeCordSwitch),
        ),
      );
      expect(english.value, isTrue);

      await tester.tap(find.byKey(const ValueKey('dont-translate-en')));
      await tester.pumpAndSettle();
      expect(ai.savedSettings.last.noTranslate, {AiLanguage.french});
    });
  });

  testWidgets('neither row shows when the server has no AI', (tester) async {
    final ai = FakeAiRepository()
      ..statusError = const AiNotConfiguredException();
    await tester.pumpWidget(_scope(ai, const AiSettingsGroup()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('translate-to-row')), findsNothing);
    expect(find.byKey(const ValueKey('dont-translate-row')), findsNothing);
  });

  group('the AI switch is told to the server', () {
    testWidgets('a change is copied, so translations honour it', (
      tester,
    ) async {
      final ai = FakeAiRepository();
      await tester.pumpWidget(_scope(ai, const AiSettingsGroup()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-enabled-switch')));
      await tester.pumpAndSettle();
      expect(ai.syncedEnabled, [false]);
      await tester.tap(find.byKey(const ValueKey('ai-enabled-switch')));
      await tester.pumpAndSettle();
      expect(ai.syncedEnabled, [false, true]);
    });

    testWidgets('a switch saved on this device is copied when the app starts', (
      tester,
    ) async {
      final ai = FakeAiRepository();
      await tester.pumpWidget(
        _scope(
          ai,
          const AiSettingsGroup(),
          store: InMemoryAiEnabledStore(false),
        ),
      );
      await tester.pumpAndSettle();
      expect(ai.syncedEnabled, [false]);
    });
  });

  group('the stored settings', () {
    test('are read once and a choice made meanwhile wins', () async {
      final ai = FakeAiRepository()
        ..storedSettings = const AiTranslateSettings(target: AiLanguage.korean);
      final container = ProviderContainer(
        overrides: [aiRepositoryProvider.overrideWithValue(ai)],
      );
      addTearDown(container.dispose);
      container.listen(aiTranslateSettingsProvider, (_, _) {});
      await container
          .read(aiTranslateSettingsProvider.notifier)
          .setTarget(AiLanguage.french);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        container.read(aiTranslateSettingsProvider).target,
        AiLanguage.french,
      );
    });

    test('the chat choice is read from the server and kept', () async {
      final ai = FakeAiRepository()
        ..conversationPrefs['c1'] = const ConversationTranslatePref(auto: true);
      final container = ProviderContainer(
        overrides: [aiRepositoryProvider.overrideWithValue(ai)],
      );
      addTearDown(container.dispose);
      container.listen(conversationTranslateProvider, (_, _) {});
      final controller = container.read(conversationTranslateProvider.notifier)
        ..ensureLoaded('c1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.of('c1').auto, isTrue);
      await controller.setAuto('c1', on: false);
      expect(ai.savedPrefs.last.$2.auto, isFalse);
      expect(controller.of('c1').auto, isFalse);
    });
  });
}
