import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_category_collapse_store.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../circles/circle_detail_screen_test.dart'
    show FakeCirclesRepository, InMemoryCircleCategoryCollapseStore;
import '../circles/circle_routes_test.dart' show FakeContactsRepository;
import 'admin_fakes.dart';

Widget _app(FakeCirclesRepository repository, FakeAdminBackend backend) {
  final router = GoRouter(
    initialLocation: '/circles/circle-1',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/circles/:circleId',
        builder: (context, state) =>
            CircleDetailScreen(circleId: state.pathParameters['circleId']!),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      ...backend.overrides,
      circlesRepositoryProvider.overrideWithValue(repository),
      contactsRepositoryProvider.overrideWithValue(FakeContactsRepository()),
      onlineUserIdsProvider.overrideWith((ref) => Stream.value(<String>{})),
      circleCategoryCollapseStoreProvider.overrideWithValue(
        InMemoryCircleCategoryCollapseStore(),
      ),
      conversationsProvider.overrideWith((ref) async => const []),
    ],
    child: MaterialApp.router(theme: WeCordTheme.light(), routerConfig: router),
  );
}

FakeCirclesRepository _repository() => FakeCirclesRepository()
  ..detailError = const CircleMembershipLostException('circle-1')
  ..circles = [
    const CircleSummary(
      id: 'circle-1',
      name: 'Close Friends',
      memberCount: 2,
      channelCount: 1,
      currentUserRole: 'member',
    ),
  ];

void main() {
  testWidgets('a suspended circle says so, and the member can leave', (
    tester,
  ) async {
    final repository = _repository();
    final backend = FakeAdminBackend()
      ..takedowns = [
        {'circle_id': 'circle-1', 'mode': 'suspend'},
      ];
    await tester.pumpWidget(_app(repository, backend));
    await tester.pumpAndSettle();

    expect(find.text('This circle was suspended'), findsOneWidget);
    expect(find.text("You're no longer a member of this circle"), findsNothing);
    expect(find.byType(CircleRail), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('circle-suspended-leave')));
    await tester.pumpAndSettle();
    // Asked first.
    expect(repository.leftCircleIds, isEmpty);
    await tester.tap(find.text('Leave circle').last);
    await tester.pumpAndSettle();
    expect(repository.leftCircleIds, ['circle-1']);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('a circle that was only delisted is not shown as suspended', (
    tester,
  ) async {
    // A delisted circle still opens, so losing it means losing membership.
    final backend = FakeAdminBackend()
      ..takedowns = [
        {'circle_id': 'circle-1', 'mode': 'delist'},
      ];
    await tester.pumpWidget(_app(_repository(), backend));
    await tester.pumpAndSettle();
    expect(find.text('This circle was suspended'), findsNothing);
    expect(
      find.text("You're no longer a member of this circle"),
      findsOneWidget,
    );
  });

  testWidgets('when the takedown cannot be read the usual state shows', (
    tester,
  ) async {
    final backend = FakeAdminBackend()..failTakedowns = true;
    await tester.pumpWidget(_app(_repository(), backend));
    await tester.pumpAndSettle();
    expect(find.text('This circle was suspended'), findsNothing);
    expect(
      find.text("You're no longer a member of this circle"),
      findsOneWidget,
    );
  });
}
