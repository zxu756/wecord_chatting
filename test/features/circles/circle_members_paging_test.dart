import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_members_source.dart';
import 'package:wecord/features/circles/circle_workspace.dart';
import 'package:wecord/features/member_honors/honor_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/profile/profile_extras_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/features/member_honors/honor_models.dart';

Map<String, dynamic> _member(int n) => {
  'role': n == 1 ? 'owner' : 'member',
  'is_current_user': n == 1,
  'role_ids': const <String>[],
  'profile': {
    'id': 'user-$n',
    'username': 'user$n',
    'display_name': 'Member $n',
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
  },
};

CircleDetail _detail({required int members, required int total}) {
  return CircleDetail.fromJson({
    'circle': {
      'id': 'circle-1',
      'name': 'Big Circle',
      'member_count': total,
      'channel_count': 1,
      'current_user_role': 'owner',
    },
    'members': [for (var n = 1; n <= members; n++) _member(n)],
    'channels': const [],
    'posts': const [],
    'roles': const [],
  });
}

class _FakeSource implements CircleMembersSource {
  final pages = <CircleMembersCursor?>[];
  final searches = <String>[];

  @override
  Future<CircleMembersPage> page(
    String circleId, {
    CircleMembersCursor? after,
    int pageSize = 100,
  }) async {
    pages.add(after);
    return CircleMembersPage(members: [CircleMember.fromJson(_member(900))]);
  }

  @override
  Future<List<CircleMember>> search(
    String circleId,
    String query, {
    int limit = 50,
  }) async {
    searches.add(query);
    return [CircleMember.fromJson(_member(777))];
  }
}

Future<_FakeSource> _pump(WidgetTester tester, CircleDetail detail) async {
  final source = _FakeSource();
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        circleMembersSourceProvider.overrideWithValue(source),
        presenceStatusesProvider.overrideWith((ref) => Stream.value({})),
        circleMemberAvatarsProvider(
          detail.circle.id,
        ).overrideWith((ref) async => {}),
        circleMemberFlairProvider(
          detail.circle.id,
        ).overrideWith((ref) async => <String, MemberFlair>{}),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CircleMemberList(
            detail: detail,
            onlineUserIds: const {},
            onChangeNickname: (_) {},
            width: null,
            compact: false,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return source;
}

void main() {
  test('a circle is partial only when the server cut the list', () {
    expect(_detail(members: 3, total: 3).hasMoreMembers, isFalse);
    // Tests and older servers: a count that disagrees with a short list.
    expect(_detail(members: 3, total: 40).hasMoreMembers, isFalse);
    expect(_detail(members: 3, total: 40).memberCount, 3);
    final big = _detail(members: circleDetailMemberLimit + 1, total: 10000);
    expect(big.hasMoreMembers, isTrue);
    expect(big.memberCount, 10000);
  });

  testWidgets('a small circle shows everyone and no paging controls', (
    tester,
  ) async {
    await _pump(tester, _detail(members: 3, total: 3));

    expect(find.text('Member 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('circle-members-more')), findsNothing);
    expect(find.byKey(const ValueKey('circle-member-search')), findsNothing);
  });

  testWidgets('a big circle loads more members and searches the database', (
    tester,
  ) async {
    final source = await _pump(
      tester,
      _detail(members: circleDetailMemberLimit, total: 10000),
    );

    final more = find.byKey(const ValueKey('circle-members-more'));
    await tester.scrollUntilVisible(
      more,
      600,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(source.pages, [null]);
    expect(find.text('Member 900'), findsOneWidget);
    // A short page was the last one.
    expect(more, findsNothing);

    final search = find.byKey(const ValueKey('circle-member-search'));
    await tester.scrollUntilVisible(
      search,
      -600,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    await tester.enterText(search, 'seven');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(source.searches, ['seven']);
    expect(find.text('Member 777'), findsOneWidget);
    expect(find.text('Member 2'), findsNothing);
  });
}
