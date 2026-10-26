import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/developer/bot_directory.dart';
import 'package:wecord/features/developer/bot_events_dialog.dart'
    show defaultBotEvents;
import 'package:wecord/features/developer/developer_bot_screen.dart';
import 'package:wecord/features/developer/developer_repository.dart';
import 'package:wecord/features/developer/developer_screen.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/config/app_config.dart';

import 'developer_fakes.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  FakeDeveloperBackend backend, {
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
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey(key));

/// Scrolls the page until [finder] is built and on screen.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final page = find.descendant(
      of: find.byKey(const ValueKey('settings-page-list')),
      matching: find.byType(Scrollable),
    );
    // Back to the top, then down.
    await tester.drag(page, const Offset(0, 5000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 200, scrollable: page);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// Scrolls the page to [finder] and taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('the repository', () {
    test('reads the bots, their events and the people who found them', () {
      final bot = DeveloperBot.fromJson(
        developerBotJson(
          description: 'Helps',
          allowDirect: true,
          events: eventsJson(enabled: false, dropped: 3),
          callsLastDay: 7,
        ),
      );
      expect(bot.name, 'Helper');
      expect(bot.circleName, 'Hike Club');
      expect(bot.isOpen, isTrue);
      expect(bot.events.isSet, isTrue);
      expect(bot.events.enabled, isFalse);
      expect(bot.events.droppedCount, 3);
      expect(bot.events.events, ['message.created', 'message.mentioned']);
      expect(bot.callsLastDay, 7);

      final quiet = DeveloperBot.fromJson(developerBotJson());
      expect(quiet.events.isSet, isFalse);
      expect(quiet.isOpen, isFalse);

      final open = OpenBot.fromJson(openBotJson());
      expect(open.allowDirect, isTrue);
      expect(open.allowGroups, isTrue);

      final delivery = BotEventDelivery.fromJson({
        'id': 'd1',
        'event': 'message.created',
        'state': 'queued',
        'attempts': 1,
        'created_at': '2026-10-28T09:00:00Z',
      });
      expect(delivery.isWaiting, isTrue);
      expect(delivery.isDelivered, isFalse);
      expect(
        BotApiCall.fromJson({
          'at': '2026-10-28T09:00:00Z',
          'method': 'GET',
          'route': '/me',
          'status': 404,
        }).succeeded,
        isFalse,
      );
    });

    test('sends what the database functions expect', () async {
      final backend = FakeDeveloperBackend();
      final repository = DeveloperRepository(backend.call);
      expect(await repository.hasAccess(), isTrue);
      final saved = await repository.setSubscription(
        'bot-1',
        url: ' https://bots.example.com/events ',
        events: ['message.created'],
      );
      expect(saved.secret, 'sec_first_0123456789');
      expect(backend.callsOf('set_bot_event_subscription').single, {
        'target_bot_id': 'bot-1',
        'event_url': 'https://bots.example.com/events',
        'event_names': ['message.created'],
      });
      await repository.setAvailability(
        'bot-1',
        description: '  Hi  ',
        direct: true,
        groups: false,
      );
      expect(backend.callsOf('set_bot_availability').single, {
        'target_bot_id': 'bot-1',
        'bot_description': 'Hi',
        'direct_chats': true,
        'group_chats': false,
      });
      await repository.addBotToGroup('chat-1', 'bot-user-1');
      expect(backend.callsOf('add_bot_to_group').single, {
        'target_conversation_id': 'chat-1',
        'target_bot_user_id': 'bot-user-1',
      });
    });
  });

  group('the Settings entry', () {
    testWidgets('is there for people who manage a circle', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: DeveloperSettingsGroup()),
        FakeDeveloperBackend(),
      );
      expect(_key('developer-tile'), findsOneWidget);
    });

    testWidgets('is not there for anyone else', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: DeveloperSettingsGroup()),
        FakeDeveloperBackend(access: false),
      );
      expect(_key('developer-tile'), findsNothing);
    });

    testWidgets('stays hidden when the answer cannot be had', (tester) async {
      final backend = FakeDeveloperBackend()
        ..failing.add('my_developer_access');
      await _pump(
        tester,
        const Scaffold(body: DeveloperSettingsGroup()),
        backend,
      );
      expect(_key('developer-tile'), findsNothing);
    });

    testWidgets('opens the developer page', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: DeveloperSettingsGroup()),
        FakeDeveloperBackend(),
      );
      await tester.tap(_key('developer-tile'));
      await tester.pumpAndSettle();
      expect(find.text('Your bots'), findsOneWidget);
    });
  });

  group('the developer page', () {
    testWidgets('lists the bots with how they are doing', (tester) async {
      final backend = FakeDeveloperBackend(
        bots: [
          developerBotJson(events: eventsJson(), callsLastDay: 12),
          developerBotJson(
            id: 'bot-2',
            name: 'Quiet',
            hasToken: false,
            circleName: 'Chess',
          ),
        ],
      );
      await _pump(tester, const DeveloperScreen(), backend);
      expect(find.text('Helper'), findsOneWidget);
      expect(
        find.text('Hike Club · Events: on · 12 calls in the last day'),
        findsOneWidget,
      );
      expect(
        find.text('Chess · Token revoked · 0 calls in the last day'),
        findsOneWidget,
      );
    });

    testWidgets('says when there are no bots', (tester) async {
      await _pump(
        tester,
        const DeveloperScreen(),
        FakeDeveloperBackend(bots: []),
      );
      expect(_key('developer-no-bots'), findsOneWidget);
    });

    testWidgets('says when there is no access', (tester) async {
      await _pump(
        tester,
        const DeveloperScreen(),
        FakeDeveloperBackend(access: false, bots: []),
      );
      expect(_key('developer-no-access'), findsOneWidget);
      expect(_key('developer-no-bots'), findsNothing);
    });

    testWidgets('says when the bots cannot be loaded, and tries again', (
      tester,
    ) async {
      final backend = FakeDeveloperBackend()
        ..failing.add('list_my_developer_bots');
      await _pump(tester, const DeveloperScreen(), backend);
      expect(_key('developer-bots-error'), findsOneWidget);
      backend.failing.clear();
      await tester.tap(_key('developer-bots-error'));
      await tester.pumpAndSettle();
      expect(find.text('Helper'), findsOneWidget);
    });

    testWidgets('opens the documentation', (tester) async {
      final opened = <Uri>[];
      await _pump(
        tester,
        const DeveloperScreen(),
        FakeDeveloperBackend(),
        overrides: [
          developerDocsLauncherProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
      );
      await tester.tap(_key('developer-docs'));
      await tester.pump();
      expect(opened.single.path, '/developers/');
    });

    testWidgets('opens a bot', (tester) async {
      await _pump(tester, const DeveloperScreen(), FakeDeveloperBackend());
      await tester.tap(_key('developer-bot-bot-1'));
      await tester.pumpAndSettle();
      expect(_key('developer-event-address'), findsOneWidget);
    });
  });

  group('a bot', () {
    testWidgets('sets an event address and shows the secret once', (
      tester,
    ) async {
      final backend = FakeDeveloperBackend();
      await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);
      expect(
        find.text('Not set. The bot can still ask for things by polling.'),
        findsOneWidget,
      );
      await _tap(tester, _key('developer-event-address'));
      await tester.enterText(
        _key('bot-events-field'),
        'https://bots.example.com/events',
      );
      await tester.pumpAndSettle();
      // The kinds a new address starts with are on; turn one more on.
      await _tap(tester, _key('bot-event-reaction.added'));
      await _tap(tester, _key('bot-events-save'));

      expect(backend.callsOf('set_bot_event_subscription').single, {
        'target_bot_id': 'bot-1',
        'event_url': 'https://bots.example.com/events',
        'event_names': [
          'message.created',
          'message.mentioned',
          'reaction.added',
          'interaction.created',
        ],
      });
      expect(find.text('sec_first_0123456789'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('https://bots.example.com/events'),
        findsWidgets,
      );
      expect(find.textContaining('Events: on'), findsOneWidget);
    });

    testWidgets('refuses an address that is not https', (tester) async {
      final backend = FakeDeveloperBackend();
      await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);
      await _tap(tester, _key('developer-event-address'));
      await tester.enterText(_key('bot-events-field'), 'http://example.com');
      await tester.pumpAndSettle();
      await _tap(tester, _key('bot-events-save'));
      expect(
        find.text('The address must start with https://', skipOffstage: false),
        findsOneWidget,
      );
      expect(backend.callsOf('set_bot_event_subscription'), isEmpty);
    });

    testWidgets('needs at least one kind of event', (tester) async {
      final backend = FakeDeveloperBackend();
      await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);
      await _tap(tester, _key('developer-event-address'));
      await tester.enterText(
        _key('bot-events-field'),
        'https://bots.example.com/events',
      );
      await tester.pumpAndSettle();
      for (final name in defaultBotEvents) {
        await _tap(tester, _key('bot-event-$name'));
      }
      await _tap(tester, _key('bot-events-save'));
      expect(find.text('Choose at least one kind of event.'), findsOneWidget);
      expect(backend.callsOf('set_bot_event_subscription'), isEmpty);
    });

    testWidgets('can try again when the address was not accepted', (
      tester,
    ) async {
      final backend = FakeDeveloperBackend()
        ..failing.add('set_bot_event_subscription');
      await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);
      await _tap(tester, _key('developer-event-address'));
      await tester.enterText(
        _key('bot-events-field'),
        'https://bots.example.com/events',
      );
      await tester.pumpAndSettle();
      await _tap(tester, _key('bot-events-save'));
      expect(
        find.text('Could not save the event address. Try again.'),
        findsOneWidget,
      );
      // The dialog came back with what was typed.
      expect(_key('bot-events-field'), findsOneWidget);
      expect(find.text('https://bots.example.com/events'), findsOneWidget);
    });

    testWidgets(
      'sends a test event, resets the secret and removes the address',
      (tester) async {
        final backend = FakeDeveloperBackend(
          bots: [developerBotJson(events: eventsJson())],
        );
        await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);

        await _tap(tester, _key('developer-test-event'));
        expect(backend.callsOf('send_bot_test_event'), hasLength(1));
        expect(find.text('A test event is on its way.'), findsOneWidget);

        await _tap(tester, _key('developer-rotate-event-secret'));
        await _tap(tester, _key('developer-confirm'));
        expect(find.text('sec_second_9876543210'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        await _tap(tester, _key('developer-clear-events'));
        await _tap(tester, _key('developer-confirm'));
        expect(backend.callsOf('clear_bot_event_subscription'), hasLength(1));
        expect(
          find.text('Not set. The bot can still ask for things by polling.'),
          findsOneWidget,
        );
        expect(_key('developer-test-event'), findsNothing);
      },
    );

    testWidgets('says a paused address is paused', (tester) async {
      final backend = FakeDeveloperBackend(
        bots: [developerBotJson(events: eventsJson(enabled: false))],
      );
      await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);
      expect(find.textContaining('Events: paused'), findsOneWidget);
      expect(find.textContaining('Paused: too many events'), findsOneWidget);
      expect(_key('developer-test-event'), findsNothing);
    });

    testWidgets('lists the latest events and API calls', (tester) async {
      final backend = FakeDeveloperBackend(
        bots: [developerBotJson(events: eventsJson())],
        deliveries: [
          {
            'id': 'd1',
            'event': 'message.created',
            'state': 'delivered',
            'attempts': 1,
            'status': 200,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
          {
            'id': 'd2',
            'event': 'reaction.added',
            'state': 'failed',
            'attempts': 5,
            'status': 500,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
        apiCalls: [
          {
            'at': DateTime.now().toUtc().toIso8601String(),
            'method': 'GET',
            'route': '/chats/{id}/messages',
            'status': 200,
          },
          {
            'at': DateTime.now().toUtc().toIso8601String(),
            'method': 'POST',
            'route': '/chats/{id}/messages',
            'status': 429,
          },
        ],
      );
      await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);
      await _reveal(tester, _key('developer-delivery-d2'));
      expect(find.text('message.created'), findsOneWidget);
      expect(find.text('Delivered · Just now'), findsOneWidget);
      expect(find.text('Failed · HTTP 500 · Just now'), findsOneWidget);
      await _reveal(tester, _key('developer-call-1'));
      expect(find.text('GET /chats/{id}/messages'), findsOneWidget);
      expect(find.text('429'), findsOneWidget);
    });

    testWidgets('says when nothing happened yet', (tester) async {
      final backend = FakeDeveloperBackend(
        bots: [developerBotJson(events: eventsJson())],
      );
      await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);
      await _reveal(tester, _key('developer-no-calls'));
      expect(_key('developer-no-deliveries'), findsOneWidget);
      expect(_key('developer-no-calls'), findsOneWidget);
    });

    testWidgets('does not ask for the events list of a bot without events', (
      tester,
    ) async {
      final backend = FakeDeveloperBackend();
      await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);
      expect(backend.callsOf('list_bot_event_deliveries'), isEmpty);
    });

    testWidgets('opens and closes it to direct chats and groups', (
      tester,
    ) async {
      final backend = FakeDeveloperBackend();
      await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);
      await _tap(tester, _key('developer-allow-direct'));
      expect(
        backend.callsOf('set_bot_availability').last['direct_chats'],
        true,
      );
      expect(
        backend.callsOf('set_bot_availability').last['group_chats'],
        false,
      );
      await _tap(tester, _key('developer-allow-groups'));
      expect(
        backend.callsOf('set_bot_availability').last['direct_chats'],
        true,
      );
      expect(backend.callsOf('set_bot_availability').last['group_chats'], true);
      await _tap(tester, _key('developer-allow-direct'));
      expect(
        backend.callsOf('set_bot_availability').last['direct_chats'],
        false,
      );
    });

    testWidgets('keeps a description', (tester) async {
      final backend = FakeDeveloperBackend();
      await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);
      await _tap(tester, _key('developer-description'));
      await tester.enterText(
        _key('developer-description-field'),
        '  Plans hikes  ',
      );
      await tester.tap(_key('developer-description-save'));
      await tester.pumpAndSettle();
      expect(
        backend.callsOf('set_bot_availability').single['bot_description'],
        'Plans hikes',
      );
      expect(find.text('Plans hikes'), findsOneWidget);
    });

    testWidgets('resets the token and shows it once', (tester) async {
      final backend = FakeDeveloperBackend();
      await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);
      expect(
        find.text('https://abc.supabase.co/functions/v1/bot-api'),
        findsOneWidget,
      );
      await _tap(tester, _key('developer-reset-token'));
      await _tap(tester, _key('developer-confirm'));
      expect(find.text('wcb_new_token_value'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(backend.callsOf('regenerate_bot_token'), hasLength(1));
    });

    testWidgets('revokes the token', (tester) async {
      final backend = FakeDeveloperBackend();
      await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);
      await _tap(tester, _key('developer-revoke-token'));
      await _tap(tester, _key('developer-confirm'));
      expect(backend.callsOf('revoke_bot_token'), hasLength(1));
      expect(_key('developer-revoke-token'), findsNothing);
      final note = find.text('Token revoked. Make a new one to use the bot.');
      await _reveal(tester, note);
      expect(note, findsOneWidget);
    });

    testWidgets('cancelling a question changes nothing', (tester) async {
      final backend = FakeDeveloperBackend();
      await _pump(tester, const DeveloperBotScreen(botId: 'bot-1'), backend);
      await _tap(tester, _key('developer-revoke-token'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.callsOf('revoke_bot_token'), isEmpty);
    });

    testWidgets('says so when the bot is gone', (tester) async {
      await _pump(
        tester,
        const DeveloperBotScreen(botId: 'nobody'),
        FakeDeveloperBackend(),
      );
      expect(_key('developer-bot-missing'), findsOneWidget);
    });
  });

  group('finding a bot', () {
    Future<void> search(WidgetTester tester, String text) async {
      await tester.enterText(_key('find-bot-field'), text);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    testWidgets('asks for two letters first', (tester) async {
      final backend = FakeDeveloperBackend();
      await _pump(tester, const FindBotScreen(), backend);
      await search(tester, 'T');
      expect(backend.callsOf('search_open_bots'), isEmpty);
      expect(find.textContaining('at least 2 letters'), findsOneWidget);
    });

    testWidgets('shows the bots that match, with a Message button', (
      tester,
    ) async {
      final backend = FakeDeveloperBackend(
        openBots: [
          openBotJson(),
          openBotJson(
            userId: 'bot-user-2',
            name: 'Trail Mapper',
            description: null,
            allowDirect: false,
          ),
        ],
      );
      await _pump(tester, const FindBotScreen(), backend);
      await search(tester, 'trail');
      expect(backend.callsOf('search_open_bots').single, {
        'search_text': 'trail',
      });
      expect(find.text('Trail Guide'), findsOneWidget);
      expect(find.text('Trail Mapper'), findsOneWidget);
      expect(
        find.text('Answers questions about hikes and weather.'),
        findsOneWidget,
      );
      // Only the bot that takes direct chats can be messaged.
      expect(_key('find-bot-action-bot-user-1'), findsOneWidget);
      expect(_key('find-bot-action-bot-user-2'), findsNothing);
    });

    testWidgets('says when nothing matches', (tester) async {
      await _pump(tester, const FindBotScreen(), FakeDeveloperBackend());
      await search(tester, 'zzz');
      expect(_key('find-bot-empty'), findsOneWidget);
    });

    testWidgets('says when the search failed, and searches again', (
      tester,
    ) async {
      final backend = FakeDeveloperBackend()..failing.add('search_open_bots');
      await _pump(tester, const FindBotScreen(), backend);
      await search(tester, 'trail');
      expect(_key('find-bot-error'), findsOneWidget);
      backend.failing.clear();
      await tester.tap(_key('find-bot-error'));
      await tester.pumpAndSettle();
      expect(find.text('Trail Guide'), findsOneWidget);
    });

    testWidgets('adds the chosen bot to a group', (tester) async {
      final backend = FakeDeveloperBackend();
      await _pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openFindBot(context, addToChatId: 'chat-1'),
              child: const Text('open'),
            ),
          ),
        ),
        backend,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await search(tester, 'trail');
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('Message'), findsNothing);
      await tester.tap(_key('find-bot-action-bot-user-1'));
      await tester.pumpAndSettle();
      expect(backend.callsOf('add_bot_to_group').single, {
        'target_conversation_id': 'chat-1',
        'target_bot_user_id': 'bot-user-1',
      });
      // The search closes once the bot is in.
      expect(_key('find-bot-field'), findsNothing);
    });

    testWidgets('says why a bot could not be added', (tester) async {
      final backend = FakeDeveloperBackend()..failing.add('add_bot_to_group');
      await _pump(tester, const FindBotScreen(addToChatId: 'chat-1'), backend);
      await search(tester, 'trail');
      await tester.tap(_key('find-bot-action-bot-user-1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not add the bot.'), findsOneWidget);
      expect(_key('find-bot-field'), findsOneWidget);
    });
  });

  group('the bots of a group', () {
    testWidgets('the row is hidden when a member has nothing to see', (
      tester,
    ) async {
      await _pump(
        tester,
        const Scaffold(body: GroupBotsRow(chatId: 'chat-1', isOwner: false)),
        FakeDeveloperBackend(),
      );
      expect(_key('group-detail-bots'), findsNothing);
    });

    testWidgets('the owner can always open it', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: GroupBotsRow(chatId: 'chat-1', isOwner: true)),
        FakeDeveloperBackend(),
      );
      expect(find.text('Add a bot to this group'), findsOneWidget);
    });

    testWidgets('members see which bots are in', (tester) async {
      final backend = FakeDeveloperBackend(groupBots: [openBotJson()]);
      await _pump(
        tester,
        const Scaffold(body: GroupBotsRow(chatId: 'chat-1', isOwner: false)),
        backend,
      );
      expect(find.text('Trail Guide'), findsOneWidget);
      await tester.tap(_key('group-detail-bots'));
      await tester.pumpAndSettle();
      expect(_key('group-bot-bot-user-1'), findsOneWidget);
      // Members cannot change it.
      expect(_key('group-bot-add'), findsNothing);
      expect(_key('group-bot-remove-bot-user-1'), findsNothing);
    });

    testWidgets('the owner removes a bot', (tester) async {
      final backend = FakeDeveloperBackend(groupBots: [openBotJson()]);
      await _pump(
        tester,
        const GroupBotsScreen(chatId: 'chat-1', isOwner: true),
        backend,
      );
      await tester.tap(_key('group-bot-remove-bot-user-1'));
      await tester.pumpAndSettle();
      await tester.tap(_key('group-bot-remove-confirm'));
      await tester.pumpAndSettle();
      expect(backend.callsOf('remove_bot_from_group').single, {
        'target_conversation_id': 'chat-1',
        'target_bot_user_id': 'bot-user-1',
      });
      expect(_key('group-bot-bot-user-1'), findsNothing);
      expect(_key('group-bot-add'), findsOneWidget);
    });

    testWidgets('a member sees there are none', (tester) async {
      await _pump(
        tester,
        const GroupBotsScreen(chatId: 'chat-1', isOwner: false),
        FakeDeveloperBackend(),
      );
      expect(find.text('No bots in this group.'), findsOneWidget);
    });
  });
}
