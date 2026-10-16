import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/voice/call_links/call_link_screen.dart';
import 'package:wecord/features/voice/call_links/call_link_sheet.dart';
import 'package:wecord/features/voice/call_links/call_links.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'call_links_fakes.dart';
import 'voice_fakes.dart';

void main() {
  group('call link addresses', () {
    test('the link is the site, /call and the code', () {
      expect(
        callLinkUrl('abcd2345efgh', site: 'https://wecord.jokebear.fyi'),
        'https://wecord.jokebear.fyi/call/abcd2345efgh',
      );
      expect(callLinkPath('abcd2345efgh'), '/call/abcd2345efgh');
    });

    test('a pasted link, path or code gives its code', () {
      expect(
        parseCallLinkCode('https://wecord.jokebear.fyi/call/abcd2345efgh'),
        'abcd2345efgh',
      );
      expect(parseCallLinkCode('  /call/ABCD2345EFGH '), 'abcd2345efgh');
      expect(parseCallLinkCode('abcd2345efgh'), 'abcd2345efgh');
      expect(parseCallLinkCode('https://wecord.jokebear.fyi/invite/x'), isNull);
      expect(parseCallLinkCode('/call/short'), isNull);
    });

    test('a browser address finds the page its link stands for', () {
      expect(
        callLinkLocationFor(
          Uri.parse('https://wecord.jokebear.fyi/call/abcd2345efgh'),
        ),
        '/call/abcd2345efgh',
      );
      // Already routed with a #: the router reads that instead.
      expect(
        callLinkLocationFor(
          Uri.parse('https://wecord.jokebear.fyi/call/abcd2345efgh#/home'),
        ),
        isNull,
      );
      expect(
        callLinkLocationFor(Uri.parse('https://wecord.jokebear.fyi/')),
        isNull,
      );
      expect(
        callLinkLocationFor(Uri.parse('https://wecord.jokebear.fyi/call/bad')),
        isNull,
      );
    });

    test('resolutions read the server answer', () {
      final channel = CallLinkResolution.fromJson(const {
        'status': 'ok',
        'kind': 'channel',
        'circle_id': 'circle-1',
        'channel_id': 'ch-lounge',
        'conversation_id': 'conv-lounge',
        'name': 'Lounge',
      });
      expect(channel.isOk, isTrue);
      expect(channel.isChannel, isTrue);
      expect(channel.name, 'Lounge');
      final call = CallLinkResolution.fromJson(const {
        'status': 'ok',
        'kind': 'call',
        'conversation_id': 'dm-bob',
        'name': 'Bob',
      });
      expect(call.isChannel, isFalse);
      expect(call.conversationId, 'dm-bob');
      for (final (status, problem) in [
        ('no_access', CallLinkProblem.noAccess),
        ('expired', CallLinkProblem.expired),
        ('revoked', CallLinkProblem.revoked),
        ('not_found', CallLinkProblem.notFound),
        ('something else', CallLinkProblem.notFound),
      ]) {
        expect(
          CallLinkResolution.fromJson({'status': status}).problem,
          problem,
        );
      }
    });

    test('expiry reads in hours and days', () {
      final now = DateTime.utc(2026, 10, 17, 9);
      expect(callLinkExpiryLabel(null, now: now), 'Never expires');
      expect(
        callLinkExpiryLabel(now.add(const Duration(minutes: 20)), now: now),
        'Expires within the hour',
      );
      expect(
        callLinkExpiryLabel(now.add(const Duration(hours: 5)), now: now),
        'Expires in 5 hours',
      );
      expect(
        callLinkExpiryLabel(now.add(const Duration(hours: 24)), now: now),
        'Expires in 1 day',
      );
      expect(
        callLinkExpiryLabel(
          now.add(const Duration(days: 6, hours: 23)),
          now: now,
        ),
        'Expires in 6 days',
      );
    });
  });

  group('copy call link sheet', () {
    late FakeCallLinksRepository links;
    late String? clipboard;

    setUp(() {
      links = FakeCallLinksRepository();
      clipboard = null;
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Widget sheet(CallLinkTarget target) {
      return ProviderScope(
        overrides: [callLinksRepositoryProvider.overrideWithValue(links)],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: CallLinkSheet(target: target, name: 'Bob'),
          ),
        ),
      );
    }

    testWidgets('creates a link with the chosen expiry and copies it', (
      tester,
    ) async {
      await tester.pumpWidget(
        sheet(const CallLinkTarget.conversation('dm-bob')),
      );
      await tester.pump();

      // A week by default; pick 24 hours.
      await tester.tap(find.byKey(const ValueKey('call-link-expiry-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('call-link-create')));
      await tester.pump();
      await tester.pump();

      expect(links.created, hasLength(1));
      expect(links.created.single.target.conversationId, 'dm-bob');
      expect(links.created.single.expiry, CallLinkExpiry.day);
      final code = links.links.keys.single;
      expect(clipboard, callLinkUrl(code));
      expect(clipboard, endsWith('/call/$code'));
      // The new link is listed and the button says so.
      expect(find.byKey(ValueKey('call-link-$code')), findsOneWidget);
      expect(find.text('Link copied'), findsWidgets);
    });

    testWidgets('a link to a voice channel, with no expiry', (tester) async {
      await tester.pumpWidget(sheet(const CallLinkTarget.channel('ch-lounge')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('call-link-expiry-never')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('call-link-create')));
      await tester.pump();
      await tester.pump();

      expect(links.created.single.target.channelId, 'ch-lounge');
      expect(links.created.single.expiry, CallLinkExpiry.never);
      expect(find.text('Never expires'), findsOneWidget);
    });

    testWidgets('lists earlier links, copies and revokes them', (tester) async {
      const target = CallLinkTarget.conversation('dm-bob');
      final first = await links.create(target, CallLinkExpiry.week);
      await tester.pumpWidget(sheet(target));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(ValueKey('call-link-${first.code}')), findsOneWidget);
      await tester.tap(find.byTooltip('Copy this link'));
      await tester.pump();
      expect(clipboard, callLinkUrl(first.code));

      await tester.tap(find.byKey(ValueKey('call-link-revoke-${first.code}')));
      await tester.pump();
      await tester.pump();

      expect(links.revoked, [first.code]);
      expect(find.byKey(ValueKey('call-link-${first.code}')), findsNothing);
    });

    testWidgets('says so when the link could not be made', (tester) async {
      links.error = StateError('nope');
      await tester.pumpWidget(
        sheet(const CallLinkTarget.conversation('dm-bob')),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('call-link-create')));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Could not create the call link. Try again.'),
        findsOneWidget,
      );
      expect(clipboard, isNull);
    });
  });

  group('opening a call link', () {
    late FakeCallLinksRepository links;
    late FakeVoiceRepository voice;
    late FakeVoiceCallConnector connector;

    setUp(() {
      links = FakeCallLinksRepository();
      voice = FakeVoiceRepository();
      connector = FakeVoiceCallConnector();
    });

    Future<GoRouter> open(WidgetTester tester, String code) async {
      final router = GoRouter(
        initialLocation: callLinkPath(code),
        routes: [
          GoRoute(
            path: '/call/:code',
            builder: (context, state) =>
                CallLinkScreen(code: state.pathParameters['code']!),
          ),
          GoRoute(
            path: '/chats/:id',
            builder: (context, state) =>
                Text('chat ${state.pathParameters['id']}'),
          ),
          GoRoute(
            path: '/circles/:circle/channels/:id',
            builder: (context, state) => Text(
              'channel ${state.pathParameters['circle']}/'
              '${state.pathParameters['id']}',
            ),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => const Text('home'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            callLinksRepositoryProvider.overrideWithValue(links),
            voiceRepositoryProvider.overrideWithValue(voice),
            voiceCallConnectorProvider.overrideWithValue(connector),
            authStateProvider.overrideWith(
              (ref) => Stream.value(const AuthUser(id: 'user-1')),
            ),
          ],
          child: MaterialApp.router(
            theme: WeCordTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return router;
    }

    Future<void> leave(WidgetTester tester) async {
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      await container.read(voiceSessionProvider.notifier).leave();
    }

    testWidgets('joins the call in a chat the user belongs to', (tester) async {
      links.resolutions['abcd2345efgh'] = const CallLinkResolution.call(
        conversationId: 'dm-bob',
        name: 'Bob',
      );
      await open(tester, 'abcd2345efgh');
      await tester.pump();

      expect(links.resolved, ['abcd2345efgh']);
      expect(voice.startedCalls, ['dm-bob']);
      expect(find.text('chat dm-bob'), findsOneWidget);
      expect(connector.calls, hasLength(1));
      await leave(tester);
    });

    testWidgets('joins a voice channel the user may connect to', (
      tester,
    ) async {
      links.resolutions['abcd2345efgh'] = const CallLinkResolution.channel(
        circleId: 'circle-1',
        channelId: 'ch-lounge',
        conversationId: 'conv-lounge',
        name: 'Lounge',
      );
      await open(tester, 'abcd2345efgh');
      await tester.pump();

      expect(voice.tokenRequests, ['ch-lounge']);
      expect(voice.joined, ['ch-lounge']);
      expect(find.text('channel circle-1/conv-lounge'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('shows a friendly page without access', (tester) async {
      links.resolutions['abcd2345efgh'] = const CallLinkResolution.problem(
        CallLinkProblem.noAccess,
      );
      await open(tester, 'abcd2345efgh');

      expect(find.text("You don't have access to this call"), findsOneWidget);
      expect(voice.startedCalls, isEmpty);
      expect(voice.tokenRequests, isEmpty);
      expect(connector.calls, isEmpty);

      await tester.tap(find.byKey(const ValueKey('call-link-home')));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('explains expired, turned off and unknown links', (
      tester,
    ) async {
      for (final (problem, title) in [
        (CallLinkProblem.expired, 'This call link has expired'),
        (CallLinkProblem.revoked, 'This call link was turned off'),
        (CallLinkProblem.notFound, "This call link doesn't exist"),
      ]) {
        links.resolutions['abcd2345efgh'] = CallLinkResolution.problem(problem);
        await open(tester, 'abcd2345efgh');
        expect(find.text(title), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a failed join can be tried again', (tester) async {
      links.resolutions['abcd2345efgh'] = const CallLinkResolution.call(
        conversationId: 'dm-bob',
        name: 'Bob',
      );
      voice.startCallError = const VoiceAccessDeniedException();
      await open(tester, 'abcd2345efgh');
      await tester.pump();

      expect(find.byKey(const ValueKey('call-link-retry')), findsOneWidget);
      expect(find.text('chat dm-bob'), findsNothing);

      voice.startCallError = null;
      await tester.tap(find.byKey(const ValueKey('call-link-retry')));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('chat dm-bob'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('a link that cannot be looked up offers to retry', (
      tester,
    ) async {
      links.error = StateError('offline');
      await open(tester, 'abcd2345efgh');

      expect(find.text('Could not open the call link'), findsOneWidget);
      expect(find.byKey(const ValueKey('call-link-retry')), findsOneWidget);
    });
  });
}
