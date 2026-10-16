import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/discovery/discovery_screen.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../circles/announcement_channels_test.dart' show RecordingRpc;
import 'discovery_fakes.dart';

/// list_discoverable_circles answering [total] circles (ids c0…), sorted by
/// nothing in particular, honouring page_size and page_offset.
Object? Function(Map<String, dynamic>) _pages(
  int total, {
  bool Function(Map<String, dynamic> params)? fail,
  bool memberOfFirst = false,
}) {
  return (params) {
    if (fail?.call(params) ?? false) {
      throw StateError('offline');
    }
    final offset = params['page_offset'] as int;
    final size = params['page_size'] as int;
    final count = (total - offset).clamp(0, size);
    return [
      for (var i = offset; i < offset + count; i++)
        discoverableJson('c$i', isMember: memberOfFirst && i == 0),
    ];
  };
}

Future<GoRouter> _pump(
  WidgetTester tester,
  RecordingRpc rpc, {
  Size size = const Size(390, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: DiscoveryScreen.path,
    routes: [
      GoRoute(
        path: DiscoveryScreen.path,
        builder: (context, state) => const DiscoveryScreen(),
      ),
      GoRoute(
        path: '/circles/:id',
        builder: (context, state) =>
            Scaffold(body: Text('circle ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [circleRpcProvider.overrideWithValue(rpc.call)],
      child: MaterialApp.router(
        theme: WeCordTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

List<Map<String, dynamic>> _listCalls(RecordingRpc rpc) => [
  for (final call in rpc.calls)
    if (call.$1 == 'list_discoverable_circles') call.$2,
];

void main() {
  testWidgets('shows new and popular circles, and filters by category', (
    tester,
  ) async {
    final rpc = RecordingRpc({'list_discoverable_circles': _pages(3)});
    await _pump(tester, rpc);

    expect(find.text('Explore circles'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Popular'), findsOneWidget);
    expect(find.text('Circle c0'), findsWidgets);
    expect(find.text('#pixel'), findsWidgets);
    expect(find.text('10 members'), findsWidgets);
    expect(find.text('2 online'), findsWidgets);
    final calls = _listCalls(rpc);
    expect(
      calls.map((call) => call['sort_by']),
      containsAll(['new', 'popular']),
    );
    expect(calls.every((call) => call['category_filter'] == null), isTrue);

    rpc.calls.clear();
    await tester.tap(find.byKey(const ValueKey('discovery-category-music')));
    await tester.pumpAndSettle();
    final filtered = _listCalls(rpc);
    expect(filtered, isNotEmpty);
    expect(
      filtered.every((call) => call['category_filter'] == 'music'),
      isTrue,
    );
    expect(find.text('Popular in Music'), findsOneWidget);
  });

  testWidgets('searching lists results by relevance, or says none match', (
    tester,
  ) async {
    final rpc = RecordingRpc({
      'list_discoverable_circles': (params) =>
          params['search_query'] == null ? _pages(2)(params) : const [],
    });
    await _pump(tester, rpc);
    rpc.calls.clear();

    await tester.enterText(
      find.byKey(const ValueKey('discovery-search')),
      '像素',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    final call = _listCalls(rpc).single;
    expect(call['search_query'], '像素');
    expect(call['sort_by'], 'relevance');
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('New'), findsNothing);
    expect(find.byKey(const ValueKey('discovery-no-results')), findsOneWidget);
    expect(find.text('No circles match “像素”'), findsOneWidget);
  });

  testWidgets('loads the next page while scrolling', (tester) async {
    final rpc = RecordingRpc({'list_discoverable_circles': _pages(30)});
    await _pump(tester, rpc);
    final popular = _listCalls(
      rpc,
    ).where((call) => call['sort_by'] == 'popular').toList();
    expect(popular.single['page_offset'], 0);

    await tester.scrollUntilVisible(
      find.text("That's everything for now."),
      600,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('discovery-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final offsets = [
      for (final call in _listCalls(rpc))
        if (call['sort_by'] == 'popular') call['page_offset'],
    ];
    expect(offsets, [0, 24]);
    expect(find.text('Circle c29'), findsOneWidget);
  });

  testWidgets('shows empty and error states', (tester) async {
    var fail = true;
    final rpc = RecordingRpc({
      'list_discoverable_circles': _pages(0, fail: (_) => fail),
    });
    await _pump(tester, rpc);
    expect(find.byKey(const ValueKey('discovery-error')), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('discovery-empty')), findsOneWidget);
    expect(find.text('No public circles yet'), findsOneWidget);
  });

  testWidgets('the preview shows rules and channels, and joining opens the '
      'circle', (tester) async {
    final rpc = RecordingRpc({
      'list_discoverable_circles': _pages(1),
      'discoverable_circle_preview': (params) =>
          previewJson(params['target_circle_id'] as String),
      'join_public_circle': (params) => params['target_circle_id'],
    });
    final router = await _pump(tester, rpc);

    await tester.tap(find.byKey(const ValueKey('discovery-card-c0')).last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('discovery-preview-rules')),
      findsOneWidget,
    );
    expect(find.text('Be kind'), findsOneWidget);
    expect(find.text('Lounge'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('discovery-join')));
    await tester.pumpAndSettle();
    expect(
      rpc.calls.where((call) => call.$1 == 'join_public_circle').single.$2,
      {'target_circle_id': 'c0'},
    );
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/circles/c0',
    );
    expect(find.text('circle c0'), findsOneWidget);
  });

  testWidgets('a failed join says why and stays on the preview', (
    tester,
  ) async {
    final rpc = RecordingRpc({
      'list_discoverable_circles': _pages(1),
      'discoverable_circle_preview': (params) =>
          previewJson(params['target_circle_id'] as String),
      'join_public_circle': (_) => throw Exception('Too many (PB429)'),
    });
    await _pump(tester, rpc, size: const Size(1440, 900));

    await tester.tap(find.byKey(const ValueKey('discovery-card-c0')).last);
    await tester.pumpAndSettle();
    // Wide screens show the preview as a centred panel.
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('discovery-join')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('discovery-join-error')), findsOneWidget);
    expect(
      find.text("You've joined a lot of circles. Try again in a while."),
      findsOneWidget,
    );
  });

  testWidgets('joined circles open, banned users cannot join', (tester) async {
    final rpc = RecordingRpc({
      'list_discoverable_circles': _pages(2, memberOfFirst: true),
      'discoverable_circle_preview': (params) {
        final id = params['target_circle_id'] as String;
        return previewJson(id, isMember: id == 'c0', isBanned: id == 'c1');
      },
    });
    final router = await _pump(tester, rpc);
    expect(find.text('Joined'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('discovery-card-c1')).last);
    await tester.pumpAndSettle();
    final banned = tester.widget<Widget>(
      find.byKey(const ValueKey('discovery-banned')),
    );
    expect(banned, isNotNull);
    expect(find.byKey(const ValueKey('discovery-join')), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('discovery-card-c0')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discovery-open')));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/circles/c0',
    );
    expect(rpc.calls.any((call) => call.$1 == 'join_public_circle'), isFalse);
  });

  testWidgets('a circle can be reported from its preview', (tester) async {
    final rpc = RecordingRpc({
      'list_discoverable_circles': _pages(1),
      'discoverable_circle_preview': (params) =>
          previewJson(params['target_circle_id'] as String),
      'report_circle': (_) => 'report-1',
    });
    await _pump(tester, rpc);
    await tester.tap(find.byKey(const ValueKey('discovery-card-c0')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discovery-preview-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report circle'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-reason-harassment')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report-submit')));
    await tester.pumpAndSettle();
    expect(rpc.calls.where((call) => call.$1 == 'report_circle').single.$2, {
      'target_circle_id': 'c0',
      'report_reason': 'harassment',
      'report_details': '',
    });
    expect(find.text('Thanks. We will review this circle.'), findsOneWidget);
  });
}
