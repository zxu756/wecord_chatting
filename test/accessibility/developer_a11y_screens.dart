// The developer page, event subscriptions and the bots of a group (I2, I3), for
// the accessibility guard (guidelines_test.dart) and the screenshot tools: the
// page with a developer's bots, one bot (token, events, availability, latest
// events and calls), the event address dialog and its one-time secret, the
// description dialog, the bot search and the bots of a group - at large text,
// narrow, with Care mode on and on the desktop.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/developer/bot_directory.dart';
import 'package:wecord/features/developer/developer_bot_screen.dart';
import 'package:wecord/features/developer/developer_screen.dart';

import '../features/developer/developer_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

final _ago = DateTime.now().toUtc().subtract(const Duration(minutes: 5));

List<Map<String, dynamic>> _deliveries() => [
  {
    'id': 'd1',
    'event': 'message.created',
    'state': 'delivered',
    'attempts': 1,
    'status': 200,
    'created_at': _ago.toIso8601String(),
  },
  {
    'id': 'd2',
    'event': 'interaction.created',
    'state': 'failed',
    'attempts': 5,
    'status': 500,
    'created_at': _ago.toIso8601String(),
  },
  {
    'id': 'd3',
    'event': 'reaction.added',
    'state': 'queued',
    'attempts': 0,
    'created_at': _ago.toIso8601String(),
  },
];

List<Map<String, dynamic>> _calls() => [
  {
    'at': _ago.toIso8601String(),
    'method': 'GET',
    'route': '/chats/{id}/messages',
    'status': 200,
  },
  {
    'at': _ago.toIso8601String(),
    'method': 'POST',
    'route': '/chats/{id}/messages',
    'status': 429,
  },
  {
    'at': _ago.toIso8601String(),
    'method': 'POST',
    'route': '/chats/{id}/files',
    'status': 201,
  },
];

FakeDeveloperBackend _backend({
  bool paused = false,
  bool noBots = false,
  bool quiet = false,
}) {
  return FakeDeveloperBackend(
    bots: noBots
        ? []
        : [
            developerBotJson(
              description: 'Plans hikes and answers questions about the trail.',
              allowDirect: true,
              events: quiet ? null : eventsJson(enabled: !paused, dropped: 4),
              callsLastDay: 128,
            ),
            developerBotJson(
              id: 'bot-2',
              name: 'Weather Watcher',
              circleName: 'Hike Club',
              events: eventsJson(),
              callsLastDay: 3,
            ),
            developerBotJson(
              id: 'bot-3',
              name: 'Old Helper',
              circleName: 'Chess Night',
              hasToken: false,
            ),
          ],
    deliveries: quiet ? [] : _deliveries(),
    apiCalls: quiet ? [] : _calls(),
    openBots: [
      openBotJson(),
      openBotJson(
        userId: 'bot-user-2',
        name: 'Trail Mapper',
        description:
            'Draws a map of the route you describe and shares the file in the chat.',
      ),
      openBotJson(
        userId: 'bot-user-3',
        name: 'Trail Quiet',
        description: null,
        allowDirect: false,
      ),
    ],
    groupBots: [
      openBotJson(),
      openBotJson(userId: 'bot-user-2', name: 'Trail Mapper'),
    ],
  );
}

Future<FakeDeveloperBackend> _open(
  WidgetTester tester,
  PhoneWorld world,
  Widget screen, {
  FakeDeveloperBackend? backend,
  bool care = false,
}) async {
  if (care) {
    world.careStore.initial = const CareModeSettings(enabled: true);
  }
  final fake = backend ?? _backend();
  await pumpStandalone(tester, world, screen, extraOverrides: [fake.override]);
  await settle(tester);
  return fake;
}

Future<void> _openBot(
  WidgetTester tester,
  PhoneWorld world, {
  bool paused = false,
  bool quiet = false,
  bool care = false,
}) async {
  await _open(
    tester,
    world,
    const DeveloperBotScreen(botId: 'bot-1'),
    backend: _backend(paused: paused, quiet: quiet),
    care: care,
  );
}

/// Scrolls to the widget with [key] (the page or a dialog) and taps it.
Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await scrollIntoView(tester, finder);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> _eventsDialog(
  WidgetTester tester,
  PhoneWorld world, {
  bool existing = false,
}) async {
  await _openBot(tester, world, quiet: !existing);
  await _tapKey(tester, 'developer-event-address');
}

Future<void> _secretDialog(WidgetTester tester, PhoneWorld world) async {
  await _eventsDialog(tester, world);
  await tester.enterText(
    find.byKey(const ValueKey('bot-events-field')),
    'https://bots.example.com/wecord/events',
  );
  await settle(tester);
  await _tapKey(tester, 'bot-events-save');
}

