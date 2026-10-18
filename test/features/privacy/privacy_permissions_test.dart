import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/privacy/privacy_permissions.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'privacy2_fakes.dart';

class _SignedIn implements AuthRepository {
  @override
  AuthUser? get currentUser => const AuthUser(id: 'user-1');

  @override
  Stream<AuthUser?> authStateChanges() =>
      Stream.value(const AuthUser(id: 'user-1'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(FakePrivacyPermissionsRepository repository) {
  return ProviderScope(
    overrides: [
      privacyPermissionsRepositoryProvider.overrideWithValue(repository),
      authRepositoryProvider.overrideWithValue(_SignedIn()),
    ],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: const Scaffold(
        body: SingleChildScrollView(child: PrivacyPermissionsGroups()),
      ),
    ),
  );
}

void main() {
  test('every choice reads and writes its wire name', () {
    expect(
      [for (final value in FriendRequestFrom.values) value.wire],
      ['everyone', 'friends_of_friends', 'circle_members', 'nobody'],
    );
    expect(
      [for (final value in GroupInviteFrom.values) value.wire],
      ['all_friends', 'starred_friends', 'approval'],
    );
    expect(
      [for (final value in CallsFrom.values) value.wire],
      ['friends', 'starred_friends', 'nobody'],
    );
    expect(
      FriendRequestFrom.fromWire('circle_members'),
      FriendRequestFrom.circleMembers,
    );
    expect(GroupInviteFrom.fromWire('approval'), GroupInviteFrom.approval);
    expect(CallsFrom.fromWire('nobody'), CallsFrom.nobody);
  });

  test('anything unknown falls back to the open default', () {
    expect(FriendRequestFrom.fromWire('bots'), FriendRequestFrom.everyone);
    expect(GroupInviteFrom.fromWire(null), GroupInviteFrom.allFriends);
    expect(CallsFrom.fromWire(3), CallsFrom.friends);
  });

  test('a row becomes the choices; no row means the defaults', () {
    expect(PrivacyPermissions.fromRow(null), const PrivacyPermissions());
    final permissions = PrivacyPermissions.fromRow({
      'friend_request_from': 'friends_of_friends',
      'discoverable_by_username': false,
      'discoverable_by_qr': true,
      'group_invite_from': 'starred_friends',
      'allow_calls_from': 'nobody',
    });
    expect(permissions.friendRequestFrom, FriendRequestFrom.friendsOfFriends);
    expect(permissions.discoverableByUsername, isFalse);
    expect(permissions.discoverableByQr, isTrue);
    expect(permissions.groupInviteFrom, GroupInviteFrom.starredFriends);
    expect(permissions.allowCallsFrom, CallsFrom.nobody);
  });

  test('saving sends only what changed', () {
    const base = PrivacyPermissions();
    expect(privacyPermissionsChanges(base, base), isEmpty);
    expect(
      privacyPermissionsChanges(
        base,
        base.copyWith(
          friendRequestFrom: FriendRequestFrom.nobody,
          discoverableByQr: false,
          allowCallsFrom: CallsFrom.starredFriends,
        ),
      ),
      {
        'friend_request_from': 'nobody',
        'discoverable_by_qr': false,
        'allow_calls_from': 'starred_friends',
      },
    );
    expect(
      privacyPermissionsChanges(
        base,
        base.copyWith(
          groupInviteFrom: GroupInviteFrom.approval,
          discoverableByUsername: false,
        ),
      ),
      {'group_invite_from': 'approval', 'discoverable_by_username': false},
    );
  });

  test('every choice has a label and a line of explanation', () {
    for (final value in FriendRequestFrom.values) {
      expect(value.label, isNotEmpty);
      expect(value.description, isNotEmpty);
    }
    for (final value in GroupInviteFrom.values) {
      expect(value.label, isNotEmpty);
      expect(value.description, isNotEmpty);
    }
    for (final value in CallsFrom.values) {
      expect(value.label, isNotEmpty);
      expect(value.description, isNotEmpty);
    }
  });

  test('the choices read in Chinese too', () {
    AppStrings.isChinese = true;
    addTearDown(() => AppStrings.isChinese = false);
    expect(FriendRequestFrom.nobody.label, '无人');
    expect(GroupInviteFrom.approval.label, '需要我同意');
    expect(CallsFrom.starredFriends.label, '星标好友');
  });

  testWidgets('shows three groups with the saved choices', (tester) async {
    final repository = FakePrivacyPermissionsRepository(
      const PrivacyPermissions(
        friendRequestFrom: FriendRequestFrom.circleMembers,
        discoverableByQr: false,
        groupInviteFrom: GroupInviteFrom.approval,
        allowCallsFrom: CallsFrom.starredFriends,
      ),
    );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Adding me'), findsOneWidget);
    expect(find.text('Group invitations'), findsOneWidget);
    expect(find.text('Calls'), findsOneWidget);
    expect(find.text('People in a shared circle'), findsOneWidget);
    expect(find.text('Needs my approval'), findsOneWidget);
    expect(find.text('Starred friends'), findsOneWidget);
    expect(
      tester
          .widget<WeCordSwitch>(
            find.descendant(
              of: find.byKey(const ValueKey('discoverable-by-username')),
              matching: find.byType(WeCordSwitch),
            ),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('picking who can send requests saves that one choice', (
    tester,
  ) async {
    final repository = FakePrivacyPermissionsRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('friend-request-from-row')));
    await tester.pumpAndSettle();
    expect(find.text('Friends of friends'), findsOneWidget);
    expect(find.text('Nobody'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.text('Friends of friends'));
    await tester.pumpAndSettle();

    expect(repository.saves, hasLength(1));
    final (before, after) = repository.saves.single;
    expect(before.friendRequestFrom, FriendRequestFrom.everyone);
    expect(after.friendRequestFrom, FriendRequestFrom.friendsOfFriends);
    expect(after.groupInviteFrom, before.groupInviteFrom);
    expect(find.text('Friends of friends'), findsOneWidget);
  });

  testWidgets('group invitations and calls have their own pickers', (
    tester,
  ) async {
    final repository = FakePrivacyPermissionsRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('group-invite-from-row')));
    await tester.pumpAndSettle();
    expect(find.text('Needs my approval'), findsOneWidget);
    await tester.tap(find.text('Needs my approval'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('calls-from-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nobody'));
    await tester.pumpAndSettle();

    expect(repository.saves, hasLength(2));
    expect(repository.stored.groupInviteFrom, GroupInviteFrom.approval);
    expect(repository.stored.allowCallsFrom, CallsFrom.nobody);
  });

  testWidgets('the two switches save on their own', (tester) async {
    final repository = FakePrivacyPermissionsRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('discoverable-by-username')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discoverable-by-qr')));
    await tester.pumpAndSettle();

    expect(repository.stored.discoverableByUsername, isFalse);
    expect(repository.stored.discoverableByQr, isFalse);
    expect(repository.saves, hasLength(2));
    // Each save carries only what changed.
    expect(
      repository.saves.first.$2.discoverableByQr,
      repository.saves.first.$1.discoverableByQr,
    );
  });

  testWidgets('a failed save keeps the old choice and says so', (tester) async {
    final repository = FakePrivacyPermissionsRepository()..fail = true;
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('calls-from-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nobody'));
    await tester.pumpAndSettle();

    expect(find.text('Could not save privacy settings. Try again.'), findsOne);
    expect(repository.stored.allowCallsFrom, CallsFrom.friends);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('calls-from-row')),
        matching: find.text('Friends'),
      ),
      findsOneWidget,
    );
  });
}
