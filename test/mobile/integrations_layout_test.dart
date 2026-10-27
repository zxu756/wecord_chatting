// Cards, feeds and GitHub connections (I6) on the three phone sizes: the
// small phone, the notched phone and the notched phone with large text.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message_embeds.dart';

import '../features/integrations/integrations_fakes.dart';
import 'phone_test_support.dart';

/// A card with a long title, a long unbroken word, many fields, a picture,
/// a thumbnail and a footer: the worst a feed or a CI can send.
MessageEmbeds wideCards() => MessageEmbeds.maybeFromJson({
  'cards': [
    {
      'title':
          'Pull request opened: #1234 A very long title that has to wrap '
          'onto several lines on a narrow phone',
      'url': 'https://github.com/wecord/app/pull/1234',
      'description':
          'Adds a dark theme.\n\n- tokens\n- screenshots\n'
          '${'Averyveryveryverylongwordwithoutanyspaces' * 3}',
      'color': '#2da44e',
      'author': {'name': 'wecord/app-with-a-long-repository-name'},
      'fields': [
        {
          'name': 'Branches',
          'value': 'feature/dark-mode → main',
          'inline': true,
        },
        {'name': 'Changes', 'value': '+120 −8 in 5 files', 'inline': true},
        {
          'name': 'Reviewers',
          'value': 'Ada, Bart, Grace, Linus',
          'inline': true,
        },
        {'name': 'Notes', 'value': 'Needs a second look at contrast.'},
      ],
      'thumbnail': {'url': 'https://example.com/t.png'},
      'image': {'url': 'https://example.com/chart.png'},
      'footer': {'text': 'opened by ada · 2 minutes ago'},
      'timestamp': '2026-10-28T10:00:00Z',
    },
    ciEmbedsJson()['cards'][0],
  ],
  'components': [
    [
      {
        'type': 'link',
        'label': 'Open pull request',
        'url': 'https://github.com/wecord/app/pull/1234',
      },
      {
        'type': 'link',
        'label': 'Files changed',
        'url': 'https://github.com/wecord/app/pull/1234/files',
      },
    ],
  ],
  'summary': true,
})!;

void main() {
  phoneTestWidgets('cards in a channel fit the screen', (
    tester,
    viewport,
  ) async {
    final world = PhoneWorld();
    world.chats.messages = [
      phoneMessage(
        'wh-0',
        bart,
        'Is the release out yet?',
        minutesAgo: 20,
        conversationId: 'conv-general',
      ),
      phoneMessage(
        'wh-1',
        me,
        'Pull request opened',
        minutesAgo: 12,
        conversationId: 'conv-general',
      ).copyWith(
        webhookId: 'webhook-1',
        webhookName: 'GitHub',
        embeds: wideCards(),
      ),
    ];
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-general',
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
    expect(tester.takeException(), isNull);
    final cards = find.byKey(const ValueKey('embed-cards'));
    expect(cards, findsOneWidget);
    final width = tester.getSize(cards).width;
    expect(width, lessThanOrEqualTo(viewport.size.width));
    final rect = tester.getRect(cards);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(viewport.size.width + 0.5));
    final open = find.text('Open pull request');
    await tester.ensureVisible(open);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expectFullyVisible(tester, open);
  });

  Future<PhoneWorld> openSettings(
    WidgetTester tester,
    FakeIntegrationsBackend backend,
  ) async {
    final world = PhoneWorld()..extraOverrides = [backend.override];
    world.chats.messages = richMessages(withThread: true);
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-general',
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Channel settings'));
    await settle(tester);
    return world;
  }

  phoneTestWidgets('channel settings: feeds and GitHub', (
    tester,
    viewport,
  ) async {
    final backend = FakeIntegrationsBackend(
      feeds: [
        feedJson(
          title: 'The Example Blog With A Rather Long Name Indeed',
          lastItemAt: '2026-10-28T08:00:00Z',
        ),
        feedJson(
          id: 'feed-2',
          url: 'https://news.example.org/rss',
          title: 'News',
          failures: 3,
          lastError: 'http_503',
        ),
      ],
      hooks: [
        hookJson(label: 'wecord/application-with-a-long-repository-name'),
        hookJson(
          id: 'hook-2',
          label: 'wecord/site',
          enabled: false,
          pausedReason: 'creator_lost_access',
        ),
      ],
    );
    await openSettings(tester, backend);

    final addFeed = find.byKey(const ValueKey('feed-add-button'));
    await scrollIntoView(tester, addFeed);
    await tester.ensureVisible(addFeed);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expectFullyVisible(tester, addFeed);
    expectTouchTargets(tester, addFeed);
    for (final key in ['feed-feed-1', 'feed-feed-2']) {
      final row = find.byKey(ValueKey(key));
      await tester.ensureVisible(row);
      await settle(tester);
      expectFullyVisible(tester, row);
    }
    expectTouchTargets(tester, find.byKey(const ValueKey('feed-menu-feed-1')));

    // The address field stays above the keyboard.
    await tester.tap(addFeed);
    await settle(tester);
    final field = find.byKey(const ValueKey('feed-url-field'));
    await tester.enterText(field, 'https://example.com/feed.xml');
    await showKeyboard(tester, viewport);
    expectCaretVisible(tester, field);
    await tester.tap(find.byKey(const ValueKey('feed-url-submit')));
    await settle(tester);
    tester.view.viewInsets = FakeViewPadding.zero;
    await settle(tester);
    expect(backend.callsOf('add_channel_feed'), hasLength(1));

    // The GitHub dialog, then the secret.
    final addHook = find.byKey(const ValueKey('github-add-button'));
    await scrollIntoView(tester, addHook);
    await tester.ensureVisible(addHook);
    await settle(tester);
    expectFullyVisible(tester, addHook);
    await tester.tap(addHook);
    await settle(tester);
    final name = find.byKey(const ValueKey('github-name-field'));
    await tester.enterText(name, 'wecord/app');
    await showKeyboard(tester, viewport);
    expectCaretVisible(tester, name);
    tester.view.viewInsets = FakeViewPadding.zero;
    await settle(tester);
    final submit = find.byKey(const ValueKey('github-name-submit'));
    await tester.ensureVisible(submit);
    await settle(tester);
    expectFullyVisible(tester, submit);
    await tester.tap(submit);
    await settle(tester);

    expect(find.text('GitHub connected'), findsOneWidget);
    for (final key in ['github-payload-url', 'github-secret']) {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expectFullyVisible(tester, finder);
    }
    final done = find.text('Done');
    await tester.ensureVisible(done);
    await settle(tester);
    expectFullyVisible(tester, done);
  });
}
