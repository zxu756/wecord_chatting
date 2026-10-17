import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/privacy/profile_visibility.dart';
import 'package:wecord/shared/models/profile_relationship.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../profile/user_profile_screen_test.dart' as profile_fakes;

class _FakeVisibility implements ProfileVisibilityRepository {
  _FakeVisibility([this.value = ProfileVisibility.everyone]);

  ProfileVisibility value;
  final saved = <ProfileVisibility>[];
  var fail = false;

  @override
  Future<ProfileVisibility> load() async => value;

  @override
  Future<void> save(ProfileVisibility visibility) async {
    if (fail) {
      throw StateError('offline');
    }
    saved.add(visibility);
    value = visibility;
  }
}

class _SignedIn implements AuthRepository {
  @override
  AuthUser? get currentUser => const AuthUser(id: 'user-1');

  @override
  Stream<AuthUser?> authStateChanges() =>
      Stream.value(const AuthUser(id: 'user-1'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(_FakeVisibility repository) {
  return ProviderScope(
    overrides: [
      profileVisibilityRepositoryProvider.overrideWithValue(repository),
      authRepositoryProvider.overrideWithValue(_SignedIn()),
    ],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: const Scaffold(body: ProfileVisibilityRow()),
    ),
  );
}

void main() {
  test('reads and writes the three choices', () {
    expect(ProfileVisibility.fromWire('friends'), ProfileVisibility.friends);
    expect(
      ProfileVisibility.fromWire('friends_and_circles'),
      ProfileVisibility.friendsAndCircles,
    );
    expect(ProfileVisibility.fromWire(null), ProfileVisibility.everyone);
    expect(ProfileVisibility.fromWire('nobody'), ProfileVisibility.everyone);
    expect(
      [for (final value in ProfileVisibility.values) value.wire],
      ['everyone', 'friends_and_circles', 'friends'],
    );
  });

  test('a summary says when details are kept private', () {
    final hidden = ProfileSummary.fromJson({
      'id': 'u',
      'username': 'ada',
      'display_name': 'Ada',
      'bio': '',
      'relationship_status': 'none',
      'profile_hidden': true,
    });
    expect(hidden.profileHidden, isTrue);
    final open = ProfileSummary.fromJson({
      'id': 'u',
      'username': 'ada',
      'display_name': 'Ada',
      'bio': 'hi',
      'relationship_status': 'none',
    });
    expect(open.profileHidden, isFalse);
  });

  testWidgets('shows the choice and changes it from a sheet', (tester) async {
    final repository = _FakeVisibility();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Profile visibility'), findsOneWidget);
    expect(find.text('Everyone'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-visibility-row')));
    await tester.pumpAndSettle();
    expect(find.text('Friends and shared circles'), findsOneWidget);
    expect(find.text('Friends only'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.text('Friends only'));
    await tester.pumpAndSettle();
    expect(repository.saved, [ProfileVisibility.friends]);
    expect(find.text('Friends only'), findsOneWidget);
  });

  testWidgets('a failed save keeps the old choice and says so', (tester) async {
    final repository = _FakeVisibility(ProfileVisibility.friendsAndCircles)
      ..fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileVisibilityRepositoryProvider.overrideWithValue(repository),
          authRepositoryProvider.overrideWithValue(_SignedIn()),
        ],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: const Scaffold(body: ProfileVisibilityRow()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-visibility-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friends only').last);
    await tester.pumpAndSettle();
    expect(find.text('Friends and shared circles'), findsOneWidget);
    expect(
      find.text('Could not save privacy settings. Try again.'),
      findsOneWidget,
    );
  });

  group('profile page', () {
    Widget page(Map<String, dynamic> extra) {
      final summary = profile_fakes.noneSummary(
        displayName: 'Ada',
        username: 'ada',
      );
      final data = profile_fakes.FakeProfileDataSource()
        ..rpcResult = [
          {...profile_fakes.summaryJson(summary), ...extra},
        ];
      return ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            ProfileRepository.withDataSource(data),
          ),
          contactsRepositoryProvider.overrideWithValue(
            profile_fakes.FakeContactsRepository(),
          ),
        ],
        child: const MaterialApp(home: UserProfileScreen(userId: 'user-2')),
      );
    }

    testWidgets('says when details are private', (tester) async {
      await tester.pumpWidget(page({'profile_hidden': true}));
      await tester.pump();
      expect(find.byKey(const ValueKey('profile-hidden-note')), findsOneWidget);
      expect(find.text('Ada keeps some details private.'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-about')), findsNothing);
    });

    testWidgets('says nothing when everything is shown', (tester) async {
      await tester.pumpWidget(page({'bio': 'Hello', 'profile_hidden': false}));
      await tester.pump();
      expect(find.byKey(const ValueKey('profile-hidden-note')), findsNothing);
      expect(find.byKey(const ValueKey('profile-about')), findsOneWidget);
    });
  });
}
