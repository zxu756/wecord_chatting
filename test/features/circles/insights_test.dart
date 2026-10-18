import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_invite_sheet.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/circles/insights/insights_charts.dart';
import 'package:wecord/features/circles/insights/insights_models.dart';
import 'package:wecord/features/circles/insights/insights_repository.dart';
import 'package:wecord/features/circles/insights/insights_screen.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

import 'ai_guard_fakes.dart';
import 'circle_routes_test.dart'
    show FakeCirclesRepository, FakeContactsRepository;
import 'insights_fakes.dart';
import 'join_requests_fakes.dart';

Widget _app(Widget home, JoinRpc rpc, {ThemeData? theme}) {
  return ProviderScope(
    retry: noProviderRetry,
    overrides: [circleRpcProvider.overrideWithValue(rpc.call)],
    child: MaterialApp(theme: theme ?? WeCordTheme.light(), home: home),
  );
}

void _tall(WidgetTester tester, {Size size = const Size(800, 3600)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('counts', () {
    test('-1 is the server\'s "fewer than 5" and is never drawn as a size', () {
      final hidden = InsightCount.parse(-1);
      expect(hidden.isHidden, isTrue);
      expect(hidden.text, '<5');
      expect(hidden.drawn, 0);
      final shown = InsightCount.parse(12);
      expect(shown.isHidden, isFalse);
      expect(shown.text, '12');
      expect(shown.drawn, 12);
      expect(InsightCount.parse(0).text, '0');
      expect(InsightCount.parse(null).value, 0);
    });

    test('a result parses, hidden counts included', () {
      final insights = CircleInsights.fromJson(insightsJson());
      expect(insights.small, isFalse);
      expect(insights.series, hasLength(30));
      expect(insights.membersNow.value, 55);
      expect(insights.totals.messages.value, 2840);
      expect(insights.heatmap.rows, hasLength(7));
      expect(insights.heatmap.rows.first, hasLength(24));
      // 3 messages in #off-topic arrive as -1.
      expect(insights.channels.last.messages.isHidden, isTrue);
      expect(insights.invites.first.createdByName, 'Bart the Bold');
      expect(insights.invites.last.revoked, isTrue);
      expect(insights.inviters.first.brought.value, 21);
      expect(insights.retention.joinedKept, 0.78);
    });

    test('a small circle has every number hidden and no ratios', () {
      final insights = CircleInsights.fromJson(insightsJson(small: true));
      expect(insights.small, isTrue);
      expect(insights.membersNow.isHidden, isTrue);
      expect(insights.series.every((day) => day.messages.isHidden), isTrue);
      expect(insights.totals.active.isHidden, isTrue);
      expect(insights.heatmap.peak, 0);
      expect(insights.retention.joinedKept, isNull);
      expect(insights.retention.activeReturning, isNull);
    });

    test('the heat map scales to the busiest shown cell', () {
      final heatmap = InsightHeatmap.fromJson({
        'rows': [
          [-1, 0, 7, 12],
        ],
      });
      expect(heatmap.peak, 12);
      expect(heatmap.isEmpty, isFalse);
      expect(InsightHeatmap.fromJson({'rows': []}).isEmpty, isTrue);
    });
  });

  group('the repository', () {
    test('asks for the range in the viewer\'s time zone', () async {
      final rpc = JoinRpc()..answer('get_circle_insights', insightsJson());
      final repository = CircleInsightsRepository(rpc.call);
      final insights = await repository.load(
        'circle-1',
        rangeDays: 7,
        tzOffset: const Duration(hours: 5, minutes: 30),
      );
      expect(insights.series, hasLength(30));
      expect(rpc.paramsOf('get_circle_insights').single, {
        'target_circle_id': 'circle-1',
        'range_days': 7,
        'tz_offset_minutes': 330,
      });
    });

    test('invite stats come by code', () async {
      final rpc = JoinRpc()
        ..answer('get_circle_invite_stats', [
          {'code': 'abcdefgh23', 'brought': 12, 'remaining': 9},
          {'code': 'zyxwvuts98', 'brought': 0, 'remaining': 0},
        ]);
      final stats = await CircleInsightsRepository(
        rpc.call,
      ).inviteStats('circle-1');
      expect(stats['abcdefgh23']!.brought, 12);
      expect(stats['abcdefgh23']!.remaining, 9);
      expect(stats['zyxwvuts98']!.brought, 0);
      expect(rpc.paramsOf('get_circle_invite_stats').single, {
        'target_circle_id': 'circle-1',
      });
    });

    test('manage_circle or view_audit_log opens Insights, others do not', () {
      expect(detail().canViewInsights, isTrue);
      expect(
        detail(
          permissions: CirclePermission.maskOf([
            CirclePermission.viewChannel,
            CirclePermission.viewAuditLog,
          ]),
        ).canViewInsights,
        isTrue,
      );
      expect(
        detail(
          permissions: CirclePermission.maskOf([
            CirclePermission.viewChannel,
            CirclePermission.manageCircle,
          ]),
        ).canViewInsights,
        isTrue,
      );
      expect(
        detail(
          permissions: CirclePermission.maskOf([
            CirclePermission.viewChannel,
            CirclePermission.kickMembers,
            CirclePermission.manageChannels,
            CirclePermission.createInvites,
          ]),
        ).canViewInsights,
        isFalse,
      );
    });
  });

  group('the page', () {
    Future<JoinRpc> open(
      WidgetTester tester, {
      bool small = false,
      ThemeData? theme,
      Map<String, dynamic>? json,
    }) async {
      _tall(tester);
      final rpc = JoinRpc()
        ..answer('get_circle_insights', json ?? insightsJson(small: small));
      await tester.pumpWidget(
        _app(
          const CircleInsightsScreen(circleId: 'circle-1'),
          rpc,
          theme: theme,
        ),
      );
      await tester.pumpAndSettle();
      return rpc;
    }

    testWidgets('shows the numbers, the charts and the rankings', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('55'), findsOneWidget);
      expect(find.byType(MemberLineChart), findsOneWidget);
      expect(find.byType(DailyBarsChart), findsNWidgets(2));
      expect(find.byType(WeekHeatmap), findsOneWidget);
      expect(find.text('# general'), findsOneWidget);
      expect(find.text('# palette-challenges'), findsOneWidget);
      expect(find.text('Link by Bart the Bold'), findsOneWidget);
      expect(find.text('Link by Ada Lovelace'), findsOneWidget);
      expect(find.text('78%'), findsOneWidget);
      expect(find.text('64%'), findsOneWidget);
      // The 4 invites that arrive as -1 ("<5") and the 3 messages in
      // #off-topic are text, never a number.
      expect(find.text('<5'), findsWidgets);
      expect(find.byKey(const ValueKey('insights-small')), findsNothing);
    });

    testWidgets('the range asks the server again', (tester) async {
      final rpc = await open(tester);
      expect(rpc.paramsOf('get_circle_insights').last['range_days'], 30);
      await tester.tap(find.byKey(const ValueKey('insights-range-7')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('get_circle_insights').last['range_days'], 7);
      await tester.tap(find.byKey(const ValueKey('insights-range-90')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('get_circle_insights').last['range_days'], 90);
    });

    testWidgets('a small circle says why every number is hidden', (
      tester,
    ) async {
      await open(tester, small: true);
      expect(find.byKey(const ValueKey('insights-small')), findsOneWidget);
      expect(find.textContaining('at least 5 members'), findsOneWidget);
      expect(find.text('55'), findsNothing);
      expect(find.text('2840'), findsNothing);
      expect(find.text('<5'), findsWidgets);
      // No ratio without enough people.
      expect(find.text('78%'), findsNothing);
      expect(find.text('Not enough people to say yet.'), findsNWidgets(2));
    });

    testWidgets('nobody brought by an invite is said plainly', (tester) async {
      await open(tester, json: insightsJson(withInvites: false));
      expect(
        find.text('No one joined with an invite link in this range.'),
        findsOneWidget,
      );
      expect(
        find.text('No one was brought in by a member in this range.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed load can be tried again', (tester) async {
      _tall(tester);
      final rpc = JoinRpc();
      await tester.pumpWidget(
        _app(const CircleInsightsScreen(circleId: 'circle-1'), rpc),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load insights.'), findsOneWidget);
      rpc.answer('get_circle_insights', insightsJson());
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load insights.'), findsNothing);
      expect(find.text('55'), findsOneWidget);
    });

    testWidgets('reads in Chinese, with Messages as 消息', (tester) async {
      AppStrings.isChinese = true;
      await open(tester);
      expect(find.text('数据'), findsOneWidget);
      expect(find.text('消息'), findsWidgets);
      expect(find.text('私信'), findsNothing);
      expect(find.text('当前成员'), findsOneWidget);
      expect(find.text('7 天'), findsOneWidget);
    });

    for (final (name, theme) in [
      ('light', WeCordTheme.light()),
      ('dark', WeCordTheme.dark()),
    ]) {
      testWidgets('draws in the $name theme without errors', (tester) async {
        await open(tester, theme: theme);
        expect(tester.takeException(), isNull);
        expect(find.byType(CustomPaint), findsWidgets);
      });
    }

    testWidgets('the charts say what they show to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(
        find.bySemanticsLabel(
          RegExp(r'Members went from \d+ to \d+ over 30 days'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'per day, 30 days\. Busiest day')),
        findsNWidgets(2),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Busiest: \w+ at \d+:00')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('the heat map colors', () {
    test('empty is quiet, the busiest is the accent, in every palette', () {
      for (final palette in [
        WeCordPalette.light,
        WeCordPalette.dark,
        WeCordPalette.lightHighContrast,
        WeCordPalette.darkHighContrast,
      ]) {
        expect(heatColor(palette, 0, 10), palette.raised);
        expect(heatColor(palette, 10, 10), palette.accent);
        final middle = heatColor(palette, 3, 10);
        expect(middle, isNot(palette.raised));
        expect(middle, isNot(palette.accent));
      }
    });
  });

  group('the invite list', () {
    testWidgets('each link says how many it brought and how many remain', (
      tester,
    ) async {
      _tall(tester, size: const Size(800, 1600));
      final rpc = JoinRpc()
        ..answer('list_circle_invites_skipping_review', <String>[])
        ..answer('get_circle_invite_stats', [
          {'code': 'abcdefgh23', 'brought': 12, 'remaining': 9},
        ]);
      final repository = FakeCirclesRepository()
        ..invites = [
          CircleInvite(
            code: 'abcdefgh23',
            circleId: 'circle-1',
            createdBy: 'user-1',
            createdAt: DateTime.utc(2026, 10, 20),
            useCount: 12,
          ),
          CircleInvite(
            code: 'zyxwvuts98',
            circleId: 'circle-1',
            createdBy: 'user-1',
            createdAt: DateTime.utc(2026, 10, 20),
            useCount: 0,
          ),
        ];
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: [
            circlesRepositoryProvider.overrideWithValue(repository),
            contactsRepositoryProvider.overrideWithValue(
              FakeContactsRepository(),
            ),
            circleRpcProvider.overrideWithValue(rpc.call),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Scaffold(body: CircleInviteSheet(detail: detail())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Brought 12 · still here 9'), findsOneWidget);
      // A link the stats do not know shows no line rather than a wrong one.
      expect(find.textContaining('Brought'), findsOneWidget);
      expect(
        inviteBroughtText(const InviteStats(brought: 0, remaining: 0)),
        'Brought 0 · still here 0',
      );
      AppStrings.isChinese = true;
      expect(
        inviteBroughtText(const InviteStats(brought: 12, remaining: 9)),
        '带来 12 人 · 仍在 9 人',
      );
    });

    testWidgets('the links still show when the stats cannot be loaded', (
      tester,
    ) async {
      _tall(tester, size: const Size(800, 1600));
      final rpc = JoinRpc()
        ..answer('list_circle_invites_skipping_review', <String>[]);
      final repository = FakeCirclesRepository()
        ..invites = [
          CircleInvite(
            code: 'abcdefgh23',
            circleId: 'circle-1',
            createdBy: 'user-1',
            createdAt: DateTime.utc(2026, 10, 20),
            useCount: 1,
          ),
        ];
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: [
            circlesRepositoryProvider.overrideWithValue(repository),
            contactsRepositoryProvider.overrideWithValue(
              FakeContactsRepository(),
            ),
            circleRpcProvider.overrideWithValue(rpc.call),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Scaffold(body: CircleInviteSheet(detail: detail())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('circle-invite-abcdefgh23')),
        findsOneWidget,
      );
      expect(find.textContaining('Brought'), findsNothing);
    });
  });
}
