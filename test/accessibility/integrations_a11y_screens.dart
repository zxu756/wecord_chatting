// Cards, RSS feeds and GitHub connections (I6), for the accessibility guard
// (guidelines_test.dart) and the screenshot tools: a channel message made of
// cards (a CI failure, a pull request with a picture and link buttons), and
// the channel settings sections for feeds and GitHub - normal, large text,
// narrow, Care mode - with the address dialog, the connection dialog, the
// secret shown once and the paused and failing states.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message_embeds.dart';

import '../features/integrations/integrations_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

const _route = '/circles/circle-1/channels/conv-general';
const _extra = ChatThreadRouteExtra(
  title: '# general',
  type: ConversationType.channel,
  circleId: 'circle-1',
);

/// A pull request card with a picture, fields and link buttons.
MessageEmbeds _pullRequestCards() => MessageEmbeds.maybeFromJson({
  'cards': [
    {
      'title': '[wecord/app] Pull request opened: #12 Add dark mode',
      'url': 'https://github.com/wecord/app/pull/12',
      'description': 'Adds a dark theme.\n\n- tokens\n- screenshots',
      'color': '#2da44e',
      'author': {'name': 'wecord/app', 'url': 'https://github.com/wecord/app'},
      'fields': [
        {'name': 'Branches', 'value': 'dark → main', 'inline': true},
        {'name': 'Changes', 'value': '+120 −8 in 5 files', 'inline': true},
      ],
      'footer': {'text': 'ada'},
      'timestamp': '2026-10-28T10:00:00Z',
    },
  ],
  'components': [
    [
      {
        'type': 'link',
        'label': 'Open pull request',
        'url': 'https://github.com/wecord/app/pull/12',
      },
    ],
  ],
  'summary': true,
})!;

Future<void> _openCards(
  WidgetTester tester,
  PhoneWorld world, {
  bool care = false,
  bool both = true,
}) async {
  if (care) {
    _care(world);
  }
  world.chats.messages = [
    phoneMessage(
      'wh-0',
      bart,
      'Is the release out yet?',
      minutesAgo: 30,
      conversationId: 'conv-general',
    ),
    phoneMessage(
      'wh-1',
      me,
      '[wecord/app] CI failed',
      minutesAgo: 14,
      conversationId: 'conv-general',
    ).copyWith(
      webhookId: 'webhook-1',
      webhookName: 'GitHub',
      embeds: ciEmbeds(),
    ),
    if (both)
      phoneMessage(
        'wh-2',
        me,
        '[wecord/app] Pull request opened: #12 Add dark mode',
        minutesAgo: 8,
        conversationId: 'conv-general',
      ).copyWith(
        webhookId: 'webhook-1',
        webhookName: 'GitHub',
        embeds: _pullRequestCards(),
      ),
  ];
  await world.open(tester, _route, extra: _extra);
}

FakeIntegrationsBackend _backend({bool empty = false}) {
  if (empty) {
    return FakeIntegrationsBackend();
  }
  return FakeIntegrationsBackend(
    feeds: [
      feedJson(
        title: 'The Example Blog',
        lastItemAt: DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 3))
            .toIso8601String(),
      ),
      feedJson(
        id: 'feed-2',
        url: 'https://news.example.org/rss',
        title: 'News from the neighbourhood',
        failures: 3,
        lastError: 'http_503',
      ),
      feedJson(
        id: 'feed-3',
        url: 'https://old.example.net/rss',
        title: 'Old posts',
        enabled: false,
        pausedReason: 'failing',
      ),
    ],
    hooks: [
      hookJson(
        events: const ['push', 'pull_request', 'issues'],
        lastDeliveryAt: DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 20))
            .toIso8601String(),
      ),
      hookJson(
        id: 'hook-2',
        label: 'wecord/site',
        events: const ['release'],
        enabled: false,
        pausedReason: 'creator_lost_access',
      ),
    ],
  );
}

Future<FakeIntegrationsBackend> _openSettings(
  WidgetTester tester,
  PhoneWorld world, {
  bool care = false,
  bool empty = false,
}) async {
  if (care) {
    _care(world);
  }
  final backend = _backend(empty: empty);
  world.extraOverrides = [backend.override];
  world.chats.messages = richMessages(withThread: true);
  await world.open(tester, _route, extra: _extra);
  await tester.tap(find.byTooltip('More'));
  await settle(tester);
  await tester.tap(find.text('Channel settings'));
  await settle(tester);
  await scrollIntoView(tester, find.byKey(const ValueKey('feed-add-button')));
  await tester.ensureVisible(find.byKey(const ValueKey('feed-add-button')));
  await settle(tester);
  return backend;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> _feedDialog(WidgetTester tester, PhoneWorld world) async {
  await _openSettings(tester, world);
  await _tapKey(tester, 'feed-add-button');
}

Future<void> _feedDialogError(WidgetTester tester, PhoneWorld world) async {
  await _feedDialog(tester, world);
  await tester.enterText(
    find.byKey(const ValueKey('feed-url-field')),
    'http://example.com/rss',
  );
  await _tapKey(tester, 'feed-url-submit');
}

Future<void> _hookDialog(WidgetTester tester, PhoneWorld world) async {
  await _openSettings(tester, world);
  await _tapKey(tester, 'github-add-button');
}

Future<void> _secretDialog(WidgetTester tester, PhoneWorld world) async {
  await _hookDialog(tester, world);
  await tester.enterText(
    find.byKey(const ValueKey('github-name-field')),
    'wecord/app',
  );
  await _tapKey(tester, 'github-name-submit');
}

Future<void> _hookMenu(WidgetTester tester, PhoneWorld world) async {
  await _openSettings(tester, world);
  await _tapKey(tester, 'github-menu-hook-1');
}

final integrationsA11yScreens = <A11yScreen>[
  A11yScreen('embed-cards', (tester, world) async {
    await _openCards(tester, world);
  }),
  A11yScreen('embed-cards-large-text', (tester, world) async {
    await _openCards(tester, world, both: false);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('embed-cards-narrow', (tester, world) async {
    await _openCards(tester, world);
  }, viewport: smallPhone),
  A11yScreen('embed-cards-care-mode', (tester, world) async {
    await _openCards(tester, world, care: true);
  }),
  A11yScreen('channel-feeds-github', (tester, world) async {
    await _openSettings(tester, world);
  }),
  A11yScreen('channel-feeds-github-large-text', (tester, world) async {
    await _openSettings(tester, world);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('channel-feeds-github-narrow', (tester, world) async {
    await _openSettings(tester, world);
  }, viewport: smallPhone),
  A11yScreen('channel-feeds-github-care-mode', (tester, world) async {
    await _openSettings(tester, world, care: true);
  }),
  A11yScreen('channel-feeds-github-empty', (tester, world) async {
    await _openSettings(tester, world, empty: true);
  }),
  A11yScreen('feed-address-dialog', _feedDialog),
  A11yScreen(
    'feed-address-dialog-large-text',
    _feedDialog,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('feed-address-dialog-error', _feedDialogError),
  A11yScreen('github-dialog', _hookDialog),
  A11yScreen(
    'github-dialog-large-text',
    _hookDialog,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('github-dialog-narrow', _hookDialog, viewport: smallPhone),
  A11yScreen('github-secret-dialog', _secretDialog),
  A11yScreen(
    'github-secret-dialog-large-text',
    _secretDialog,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'github-secret-dialog-narrow',
    _secretDialog,
    viewport: smallPhone,
  ),
  A11yScreen('github-connection-menu', _hookMenu),
];
