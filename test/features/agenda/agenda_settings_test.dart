import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/agenda/calendar_feed_repository.dart';

import '../../mobile/phone_test_support.dart';
import 'agenda_fakes.dart';

void main() {
  final supabase = Uri.parse('https://wecordproject.supabase.co');
  final token1 = '1'.padLeft(48, 'a');
  final token2 = '2'.padLeft(48, 'a');

  group('the link', () {
    test('is the feed function address with the secret and .ics', () {
      expect(
        calendarFeedUrl(supabase, token1).toString(),
        'https://wecordproject.supabase.co/functions/v1/calendar-feed/$token1.ics',
      );
      expect(
        calendarFeedUrl(
          Uri.parse('https://wecordproject.supabase.co/'),
          token1,
        ).path,
        '/functions/v1/calendar-feed/$token1.ics',
      );
      expect(
        calendarFeedSubscribeUrl(calendarFeedUrl(supabase, token1)).scheme,
        'webcal',
      );
    });

    test('settings come from the server row', () {
      final settings = CalendarFeedSettings.fromJson({
        'enabled': true,
        'include_content': true,
        'created_at': '2026-10-18T10:00:00+00:00',
        'last_used_at': null,
      });
      expect(settings.enabled, isTrue);
      expect(settings.includeContent, isTrue);
      expect(settings.createdAt, DateTime.utc(2026, 10, 18, 10));
      expect(settings.lastUsedAt, isNull);
      expect(
        CalendarFeedSettings.fromJson({
          'enabled': false,
          'include_content': false,
        }).enabled,
        isFalse,
      );
    });
  });

  group('settings page', () {
    late List<MethodCall> clipboard;

    Future<PhoneWorld> open(
      WidgetTester tester, {
      FakeCalendarFeedRepository? feed,
      InMemoryCalendarFeedTokenStore? tokens,
    }) async {
      usePhoneViewport(tester, notchedPhone);
      clipboard = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          clipboard.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final world = PhoneWorld()
        ..extraOverrides = agendaOverrides(feed: feed, tokens: tokens);
      await world.open(tester, '/me');
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('agenda-settings-tile')),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('settings-page-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('agenda-settings-tile')));
      await settle(tester);
      return world;
    }

    testWidgets('is a row in Settings', (tester) async {
      await open(tester);
      expect(
        find.byKey(const ValueKey('agenda-settings-screen')),
        findsOneWidget,
      );
      expect(find.text('Calendar subscription'), findsWidgets);
    });

    testWidgets('makes a link, keeps it on the device and shows it', (
      tester,
    ) async {
      final feed = FakeCalendarFeedRepository();
      final tokens = InMemoryCalendarFeedTokenStore();
      await open(tester, feed: feed, tokens: tokens);

      // Nothing yet: the explanation and the button.
      expect(find.byKey(const ValueKey('agenda-create-link')), findsOneWidget);
      expect(find.byKey(const ValueKey('agenda-link')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('agenda-create-link')));
      await settle(tester);

      expect(feed.tokens, [token1]);
      // Titles stay out until the person asks for them; the zone and the
      // language travel with the request, for the feed has no one to ask.
      expect(feed.options.single.includeContent, isFalse);
      expect(
        feed.options.single.offset,
        DateTime.now().timeZoneOffset.inMinutes,
      );
      expect(feed.options.single.language, 'en');
      expect(tokens.tokens['user-1'], token1);
      expect(
        tester
            .widget<SelectableText>(find.byKey(const ValueKey('agenda-link')))
            .data,
        'https://wecordproject.supabase.co/functions/v1/calendar-feed/$token1.ics',
      );
      expect(find.byKey(const ValueKey('agenda-create-link')), findsNothing);
    });

    testWidgets('copies the link', (tester) async {
      await open(
        tester,
        feed: FakeCalendarFeedRepository(enabled: true),
        tokens: InMemoryCalendarFeedTokenStore({'user-1': token1}),
      );
      await tester.tap(find.byKey(const ValueKey('agenda-copy-link')));
      await settle(tester);

      final set = clipboard.singleWhere(
        (call) => call.method == 'Clipboard.setData',
      );
      expect(
        (set.arguments as Map)['text'],
        'https://wecordproject.supabase.co/functions/v1/calendar-feed/$token1.ics',
      );
      expect(
        find.text('Link copied. Paste it into your calendar app.'),
        findsOneWidget,
      );
    });

    testWidgets('Add to calendar opens the webcal address', (tester) async {
      final world = await open(
        tester,
        feed: FakeCalendarFeedRepository(enabled: true),
        tokens: InMemoryCalendarFeedTokenStore({'user-1': token1}),
      );
      await tester.tap(find.byKey(const ValueKey('agenda-subscribe')));
      await settle(tester);
      expect(world.openedLinks.single.toString(), startsWith('webcal://'));
      expect(world.openedLinks.single.path, endsWith('$token1.ics'));
    });

    testWidgets('the content switch is off by default and saves', (
      tester,
    ) async {
      final feed = FakeCalendarFeedRepository(enabled: true);
      await open(
        tester,
        feed: feed,
        tokens: InMemoryCalendarFeedTokenStore({'user-1': token1}),
      );
      expect(
        find.textContaining('shows only the time and the name'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('agenda-include-content')));
      await settle(tester);
      expect(feed.includeContent, isTrue);
      expect(feed.options.single.includeContent, isTrue);
      expect(
        find.textContaining('shows titles, places and details'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('agenda-include-content')));
      await settle(tester);
      expect(feed.includeContent, isFalse);
    });

    testWidgets('a reset asks first, then makes a new link', (tester) async {
      final feed = FakeCalendarFeedRepository(enabled: true)
        ..tokens.add(token1);
      final tokens = InMemoryCalendarFeedTokenStore({'user-1': token1});
      await open(tester, feed: feed, tokens: tokens);

      await tester.drag(
        find.byKey(const ValueKey('settings-page-list')),
        const Offset(0, -200),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('agenda-reset-link')));
      await settle(tester);
      expect(find.text('Reset the link?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(feed.tokens, [token1]);

      await tester.tap(find.byKey(const ValueKey('agenda-reset-link')));
      await settle(tester);
      await tester.tap(find.text('Reset link').last);
      await settle(tester);

      expect(feed.tokens, [token1, token2]);
      expect(tokens.tokens['user-1'], token2);
      expect(
        tester
            .widget<SelectableText>(find.byKey(const ValueKey('agenda-link')))
            .data,
        endsWith('$token2.ics'),
      );
      expect(find.text('New link made. The old one is off.'), findsOneWidget);
    });

    testWidgets('turning it off asks, then forgets the link', (tester) async {
      final feed = FakeCalendarFeedRepository(enabled: true);
      final tokens = InMemoryCalendarFeedTokenStore({'user-1': token1});
      await open(tester, feed: feed, tokens: tokens);

      await tester.drag(
        find.byKey(const ValueKey('settings-page-list')),
        const Offset(0, -200),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('agenda-turn-off')));
      await settle(tester);
      expect(find.text('Turn off the subscription?'), findsOneWidget);
      await tester.tap(find.text('Turn off').last);
      await settle(tester);

      expect(feed.deleted, 1);
      expect(tokens.tokens, isEmpty);
      expect(find.byKey(const ValueKey('agenda-create-link')), findsOneWidget);
    });

    testWidgets('a link made on another device offers a reset only', (
      tester,
    ) async {
      await open(tester, feed: FakeCalendarFeedRepository(enabled: true));
      expect(
        find.byKey(const ValueKey('agenda-link-elsewhere')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('agenda-link')), findsNothing);
      expect(find.byKey(const ValueKey('agenda-copy-link')), findsNothing);
      expect(find.byKey(const ValueKey('agenda-reset-link')), findsOneWidget);
    });

    testWidgets('says when a calendar app last fetched it', (tester) async {
      await open(
        tester,
        feed: FakeCalendarFeedRepository(enabled: true),
        tokens: InMemoryCalendarFeedTokenStore({'user-1': token1}),
      );
      expect(find.text('No calendar app has fetched it yet.'), findsOneWidget);
    });

    testWidgets('a failure is said, not swallowed', (tester) async {
      final feed = FakeCalendarFeedRepository()
        ..failWith = Exception('offline');
      await open(tester, feed: feed);
      await tester.tap(find.byKey(const ValueKey('agenda-create-link')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('agenda-settings-error')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('agenda-create-link')), findsOneWidget);
    });
  });
}
