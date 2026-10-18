// The daily digest, for the accessibility guard (guidelines_test.dart) and
// the screenshot tool: the digest card in Notifications (unread, long, and
// with nothing yet) and Settings -> AI -> Daily digest (following a few chats,
// switched off, and at the limit of 10).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/inbox/digest/digest_models.dart';
import 'package:wecord/features/inbox/digest/digest_settings_screen.dart';

import '../features/inbox/digest_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// A digest of five chats, each a few bullets: long enough to fold.
AiDigest _longDigest() {
  return sampleDigest(
    items: const [
      DigestChatSummary(
        conversationId: 'group-1',
        title: 'Weekend climbers',
        summary:
            '- Bart asked who can book the 9am train on Friday\n'
            '- Grace will bring snacks; everyone packs a headlamp and water\n'
            '- The trailhead moved to the north lot',
        messageCount: 24,
      ),
      DigestChatSummary(
        conversationId: 'conv-general',
        title: 'general',
        circleName: 'Hikers',
        summary:
            '- The meetup moved to 5pm on Saturday\n'
            '- Omar asked for a lift from the station',
        messageCount: 9,
      ),
      DigestChatSummary(
        conversationId: 'conv-random',
        title: 'off-topic-random-chatter-and-memes-zone',
        circleName: 'Hikers',
        summary: '- Mostly memes; Priya shared a link to the trail map',
        messageCount: 31,
      ),
      DigestChatSummary(
        conversationId: 'chat-4',
        title: 'Book club',
        summary: '- Next month: the short story collection',
        messageCount: 3,
      ),
      DigestChatSummary(
        conversationId: 'chat-5',
        title: 'Flat 4B',
        summary: '- The landlord will visit on Tuesday morning',
        messageCount: 2,
      ),
    ],
  );
}

Future<void> _inbox(
  WidgetTester tester,
  PhoneWorld world,
  FakeDigestRepository repository,
) async {
  world.extraOverrides = digestOverrides(repository);
  await world.open(tester, '/notifications');
  await settle(tester);
}

Future<void> _settings(
  WidgetTester tester,
  PhoneWorld world,
  FakeDigestRepository repository,
) async {
  world.extraOverrides = digestOverrides(repository);
  await pumpStandalone(tester, world, const DigestSettingsScreen());
  await settle(tester);
}

List<DigestSubscription> _following(int count) => [
  for (var i = 0; i < count; i++)
    DigestSubscription(
      conversationId: 'followed-$i',
      title: 'Another chat ${i + 1}',
    ),
];

final digestA11yScreens = <A11yScreen>[
  A11yScreen(
    'digest-inbox',
    (tester, world) => _inbox(tester, world, FakeDigestRepository()),
  ),
  A11yScreen(
    'digest-inbox-desktop',
    (tester, world) => _inbox(tester, world, FakeDigestRepository()),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('digest-inbox-long', (tester, world) async {
    await _inbox(tester, world, FakeDigestRepository(digests: [_longDigest()]));
    final expand = find.byKey(const ValueKey('digest-expand-digest-1'));
    await tester.ensureVisible(expand);
    await settle(tester);
    await tester.tap(expand);
    await settle(tester);
  }),
  A11yScreen('digest-inbox-empty', (tester, world) async {
    await _inbox(tester, world, FakeDigestRepository(digests: []));
    final chip = find.byKey(const ValueKey('inbox-filter-digest'));
    await tester.ensureVisible(chip);
    await settle(tester);
    await tester.tap(chip);
    await settle(tester);
  }),
  A11yScreen(
    'digest-settings',
    (tester, world) => _settings(tester, world, FakeDigestRepository()),
  ),
  A11yScreen(
    'digest-settings-desktop',
    (tester, world) => _settings(tester, world, FakeDigestRepository()),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'digest-settings-off',
    (tester, world) => _settings(
      tester,
      world,
      FakeDigestRepository(
        settings: sampleSettings(enabled: false, subscriptions: const []),
      ),
    ),
  ),
  A11yScreen(
    'digest-settings-full',
    (tester, world) => _settings(
      tester,
      world,
      FakeDigestRepository(
        settings: sampleSettings(subscriptions: _following(10)),
      ),
    ),
  ),
];
