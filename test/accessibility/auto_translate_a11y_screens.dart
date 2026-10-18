// Auto-translate (the chat's More menu entry, the translations under
// messages, and Settings → AI "Translate to" / "Don't translate"), for the
// accessibility guard (guidelines_test.dart) and the screenshot tools.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/translate_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/ai/ai_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// A direct chat in a language the reader does not read, with
/// auto-translate [auto] and the AI fake's answers for it.
Future<void> openAutoTranslateThread(
  WidgetTester tester,
  PhoneWorld world, {
  bool auto = true,
  bool limitReached = false,
  bool openMore = false,
  AiTranslateSettings? settings,
}) async {
  final ai = FakeAiRepository()
    ..batchLimitReached = limitReached
    ..translations['m0'] =
        'Shall we have lunch together? I know a new ramen place.'
    ..translations['m2'] = 'At 1 pm. I will be waiting for you there!'
    ..translations['m4'] = 'Looking forward to it, see you soon.'
    ..storedSettings = settings
    ..conversationPrefs['dm-1'] = ConversationTranslatePref(auto: auto);
  world.chats.messages = [
    phoneMessage(
      'm0',
      bart,
      '¿Quedamos para comer? Conozco un sitio nuevo de ramen.',
      minutesAgo: 60,
    ),
    phoneMessage('m1', me, 'Sounds great, what time?', minutesAgo: 55),
    phoneMessage(
      'm2',
      bart,
      'A la una de la tarde, ¡te espero allí!',
      minutesAgo: 50,
    ),
    phoneMessage('m3', bart, '🍜🍜', minutesAgo: 49),
    phoneMessage('m4', bart, '期待见面，一会儿见。', minutesAgo: 10),
  ];
  world.extraOverrides = [
    aiRepositoryProvider.overrideWithValue(ai),
    aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
  ];
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
  // The debounce, the answer, and the stored choice arriving.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  await settle(tester);
  if (openMore) {
    await tester.tap(find.byKey(const ValueKey('chat-header-more')));
    await settle(tester);
  }
}

/// Settings → AI scrolled to the translation rows, with the sheet [sheet]
/// open ('translate-to' or 'dont-translate').
Future<void> openTranslateSettings(
  WidgetTester tester,
  PhoneWorld world, {
  String? sheet,
}) async {
  world.extraOverrides = [
    aiRepositoryProvider.overrideWithValue(
      FakeAiRepository()
        ..storedSettings = const AiTranslateSettings(
          target: AiLanguage.japanese,
          noTranslate: {AiLanguage.english, AiLanguage.chinese},
        ),
    ),
    aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
  ];
  await world.open(tester, '/me');
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('dont-translate-row')),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  // Both rows in view, with the AI switch above them when it fits.
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 160));
  await settle(tester);
  if (sheet != null) {
    await tester.tap(find.byKey(ValueKey('$sheet-row')));
    await settle(tester);
  }
}

final autoTranslateA11yScreens = <A11yScreen>[
  A11yScreen('auto-translate-thread', openAutoTranslateThread),
  A11yScreen(
    'auto-translate-more-menu',
    (tester, world) => openAutoTranslateThread(tester, world, openMore: true),
  ),
  A11yScreen(
    'auto-translate-more-menu-off',
    (tester, world) =>
        openAutoTranslateThread(tester, world, auto: false, openMore: true),
  ),
  A11yScreen(
    'auto-translate-limit',
    (tester, world) =>
        openAutoTranslateThread(tester, world, limitReached: true),
  ),
  A11yScreen(
    'auto-translate-thread-desktop',
    openAutoTranslateThread,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('translate-settings', openTranslateSettings),
  A11yScreen(
    'translate-to-sheet',
    (tester, world) =>
        openTranslateSettings(tester, world, sheet: 'translate-to'),
  ),
  A11yScreen(
    'dont-translate-sheet',
    (tester, world) =>
        openTranslateSettings(tester, world, sheet: 'dont-translate'),
  ),
];
