// Care mode (L7), for the accessibility guard (guidelines_test.dart) and the
// accessibility screenshot tool: the main pages with Care mode on (home,
// chats, a chat with its menus, settings), the switch and its options page,
// and the home with only the sizes changed. Text is 1.3x here; the large
// variants run it on top of the phone's own larger text.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_screen.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/care_mode/speech_reader.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/care_mode/care_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

const _careOn = CareModeSettings(enabled: true);

/// Care mode on for this "device", with a voice that does not speak.
SpeechReader _care(PhoneWorld world, [CareModeSettings settings = _careOn]) {
  world.careStore.initial = settings;
  final reader = FakeSpeechReader();
  world.extraOverrides = careVoice(reader);
  return reader;
}

Future<void> _openChat(
  WidgetTester tester,
  PhoneWorld world, {
  CareModeSettings settings = _careOn,
}) async {
  _care(world, settings);
  world.chats.messages = richMessages();
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await scrollIntoView(tester, finder);
  await settle(tester);
}

/// Presses and holds the message with the link, scrolled into view first (at
/// large text on a small phone it starts below the fold).
Future<void> _longPressMessage(WidgetTester tester) async {
  final message = find.textContaining('Also this', findRichText: true).first;
  await tester.ensureVisible(message);
  await settle(tester);
  await tester.longPress(message);
}

/// The screens, in the order of the flows.
final careModeA11yScreens = <A11yScreen>[
  A11yScreen('care-home', (tester, world) async {
    _care(world);
    await world.open(tester, '/home');
  }),
  A11yScreen('care-home-large-text', (tester, world) async {
    _care(world);
    await world.open(tester, '/home');
  }, viewport: notchedPhoneLargeText),
  A11yScreen('care-home-sizes-only', (tester, world) async {
    _care(world, const CareModeSettings(enabled: true, simpleHome: false));
    await world.open(tester, '/home');
  }),
  A11yScreen('care-chats-list', (tester, world) async {
    _care(world);
    await world.open(tester, ChatsScreen.path);
  }),
  A11yScreen('care-direct-thread', (tester, world) async {
    await _openChat(tester, world);
  }),
  A11yScreen('care-direct-thread-large-text', (tester, world) async {
    await _openChat(tester, world);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('care-message-menu', (tester, world) async {
    await _openChat(tester, world);
    await _longPressMessage(tester);
  }),
  A11yScreen('care-reading-aloud', (tester, world) async {
    await _openChat(tester, world);
    await _longPressMessage(tester);
    await settle(tester);
    await tester.tap(find.text(tr('Read aloud')));
  }),
  A11yScreen('care-thread-more-menu', (tester, world) async {
    await _openChat(tester, world);
    await tester.tap(find.byTooltip(tr('More')));
  }),
  A11yScreen('care-composer-menu', (tester, world) async {
    await _openChat(tester, world);
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
  }),
  A11yScreen('care-settings', (tester, world) async {
    _care(world);
    await world.open(tester, '/me');
  }),
  A11yScreen('care-settings-switch', (tester, world) async {
    _care(world);
    await world.open(tester, '/me');
    await _scrollTo(tester, find.byKey(CareModeSettingsGroup.switchKey));
  }),
  A11yScreen('care-settings-switch-off', (tester, world) async {
    await world.open(tester, '/me');
    await _scrollTo(tester, find.byKey(CareModeSettingsGroup.switchKey));
  }),
  A11yScreen('care-options', (tester, world) async {
    _care(world);
    await world.open(tester, '/me');
    await _scrollTo(tester, find.byKey(CareModeSettingsGroup.optionsKey));
    await tester.tap(find.byKey(CareModeSettingsGroup.optionsKey));
    await settle(tester);
  }),
  A11yScreen('care-options-high-contrast', (tester, world) async {
    _care(world, const CareModeSettings(enabled: true, highContrast: true));
    await world.open(tester, '/me');
    await _scrollTo(tester, find.byKey(CareModeSettingsGroup.optionsKey));
    await tester.tap(find.byKey(CareModeSettingsGroup.optionsKey));
    await settle(tester);
  }),
  A11yScreen(
    'care-desktop-appearance',
    (tester, world) async {
      _care(world);
      await world.open(tester, '/me');
      await tester.tap(find.byKey(const ValueKey('settings-nav-appearance')));
      await settle(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'care-desktop-home',
    (tester, world) async {
      _care(world);
      await world.open(tester, '/home');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
