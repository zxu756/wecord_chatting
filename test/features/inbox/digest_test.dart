import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/ai_settings.dart';
import 'package:wecord/features/inbox/digest/digest_card.dart';
import 'package:wecord/features/inbox/digest/digest_models.dart';
import 'package:wecord/features/inbox/digest/digest_repository.dart';
import 'package:wecord/features/inbox/digest/digest_settings_screen.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';
import '../ai/ai_fakes.dart';
import 'digest_fakes.dart';

void main() {
  group('models', () {
    test('a digest is read from the list function', () {
      final digest = AiDigest.fromJson({
        'id': 'd-1',
        'local_date': '2026-10-19',
        'created_at': '2026-10-19T00:00:03Z',
        'read_at': null,
        'items': [
          {
            'conversation_id': 'c-1',
            'title': 'general',
            'circle_name': 'Hikers',
            'summary': '- One\n\n- Two\n',
            'message_count': 4,
          },
        ],
      });
      expect(digest.isUnread, isTrue);
      expect(digest.items.single.circleName, 'Hikers');
      expect(digest.items.single.bullets, ['One', 'Two']);
      expect(digest.messageCount, 4);
      expect(digestChatLabel(digest.items.single), '#general · Hikers');
      expect(
        digestChatLabel(
          const DigestChatSummary(
            conversationId: 'c-2',
            title: 'Plan',
            summary: '',
          ),
        ),
        'Plan',
      );
    });

    test('settings are read, with the time as hour and minute', () {
      final settings = DigestSettings.fromJson({
        'enabled': false,
        'deliver_at': '06:45',
        'language': 'zh',
        'time_zone': 'Asia/Shanghai',
        'max_subscriptions': 10,
        'subscriptions': [
          {'conversation_id': 'c-1', 'title': 'Plan', 'circle_name': null},
        ],
      });
      expect(settings.enabled, isFalse);
      expect((settings.hour, settings.minute), (6, 45));
      expect(settings.follows('c-1'), isTrue);
      expect(settings.follows('c-2'), isFalse);
      expect(settings.isFull, isFalse);
      expect(DigestSettings.fromJson(const {}).hour, 8);
    });
  });

  group('the card', () {
    Future<void> pumpCard(
      WidgetTester tester,
      AiDigest digest, {
      void Function(String)? onOpenChat,
      VoidCallback? onMarkRead,
    }) async {
      usePhoneViewport(tester, notchedPhone);
      await pumpStandalone(
        tester,
        PhoneWorld(),
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AiDigestCard(
                digest: digest,
                onOpenChat: onOpenChat ?? (_) {},
                onMarkRead: onMarkRead ?? () {},
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('shows each chat with its bullets and count', (tester) async {
      await pumpCard(tester, sampleDigest());

      expect(find.text('Daily digest'), findsOneWidget);
      expect(find.text('2 chats had news'), findsOneWidget);
      expect(find.text('Weekend climbers'), findsOneWidget);
      expect(find.text('#general · Hikers'), findsOneWidget);
      expect(find.text('12 messages'), findsOneWidget);
      expect(find.text('1 message'), findsOneWidget);
      expect(
        find.text('Bart asked who can book the 9am train on Friday'),
        findsOneWidget,
      );
      expect(find.text('The meetup moved to 5pm on Saturday'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('inbox-digest-unread-dot')),
        findsOneWidget,
      );
    });

    testWidgets('a read digest has no dot and no Mark as read', (tester) async {
      await pumpCard(tester, sampleDigest(readAt: DateTime.now()));

      expect(
        find.byKey(const ValueKey('inbox-digest-unread-dot')),
        findsNothing,
      );
      expect(find.text('Mark as read'), findsNothing);
    });

    testWidgets('tapping a chat opens it; Mark as read says so', (
      tester,
    ) async {
      final opened = <String>[];
      var read = 0;
      await pumpCard(
        tester,
        sampleDigest(),
        onOpenChat: opened.add,
        onMarkRead: () => read++,
      );

      await tester.tap(find.byKey(const ValueKey('digest-chat-conv-general')));
      await settle(tester);
      expect(opened, ['conv-general']);

      await tester.tap(find.byKey(const ValueKey('digest-read-digest-1')));
      await settle(tester);
      expect(read, 1);
    });

    testWidgets('a long digest shows three chats and Show all', (tester) async {
      final items = [
        for (var i = 1; i <= 5; i++)
          DigestChatSummary(
            conversationId: 'chat-$i',
            title: 'Chat number $i',
            summary: '- News $i',
            messageCount: i,
          ),
      ];
      await pumpCard(tester, sampleDigest(items: items));

      expect(find.text('Chat number 3'), findsOneWidget);
      expect(find.text('Chat number 4'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('digest-expand-digest-1')));
      await settle(tester);
      expect(find.text('Chat number 5'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);
    });
  });

  group('Notifications', () {
    Future<PhoneWorld> openInbox(
      WidgetTester tester,
      FakeDigestRepository repository,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld()..extraOverrides = digestOverrides(repository);
      await world.open(tester, '/notifications');
      await settle(tester);
      return world;
    }

    Future<void> filter(WidgetTester tester, String name) async {
      final chip = find.byKey(ValueKey('inbox-filter-$name'));
      await tester.ensureVisible(chip);
      await settle(tester);
      await tester.tap(chip);
      await settle(tester);
    }

    testWidgets('the digest is a card, and the Digest chip counts it', (
      tester,
    ) async {
      await openInbox(tester, FakeDigestRepository());

      expect(find.byKey(const ValueKey('inbox-digest-digest-1')), findsOne);
      expect(find.text('Digest 1'), findsOneWidget);
    });

    testWidgets('the Digest chip shows only digests', (tester) async {
      await openInbox(tester, FakeDigestRepository());

      await filter(tester, 'digest');
      expect(find.byKey(const ValueKey('inbox-digest-digest-1')), findsOne);
      expect(find.byKey(const ValueKey('inbox-friend-requests')), findsNothing);
    });

    testWidgets('with no digest the chip says what it is for', (tester) async {
      await openInbox(tester, FakeDigestRepository(digests: []));

      await filter(tester, 'digest');
      expect(
        find.text(
          'Your daily digest shows up here. Set it up in Settings, under AI.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('opening a chat from the card marks the digest read', (
      tester,
    ) async {
      final repository = FakeDigestRepository();
      final world = await openInbox(tester, repository);

      await tester.tap(find.byKey(const ValueKey('digest-chat-group-1')));
      await settle(tester);

      expect(repository.readCalls, [
        ['digest-1'],
      ]);
      expect(world.router.state.uri.path, '/chats/group-1');
    });

    testWidgets('Mark as read clears the dot and the chip count', (
      tester,
    ) async {
      final repository = FakeDigestRepository();
      await openInbox(tester, repository);

      await tester.tap(find.byKey(const ValueKey('digest-read-digest-1')));
      await settle(tester);

      expect(repository.readCalls, [
        ['digest-1'],
      ]);
      expect(
        find.byKey(const ValueKey('inbox-digest-unread-dot')),
        findsNothing,
      );
      expect(find.text('Digest 1'), findsNothing);
      expect(find.text('Digest'), findsOneWidget);
    });

    testWidgets('an unread digest is part of the Notifications badge', (
      tester,
    ) async {
      final repository = FakeDigestRepository();
      await openInbox(tester, repository);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );
      final withDigest = container.read(inboxBadgeCountProvider);
      expect(container.read(aiDigestsUnreadProvider), 1);

      await tester.tap(find.byKey(const ValueKey('digest-read-digest-1')));
      await settle(tester);

      expect(container.read(aiDigestsUnreadProvider), 0);
      expect(container.read(inboxBadgeCountProvider), withDigest - 1);
    });

    testWidgets('digests that cannot be loaded leave the rest of the inbox', (
      tester,
    ) async {
      final repository = FakeDigestRepository()..error = StateError('down');
      await openInbox(tester, repository);

      expect(find.byKey(const ValueKey('inbox-digest-digest-1')), findsNothing);
      expect(find.byKey(const ValueKey('inbox-friend-requests')), findsOne);
    });
  });

  group('Settings -> AI -> Daily digest', () {
    late FakeDigestRepository repository;
    late PhoneWorld world;

    Future<void> openScreen(
      WidgetTester tester, {
      DigestSettings? settings,
    }) async {
      usePhoneViewport(tester, notchedPhone);
      repository = FakeDigestRepository(settings: settings);
      world = PhoneWorld()..extraOverrides = digestOverrides(repository);
      await pumpStandalone(tester, world, const DigestSettingsScreen());
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      final finder = find.byKey(ValueKey(key));
      final list = find.byKey(const ValueKey('settings-page-list'));
      if (list.evaluate().isNotEmpty) {
        await tester.dragUntilVisible(finder, list, const Offset(0, -150));
      }
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await settle(tester);
    }

    bool switchValue(WidgetTester tester, String key) {
      return tester
          .widget<WeCordSwitch>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(WeCordSwitch),
            ),
          )
          .value;
    }

    testWidgets('shows the time, the zone and the chats followed', (
      tester,
    ) async {
      await openScreen(tester);

      expect(find.text('Send me a daily digest'), findsOneWidget);
      expect(find.text('8:00 AM'), findsOneWidget);
      expect(find.text('Asia/Shanghai'), findsOneWidget);
      expect(find.text('Chats you follow (1 of 10)'), findsOneWidget);
      expect(switchValue(tester, 'digest-enabled-switch'), isTrue);
      expect(switchValue(tester, 'digest-follow-group-1'), isTrue);
      // Groups and circle channels can be followed; private chats cannot.
      expect(
        find.byKey(const ValueKey('digest-follow-conv-general')),
        findsOne,
      );
      expect(find.byKey(const ValueKey('digest-follow-dm-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('digest-follow-thread-conv-1')),
        findsNothing,
      );
      expect(switchValue(tester, 'digest-follow-conv-general'), isFalse);
    });

    testWidgets('the switch is saved with the app language', (tester) async {
      await openScreen(tester);

      await tapKey(tester, 'digest-enabled-switch');

      expect(repository.saved.single.enabled, isFalse);
      expect(repository.saved.single.language, 'en');
      expect(switchValue(tester, 'digest-enabled-switch'), isFalse);
    });

    testWidgets('following and unfollowing a chat is saved', (tester) async {
      await openScreen(tester);

      await tapKey(tester, 'digest-follow-conv-general');
      expect(repository.followCalls.single.id, 'conv-general');
      expect(repository.followCalls.single.subscribed, isTrue);
      expect(switchValue(tester, 'digest-follow-conv-general'), isTrue);
      expect(find.text('Chats you follow (2 of 10)'), findsOneWidget);

      await tapKey(tester, 'digest-follow-group-1');
      expect(repository.followCalls.last.subscribed, isFalse);
      expect(find.text('Chats you follow (1 of 10)'), findsOneWidget);
    });

    testWidgets('at the limit the others cannot be followed', (tester) async {
      await openScreen(tester, settings: sampleSettings(max: 1));

      expect(
        find.text(
          'You follow 1 chats, the most you can. Unfollow one to follow another.',
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'digest-follow-conv-general');
      expect(repository.followCalls, isEmpty);
      // The followed one can still be dropped.
      await tapKey(tester, 'digest-follow-group-1');
      expect(repository.followCalls.single.subscribed, isFalse);
    });

    testWidgets('when the server refuses an eleventh chat it says so', (
      tester,
    ) async {
      await openScreen(tester);
      repository.followError = const DigestLimitReached();

      await tapKey(tester, 'digest-follow-conv-general');

      expect(
        find.text('You can follow at most 10 chats. Unfollow one first.'),
        findsOneWidget,
      );
      expect(switchValue(tester, 'digest-follow-conv-general'), isFalse);
    });

    testWidgets('a failed save says so and keeps the old value', (
      tester,
    ) async {
      await openScreen(tester);
      repository.followError = StateError('offline');

      await tapKey(tester, 'digest-follow-conv-general');

      expect(find.text('Could not save. Try again.'), findsOneWidget);
      expect(switchValue(tester, 'digest-follow-conv-general'), isFalse);
    });

    testWidgets('the time is picked and saved', (tester) async {
      await openScreen(tester);

      await tapKey(tester, 'digest-time-row');
      expect(find.text('Deliver the digest at'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await settle(tester);

      expect(repository.saved.single.hour, 8);
      expect(repository.saved.single.minute, 0);
    });

    testWidgets('switched off, the time cannot be changed', (tester) async {
      await openScreen(tester, settings: sampleSettings(enabled: false));

      await tapKey(tester, 'digest-time-row');

      expect(find.text('Deliver the digest at'), findsNothing);
    });

    testWidgets('a settings page that cannot load says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      repository = FakeDigestRepository()..error = StateError('down');
      world = PhoneWorld()..extraOverrides = digestOverrides(repository);
      await pumpStandalone(tester, world, const DigestSettingsScreen());

      expect(find.text('Could not load. Try again.'), findsOneWidget);
    });

    testWidgets('a note says when AI is off in Settings', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      repository = FakeDigestRepository();
      world = PhoneWorld()
        ..extraOverrides = digestOverrides(repository, aiEnabled: false);
      await pumpStandalone(tester, world, const DigestSettingsScreen());

      expect(
        find.text(
          'AI features are off in Settings, so no digest is made until you turn them on.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the row in Settings -> AI opens the page', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      repository = FakeDigestRepository();
      world = PhoneWorld()
        ..extraOverrides = [
          ...digestOverrides(repository),
          aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
        ];
      await pumpStandalone(
        tester,
        world,
        const Scaffold(body: SingleChildScrollView(child: AiSettingsGroup())),
      );

      final row = find.byKey(const ValueKey('digest-settings-tile'));
      expect(row, findsOneWidget);
      expect(find.text('8:00 AM'), findsOneWidget);
      await tester.ensureVisible(row);
      await settle(tester);
      await tester.tap(row);
      await settle(tester);

      expect(find.byKey(const ValueKey('digest-settings-screen')), findsOne);
    });

    testWidgets('the row says Off when nothing is followed', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      repository = FakeDigestRepository(
        settings: sampleSettings(subscriptions: const []),
      );
      world = PhoneWorld()
        ..extraOverrides = [
          ...digestOverrides(repository),
          aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
        ];
      await pumpStandalone(
        tester,
        world,
        const Scaffold(body: SingleChildScrollView(child: AiSettingsGroup())),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('digest-settings-tile')),
          matching: find.text('Off'),
        ),
        findsOneWidget,
      );
    });
  });
}