Future<void> _descriptionDialog(WidgetTester tester, PhoneWorld world) async {
  await _openBot(tester, world);
  await _tapKey(tester, 'developer-description');
}

Future<void> _search(
  WidgetTester tester,
  PhoneWorld world, {
  String? addToChatId,
  String text = 'trail',
}) async {
  await _open(tester, world, FindBotScreen(addToChatId: addToChatId));
  await tester.enterText(find.byKey(const ValueKey('find-bot-field')), text);
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

Future<void> _groupBots(
  WidgetTester tester,
  PhoneWorld world, {
  bool owner = true,
}) async {
  await _open(tester, world, GroupBotsScreen(chatId: 'chat-1', isOwner: owner));
}

final developerA11yScreens = <A11yScreen>[
  A11yScreen('developer-page', (tester, world) async {
    await _open(tester, world, const DeveloperScreen());
  }),
  A11yScreen('developer-page-large-text', (tester, world) async {
    await _open(tester, world, const DeveloperScreen());
  }, viewport: notchedPhoneLargeText),
  A11yScreen('developer-page-narrow', (tester, world) async {
    await _open(tester, world, const DeveloperScreen());
  }, viewport: smallPhone),
  A11yScreen('developer-page-care-mode', (tester, world) async {
    await _open(tester, world, const DeveloperScreen(), care: true);
  }),
  A11yScreen('developer-page-empty', (tester, world) async {
    await _open(
      tester,
      world,
      const DeveloperScreen(),
      backend: _backend(noBots: true),
    );
  }),
  A11yScreen('developer-bot', (tester, world) async {
    await _openBot(tester, world);
  }),
  A11yScreen('developer-bot-large-text', (tester, world) async {
    await _openBot(tester, world);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('developer-bot-narrow', (tester, world) async {
    await _openBot(tester, world);
  }, viewport: smallPhone),
  A11yScreen('developer-bot-care-mode', (tester, world) async {
    await _openBot(tester, world, care: true);
  }),
  A11yScreen('developer-bot-paused', (tester, world) async {
    await _openBot(tester, world, paused: true);
  }),
  A11yScreen('developer-bot-no-events', (tester, world) async {
    await _openBot(tester, world, quiet: true);
  }),
  A11yScreen('developer-bot-bottom', (tester, world) async {
    await _openBot(tester, world);
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('developer-call-2')),
    );
  }),
  A11yScreen('developer-bot-bottom-large-text', (tester, world) async {
    await _openBot(tester, world);
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('developer-call-2')),
    );
  }, viewport: notchedPhoneLargeText),
  A11yScreen('developer-events-dialog', (tester, world) async {
    await _eventsDialog(tester, world);
  }),
  A11yScreen('developer-events-dialog-large-text', (tester, world) async {
    await _eventsDialog(tester, world);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('developer-events-dialog-narrow', (tester, world) async {
    await _eventsDialog(tester, world, existing: true);
  }, viewport: smallPhone),
  A11yScreen('developer-events-dialog-error', (tester, world) async {
    await _eventsDialog(tester, world);
    await tester.enterText(
      find.byKey(const ValueKey('bot-events-field')),
      'http://bots.example.com',
    );
    await settle(tester);
    await _tapKey(tester, 'bot-events-save');
  }),
  A11yScreen('developer-event-secret', _secretDialog),
  A11yScreen(
    'developer-event-secret-large-text',
    _secretDialog,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('developer-description-dialog', _descriptionDialog),
  A11yScreen(
    'developer-description-dialog-narrow',
    _descriptionDialog,
    viewport: smallPhone,
  ),
  A11yScreen('find-bot', _search),
  A11yScreen('find-bot-large-text', _search, viewport: notchedPhoneLargeText),
  A11yScreen('find-bot-narrow', _search, viewport: smallPhone),
  A11yScreen('find-bot-care-mode', (tester, world) async {
    world.careStore.initial = const CareModeSettings(enabled: true);
    await _search(tester, world);
  }),
  A11yScreen('find-bot-empty', (tester, world) async {
    await _search(tester, world, text: 'zzz');
  }),
  A11yScreen('find-bot-add-to-group', (tester, world) async {
    await _search(tester, world, addToChatId: 'chat-1');
  }),
  A11yScreen('group-bots', _groupBots),
  A11yScreen(
    'group-bots-large-text',
    _groupBots,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('group-bots-narrow', _groupBots, viewport: smallPhone),
  A11yScreen('group-bots-member', (tester, world) async {
    await _groupBots(tester, world, owner: false);
  }),
  A11yScreen(
    'desktop-developer-page',
    (tester, world) async {
      await _open(tester, world, const DeveloperScreen());
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-developer-bot',
    (tester, world) async {
      await _openBot(tester, world);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-developer-events-dialog',
    (tester, world) async {
      await _eventsDialog(tester, world, existing: true);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
