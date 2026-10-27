import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer_registrations.dart';
import 'package:wecord/features/integrations/channel_connections_section.dart';
import 'package:wecord/features/integrations/embed_cards_view.dart';
import 'package:wecord/features/integrations/integrations_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/config/app_config.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message_embeds.dart';

import '../../mobile/phone_test_support.dart';
import 'integrations_fakes.dart';

const _channel = CircleChannel(
  id: 'channel-1',
  circleId: 'circle-1',
  conversationId: 'conv-1',
  name: 'news',
  position: 0,
);

Future<void> _pumpSection(
  WidgetTester tester,
  FakeIntegrationsBackend backend, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backend.override,
        appConfigProvider.overrideWithValue(
          AppConfig(
            supabaseUrl: Uri.parse('https://abc.supabase.co'),
            supabaseAnonKey: 'anon',
          ),
        ),
        ...overrides,
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChannelConnectionsSection(channel: _channel),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

/// Opens a row's menu and taps [action].
Future<void> _menu(WidgetTester tester, String rowKey, String action) async {
  final button = find.descendant(
    of: _key(rowKey),
    matching: find.byIcon(Icons.more_horiz_rounded),
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action).last);
  await tester.pumpAndSettle();
}

void main() {
  group('the repository', () {
    test('reads feeds and connections, never asking for a secret', () {
      final feed = ChannelFeed.fromJson(
        feedJson(failures: 2, lastError: 'http_500'),
      );
      expect(feed.displayName, 'Example Blog');
      expect(feed.hasProblem, isTrue);
      expect(feed.pausedReason, isNull);
      expect(
        ChannelFeed.fromJson(feedJson(title: null)).displayName,
        'blog.example.com',
      );
      final paused = ChannelFeed.fromJson(
        feedJson(enabled: false, pausedReason: 'creator_gone'),
      );
      expect(paused.pausedReason, PausedReason.creatorGone);
      expect(paused.hasProblem, isFalse);

      final hook = GithubHook.fromJson(hookJson());
      expect(hook.events, ['push', 'pull_request']);
      expect(hook.secret, isNull);
      expect(
        hook.payloadUrlFor(Uri.parse('https://abc.supabase.co/')),
        'https://abc.supabase.co/functions/v1/github/hook-1',
      );
      // A row from a newer server with odd values does not break the list.
      expect(PausedReason.fromJson('something_new'), isNull);
      expect(
        GithubHook.fromJson({'id': 'h', 'enabled': 'yes'}).enabled,
        isFalse,
      );
    });

    test('database errors become problems the screen can word', () async {
      final backend = FakeIntegrationsBackend();
      final repository = IntegrationsRepository(backend.call);
      for (final (code, problem) in [
        ('23505', IntegrationProblem.duplicate),
        ('54000', IntegrationProblem.limit),
        ('42501', IntegrationProblem.notAllowed),
        ('22023', IntegrationProblem.invalid),
      ]) {
        backend.failing['add_channel_feed'] = code;
        await expectLater(
          repository.addFeed('channel-1', 'https://a.example.com/rss'),
          throwsA(
            isA<IntegrationException>().having(
              (e) => e.problem,
              'problem',
              problem,
            ),
          ),
        );
      }
      // Something unknown is left as it is.
      backend.failing['add_channel_feed'] = '57014';
      await expectLater(
        repository.addFeed('channel-1', 'https://a.example.com/rss'),
        throwsA(isNot(isA<IntegrationException>())),
      );
    });
  });

  group('channel settings', () {
    testWidgets('lists feeds and connections with how they are doing', (
      tester,
    ) async {
      final backend = FakeIntegrationsBackend(
        feeds: [
          feedJson(),
          feedJson(
            id: 'feed-2',
            url: 'https://news.example.org/rss',
            title: 'News',
            failures: 3,
            lastError: 'http_503',
          ),
          feedJson(
            id: 'feed-3',
            url: 'https://old.example.net/rss',
            title: 'Old',
            enabled: false,
            pausedReason: 'failing',
          ),
        ],
        hooks: [
          hookJson(),
          hookJson(
            id: 'hook-2',
            label: 'wecord/site',
            events: ['release'],
            enabled: false,
            pausedReason: 'creator_lost_access',
          ),
        ],
      );
      await _pumpSection(tester, backend);

      expect(find.text('RSS feeds'), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Example Blog'), findsOneWidget);
      expect(find.text('Waiting for the first read'), findsNothing);
      expect(find.text('Nothing posted yet'), findsOneWidget);
      expect(
        find.text('The site answered with an error (503).'),
        findsOneWidget,
      );
      expect(
        find.text('Paused: it kept failing. Resume to try again.'),
        findsOneWidget,
      );
      expect(find.text('wecord/app'), findsOneWidget);
      expect(
        find.text('Pushes, Pull requests · Nothing received yet'),
        findsOneWidget,
      );
      expect(
        find.text('Paused: the person who added it can no longer post here.'),
        findsOneWidget,
      );
    });

    testWidgets('following a feed checks the address, then asks the server', (
      tester,
    ) async {
      final backend = FakeIntegrationsBackend();
      await _pumpSection(tester, backend);
      expect(find.text('No feeds yet.'), findsOneWidget);

      await _tapKey(tester, 'feed-add-button');
      await tester.enterText(_key('feed-url-field'), 'http://example.com/rss');
      await _tapKey(tester, 'feed-url-submit');
      expect(
        find.text('Use an address that starts with https://.'),
        findsOneWidget,
      );
      expect(backend.callsOf('add_channel_feed'), isEmpty);

      await tester.enterText(
        _key('feed-url-field'),
        '  https://blog.example.com/feed.xml ',
      );
      await _tapKey(tester, 'feed-url-submit');
      expect(backend.callsOf('add_channel_feed'), [
        {
          'target_channel_id': 'channel-1',
          'feed_url': 'https://blog.example.com/feed.xml',
        },
      ]);
      expect(find.text('blog.example.com'), findsOneWidget);
      expect(find.text('Waiting for the first read'), findsOneWidget);
    });

    testWidgets('the server refusing is said in words', (tester) async {
      final backend = FakeIntegrationsBackend();
      await _pumpSection(tester, backend);
      for (final (code, words) in [
        ('23505', 'This channel already follows that feed.'),
        (
          '54000',
          'This circle or channel has all it can have. Remove one first.',
        ),
        ('42501', 'You can no longer manage this channel.'),
        ('22023', 'Could not follow the feed. Try again.'),
        ('57014', 'Could not follow the feed. Try again.'),
      ]) {
        backend.failing['add_channel_feed'] = code;
        await _tapKey(tester, 'feed-add-button');
        await tester.enterText(
          _key('feed-url-field'),
          'https://blog.example.com/feed.xml',
        );
        await _tapKey(tester, 'feed-url-submit');
        expect(find.text(words), findsOneWidget, reason: code);
        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold)),
        ).clearSnackBars();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('a feed can be paused, resumed and dropped', (tester) async {
      final backend = FakeIntegrationsBackend(feeds: [feedJson()]);
      await _pumpSection(tester, backend);

      await _menu(tester, 'feed-feed-1', 'Pause');
      expect(backend.callsOf('set_channel_feed_enabled').last, {
        'target_feed_id': 'feed-1',
        'turn_on': false,
      });
      expect(find.text('Paused'), findsOneWidget);

      await _menu(tester, 'feed-feed-1', 'Resume');
      expect(backend.callsOf('set_channel_feed_enabled').last['turn_on'], true);

      await _menu(tester, 'feed-feed-1', 'Stop following');
      expect(backend.callsOf('remove_channel_feed'), isEmpty);
      await _tapKey(tester, 'integration-confirm');
      expect(backend.callsOf('remove_channel_feed').single, {
        'target_feed_id': 'feed-1',
      });
      expect(find.text('No feeds yet.'), findsOneWidget);
    });

    testWidgets('a connection shows its address and secret once', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final backend = FakeIntegrationsBackend();
      await _pumpSection(tester, backend);

      await _tapKey(tester, 'github-add-button');
      // All events are on to begin with; the name is needed.
      await _tapKey(tester, 'github-name-submit');
      expect(find.text('Name the connection.'), findsOneWidget);
      expect(backend.callsOf('add_github_hook'), isEmpty);

      await tester.enterText(_key('github-name-field'), ' wecord/app ');
      await tester.tap(_key('github-event-issue_comment'));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'github-name-submit');
      expect(backend.callsOf('add_github_hook').single, {
        'target_channel_id': 'channel-1',
        'hook_label': 'wecord/app',
        'event_names': [
          'push',
          'pull_request',
          'issues',
          'release',
          'workflow_run',
        ],
      });

      expect(find.text('GitHub connected'), findsOneWidget);
      expect(
        find.text('https://abc.supabase.co/functions/v1/github/hook-10'),
        findsOneWidget,
      );
      expect(find.text('whs_first_0123456789'), findsOneWidget);
      await tester.tap(_key('github-secret'));
      await tester.pump();
      expect(copied, 'whs_first_0123456789');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Gone for good: the list never carries it.
      expect(find.text('whs_first_0123456789'), findsNothing);
      expect(
        (backend.hooks.single).containsKey('secret'),
        isFalse,
        reason: 'the fake keeps no secret in the list',
      );
      expect(find.text('wecord/app'), findsOneWidget);
    });

    testWidgets('a new secret asks first, then shows once', (tester) async {
      final backend = FakeIntegrationsBackend(hooks: [hookJson()]);
      await _pumpSection(tester, backend);

      await _menu(tester, 'github-hook-1', 'New secret');
      expect(backend.callsOf('regenerate_github_secret'), isEmpty);
      await _tapKey(tester, 'integration-confirm');
      expect(backend.callsOf('regenerate_github_secret').single, {
        'target_hook_id': 'hook-1',
      });
      expect(find.text('whs_second_9876543210'), findsOneWidget);
    });

    testWidgets('events can be changed but not emptied', (tester) async {
      final backend = FakeIntegrationsBackend(hooks: [hookJson()]);
      await _pumpSection(tester, backend);

      await _menu(tester, 'github-hook-1', 'Name and events');
      await tester.tap(_key('github-event-push'));
      await tester.tap(_key('github-event-pull_request'));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'github-name-submit');
      expect(find.text('Choose at least one event.'), findsOneWidget);
      expect(backend.callsOf('update_github_hook'), isEmpty);

      await _tapKey(tester, 'github-event-release');
      await _tapKey(tester, 'github-name-submit');
      expect(backend.callsOf('update_github_hook').single, {
        'target_hook_id': 'hook-1',
        'hook_label': 'wecord/app',
        'event_names': ['release'],
      });
    });

    testWidgets('a connection can be paused and disconnected', (tester) async {
      final backend = FakeIntegrationsBackend(hooks: [hookJson()]);
      await _pumpSection(tester, backend);

      await _menu(tester, 'github-hook-1', 'Pause');
      expect(
        backend.callsOf('set_github_hook_enabled').single['turn_on'],
        false,
      );
      expect(find.text('Paused'), findsOneWidget);

      await _menu(tester, 'github-hook-1', 'Disconnect');
      await _tapKey(tester, 'integration-confirm');
      expect(backend.callsOf('remove_github_hook').single, {
        'target_hook_id': 'hook-1',
      });
      expect(find.text('No repositories yet.'), findsOneWidget);
    });

    testWidgets('a channel at its limit cannot add more', (tester) async {
      final backend = FakeIntegrationsBackend(
        feeds: [
          for (var i = 0; i < maxFeedsPerChannel; i++)
            feedJson(id: 'f$i', url: 'https://s$i.example.com/rss'),
        ],
      );
      await _pumpSection(tester, backend);
      await tester.ensureVisible(_key('feed-add-button'));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'feed-add-button');
      expect(_key('feed-url-field'), findsNothing);
    });
  });

  group('in the chat', () {
    Future<void> openWith(
      WidgetTester tester,
      PhoneWorld world,
      MessageEmbeds? embeds, {
      String body = '[wecord/app] CI failed',
      bool recalled = false,
    }) async {
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
          body,
          minutesAgo: 12,
          conversationId: 'conv-general',
        ).copyWith(
          webhookId: 'webhook-1',
          webhookName: 'wecord/app',
          embeds: embeds,
          recalledAt: recalled ? DateTime.utc(2026, 10, 28, 11) : null,
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
    }

    testWidgets('a message of cards draws them and not its summary text', (
      tester,
    ) async {
      final world = PhoneWorld();
      await openWith(tester, world, ciEmbeds());
      expect(_key('embed-cards'), findsOneWidget);
      // The title is drawn once, by the card: the summary line is hidden.
      expect(find.text('[wecord/app] CI failed'), findsOneWidget);
      expect(find.text('Branch'), findsOneWidget);
      expect(find.text('main'), findsOneWidget);
      expect(find.text('Open run'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('without the summary mark the text stays', (tester) async {
      final world = PhoneWorld();
      await openWith(
        tester,
        world,
        ciEmbeds(summary: false),
        body: 'See the card below',
      );
      expect(find.text('See the card below'), findsOneWidget);
      expect(_key('embed-cards'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a deleted message shows no cards', (tester) async {
      final world = PhoneWorld();
      await openWith(tester, world, ciEmbeds(), recalled: true);
      expect(_key('embed-cards'), findsNothing);
      expect(find.text('Open run'), findsNothing);
      await world.close(tester);
    });

    testWidgets('texts in cards are plain text', (tester) async {
      final world = PhoneWorld();
      await openWith(
        tester,
        world,
        MessageEmbeds.maybeFromJson({
          'cards': [
            {
              'title': '<b>bold</b> **star**',
              'description': '[link](https://evil.example.com)',
            },
          ],
          'summary': true,
        }),
        body: 'x',
      );
      expect(find.text('<b>bold</b> **star**'), findsOneWidget);
      expect(find.text('[link](https://evil.example.com)'), findsOneWidget);
      await world.close(tester);
    });

    test('the registry draws cards inside the bubble', () {
      expect(
        bubbleFooterExtensions.map((entry) => entry.id),
        contains(embedCardsFooterEntry.id),
      );
    });
  });
}
