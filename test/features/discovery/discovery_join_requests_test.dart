import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/discovery/discovery_screen.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../circles/announcement_channels_test.dart' show RecordingRpc;
import '../circles/join_requests_fakes.dart';
import 'discovery_fakes.dart';

/// Explore, with one public circle (c0) whose join state is [state].
Future<(RecordingRpc, GoRouter)> _pump(
  WidgetTester tester,
  Object? Function(Map<String, dynamic>) state, {
  Object? Function(Map<String, dynamic>)? join,
  Size size = const Size(390, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final rpc = RecordingRpc({
    'list_discoverable_circles': (params) => [discoverableJson('c0')],
    'discoverable_circle_preview': (params) =>
        previewJson(params['target_circle_id'] as String),
    'get_circle_join_state': state,
    'join_public_circle': join ?? (params) => params['target_circle_id'],
    'cancel_join_request': (_) => null,
  });
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
      retry: noProviderRetry,
      overrides: [circleRpcProvider.overrideWithValue(rpc.call)],
      child: MaterialApp.router(
        theme: WeCordTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('discovery-card-c0')).last);
  await tester.pumpAndSettle();
  return (rpc, router);
}

Map<String, dynamic> _state(
  Map<String, dynamic> params, {
  String mode = 'apply',
  Map<String, dynamic>? request,
  String? retryAt,
}) => joinStateJson(
  circleId: params['target_circle_id'] as String,
  mode: mode,
  request: request,
  retryAt: retryAt,
);

void main() {
  testWidgets('a circle that reviews asks its questions, then waits', (
    tester,
  ) async {
    var requested = false;
    final (rpc, router) = await _pump(
      tester,
      (params) => _state(params, request: requested ? requestInfoJson() : null),
      join: (params) {
        requested = true;
        return params['target_circle_id'];
      },
    );

    expect(find.text('Why do you want to join?'), findsOneWidget);
    final send = tester.widget<WeCordButton>(
      find.byKey(const ValueKey('discovery-join')),
    );
    expect(send.label, 'Send request');
    expect(send.onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('join-answer-q1')),
      'I paint pixel art',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('discovery-join')));
    await tester.pumpAndSettle();

    expect(
      rpc.calls.where((call) => call.$1 == 'join_public_circle').single.$2,
      {
        'target_circle_id': 'c0',
        'answers': [
          {'question_id': 'q1', 'answer': 'I paint pixel art'},
        ],
      },
    );
    // A request is not a membership: the preview stays and shows it waiting.
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      DiscoveryScreen.path,
    );
    expect(find.text('Waiting for review'), findsOneWidget);
    expect(
      tester
          .widget<WeCordButton>(find.byKey(const ValueKey('discovery-join')))
          .label,
      'Request sent',
    );
  });

  testWidgets('a waiting request can be withdrawn from the preview', (
    tester,
  ) async {
    var waiting = true;
    final (rpc, _) = await _pump(
      tester,
      (params) => _state(params, request: waiting ? requestInfoJson() : null),
    );
    expect(find.text('Waiting for review'), findsOneWidget);
    waiting = false;
    await tester.tap(find.byKey(const ValueKey('join-cancel-request')));
    await tester.pumpAndSettle();
    expect(
      rpc.calls.where((call) => call.$1 == 'cancel_join_request').single.$2,
      {'target_circle_id': 'c0'},
    );
    expect(find.text('Waiting for review'), findsNothing);
  });

  testWidgets('an invite-only circle cannot be joined from Explore', (
    tester,
  ) async {
    final (rpc, _) = await _pump(
      tester,
      (params) => _state(params, mode: 'invite_only'),
    );
    expect(
      find.text('Ask a member for an invite to join this circle.'),
      findsOneWidget,
    );
    final button = tester.widget<WeCordButton>(
      find.byKey(const ValueKey('discovery-join')),
    );
    expect(button.label, 'Invite only');
    expect(button.onPressed, isNull);
    expect(rpc.calls.any((call) => call.$1 == 'join_public_circle'), isFalse);
  });

  testWidgets('an open circle joins at once, with no extra parameters', (
    tester,
  ) async {
    final (rpc, router) = await _pump(
      tester,
      (params) => _state(params, mode: 'open'),
    );
    expect(find.byKey(const ValueKey('join-questions')), findsNothing);
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
  });

  testWidgets('a refusal says why', (tester) async {
    final (_, _) = await _pump(
      tester,
      (params) => _state(params, mode: 'open'),
      join: (_) => throw Exception('This circle is invite only (42501)'),
    );
    await tester.tap(find.byKey(const ValueKey('discovery-join')));
    await tester.pumpAndSettle();
    expect(find.text('This circle is invite only.'), findsOneWidget);
  });

  testWidgets('a state that cannot be read still lets the person try', (
    tester,
  ) async {
    final (rpc, router) = await _pump(
      tester,
      (_) => throw Exception('offline'),
    );
    expect(find.byKey(const ValueKey('join-questions')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('discovery-join')));
    await tester.pumpAndSettle();
    expect(rpc.calls.any((call) => call.$1 == 'join_public_circle'), isTrue);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/circles/c0',
    );
  });
}
