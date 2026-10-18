import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/profile/birthday_card.dart';
import 'package:wecord/features/profile/birthday_editor.dart';
import 'package:wecord/features/profile/profile_insights_blocks.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/features/profile/status_visibility_picker.dart';
import 'package:wecord/features/profile/support_links.dart';
import 'package:wecord/features/profile/support_links_editor.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

class _Source implements ProfileDataSource {
  final calls = <(String, Map<String, dynamic>)>[];
  final answers = <String, Object?>{};
  Object? error;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    calls.add((functionName, params));
    if (error != null) {
      throw error!;
    }
    return answers[functionName];
  }
}

Widget _host(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the profile card', () {
    testWidgets(
      'shows the numbers in common, a group, the source and the birthday',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const ProfileInsightsBlocks(userId: 'u2'),
            overrides: [
              profileInsightsProvider('u2').overrideWith(
                (ref) async => const ProfileInsights(
                  mutuals: Mutuals(
                    friendCount: 3,
                    groupCount: 2,
                    circleCount: 1,
                    groups: [MutualItem(id: 'g1', title: 'Study group')],
                  ),
                  source: FriendSource.group,
                  birthday: ProfileBirthday(month: 10, day: 18),
                ),
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.text('3 mutual friends · 2 mutual groups · 1 mutual circle'),
          findsOneWidget,
        );
        expect(find.text('Study group'), findsOneWidget);
        expect(find.text('From a group chat'), findsOneWidget);
        expect(find.text('October 18'), findsOneWidget);
      },
    );

    testWidgets('a stranger gets numbers and no group names', (tester) async {
      await tester.pumpWidget(
        _host(
          const ProfileInsightsBlocks(userId: 'u2'),
          overrides: [
            profileInsightsProvider('u2').overrideWith(
              (ref) async => const ProfileInsights(
                mutuals: Mutuals(friendCount: 1, groupCount: 4),
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('1 mutual friend · 4 mutual groups'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-source')), findsNothing);
      expect(find.byKey(const ValueKey('profile-birthday')), findsNothing);
    });

    testWidgets('nothing to show draws nothing', (tester) async {
      await tester.pumpWidget(_host(const ProfileInsightsBlocks(userId: 'u2')));
      await tester.pump();
      expect(find.byKey(const ValueKey('profile-insights')), findsNothing);
    });

    testWidgets('reads in Chinese', (tester) async {
      AppStrings.isChinese = true;
      await tester.pumpWidget(
        _host(
          const ProfileInsightsBlocks(userId: 'u2'),
          overrides: [
            profileInsightsProvider('u2').overrideWith(
              (ref) async => const ProfileInsights(
                mutuals: Mutuals(friendCount: 3, groupCount: 2),
                source: FriendSource.qr,
                birthday: ProfileBirthday(month: 10, day: 18),
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text('${mutualFriendsLabel(3)} · ${mutualGroupsLabel(2)}'),
        findsOneWidget,
      );
      expect(mutualGroupsLabel(2), '2 个共同群聊');
      expect(find.text('扫了二维码'), findsOneWidget);
      expect(find.text('10 月 18 日'), findsOneWidget);
    });

    testWidgets('a request card shows how many friends are shared', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Column(
            children: [
              MutualCountLine(userId: 'u2'),
              MutualCountLine(userId: 'u3'),
            ],
          ),
          overrides: [
            mutualFriendCountProvider('u2').overrideWith((ref) async => 3),
            mutualFriendCountProvider('u3').overrideWith((ref) async => 0),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('3 mutual friends'), findsOneWidget);
      expect(find.byKey(const ValueKey('mutual-count-u3')), findsNothing);
    });
  });

  group('adding a friend from a profile', () {
    Future<_Source> pumpProfile(
      WidgetTester tester, {
      FriendSource? source,
    }) async {
      final profileSource = _Source()
        ..answers['get_profile_summary'] = [
          {
            'id': 'user-2',
            'username': 'ada',
            'display_name': 'Ada',
            'bio': '',
            'relationship_status': 'none',
            'is_blocked_by_me': false,
            'has_blocked_me': false,
          },
        ];
      final social = _Source();
      final contacts = _Contacts();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileRepositoryProvider.overrideWithValue(
              ProfileRepository.withDataSource(profileSource),
            ),
            profileSocialRepositoryProvider.overrideWithValue(
              ProfileSocialRepository(social),
            ),
            contactsRepositoryProvider.overrideWithValue(contacts),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: UserProfileScreen(userId: 'user-2', source: source),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('profile-add-friend')));
      await tester.pump();
      await tester.pump();
      expect(contacts.sent, ['user-2']);
      return social;
    }

    testWidgets('the request remembers where the profile was opened from', (
      tester,
    ) async {
      final social = await pumpProfile(tester, source: FriendSource.qr);
      final note = social.calls.where(
        (call) => call.$1 == 'set_friend_request_source',
      );
      expect(note.single.$2, {'target_user_id': 'user-2', 'source': 'qr'});
    });

    testWidgets('a profile opened from nowhere in particular notes nothing', (
      tester,
    ) async {
      final social = await pumpProfile(tester);
      expect(
        social.calls.where((call) => call.$1 == 'set_friend_request_source'),
        isEmpty,
      );
    });

    test('profile locations carry the source', () {
      expect(userProfileLocation('u1'), '/profile/u1');
      expect(
        userProfileLocation('u1', source: FriendSource.circle),
        '/profile/u1?source=circle',
      );
    });
  });

  group('birthday', () {
    testWidgets('saves a month and a day, private to friends by default', (
      tester,
    ) async {
      final source = _Source();
      await tester.pumpWidget(
        _host(
          const BirthdayEditor(current: MyBirthday()),
          overrides: [
            profileSocialRepositoryProvider.overrideWithValue(
              ProfileSocialRepository(source),
            ),
          ],
        ),
      );
      await tester.pump();

      // Nothing chosen yet.
      await tester.tap(find.byKey(const ValueKey('birthday-save')));
      await tester.pump();
      expect(find.text('Choose a month and a day.'), findsOneWidget);
      expect(source.calls, isEmpty);

      await tester.tap(find.byKey(const ValueKey('birthday-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('March').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('birthday-day-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('birthday-save')));
      await tester.pump();
      await tester.pump();
      expect(source.calls.single.$1, 'set_my_birthday');
      expect(source.calls.single.$2, {
        'p_month': 3,
        'p_day': 4,
        'p_visibility': 'friends',
        'p_reminders': true,
      });
    });

    testWidgets('only me and no reminders, and a birthday can be removed', (
      tester,
    ) async {
      final source = _Source();
      await tester.pumpWidget(
        _host(
          const BirthdayEditor(
            current: MyBirthday(
              birthday: ProfileBirthday(month: 3, day: 4),
              visibility: BirthdayVisibility.friends,
            ),
          ),
          overrides: [
            profileSocialRepositoryProvider.overrideWithValue(
              ProfileSocialRepository(source),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('birthday-visibility-self')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('birthday-reminders')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('birthday-save')));
      await tester.pump();
      await tester.pump();
      expect(source.calls.last.$2, {
        'p_month': 3,
        'p_day': 4,
        'p_visibility': 'self',
        'p_reminders': false,
      });

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _host(
          const BirthdayEditor(
            current: MyBirthday(birthday: ProfileBirthday(month: 3, day: 4)),
          ),
          overrides: [
            profileSocialRepositoryProvider.overrideWithValue(
              ProfileSocialRepository(source),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('birthday-remove')));
      await tester.pump();
      await tester.pump();
      expect(source.calls.last.$2['p_month'], isNull);
      expect(source.calls.last.$2['p_day'], isNull);
    });

    testWidgets('the settings row says what is saved', (tester) async {
      await tester.pumpWidget(
        _host(
          const BirthdaySettingsRow(),
          overrides: [
            myProfileExtrasProvider.overrideWith(
              (ref) async => const MyProfileExtras(
                birthday: MyBirthday(
                  birthday: ProfileBirthday(month: 10, day: 18),
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('October 18'), findsOneWidget);
    });

    testWidgets('a card wishes happy birthday through a draft in the chat', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const BirthdayCard(
            friend: BirthdayFriend(
              userId: 'u2',
              username: 'ada',
              displayName: 'Ada',
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Ada has a birthday today', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Send wishes'), findsOneWidget);
      expect(birthdayGreeting(), 'Happy birthday! 🎂');
      AppStrings.isChinese = true;
      expect(birthdayGreeting(), '生日快乐！🎂');
    });
  });

  group('status audience', () {
    testWidgets('picks who sees the status and reports only a change', (
      tester,
    ) async {
      final changes = <StatusVisibility?>[];
      await tester.pumpWidget(
        _host(
          StatusVisibilityPicker(onChanged: changes.add),
          overrides: [
            myProfileExtrasProvider.overrideWith(
              (ref) async => const MyProfileExtras(
                statusVisibility: StatusVisibility.friends,
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Everyone'), findsOneWidget);
      expect(find.text('Starred friends'), findsOneWidget);
      expect(find.text('Only me'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('status-visibility-starred')));
      await tester.pump();
      expect(changes.last, StatusVisibility.starred);
      // Back to the saved choice: nothing to save.
      await tester.tap(find.byKey(const ValueKey('status-visibility-friends')));
      await tester.pump();
      expect(changes.last, isNull);
    });
  });

  group('support links editor', () {
    testWidgets('refuses a link outside the list, saves the rest', (
      tester,
    ) async {
      final source = _Source();
      await tester.pumpWidget(
        _host(
          const SupportLinksEditor(current: []),
          overrides: [
            profileSocialRepositoryProvider.overrideWithValue(
              ProfileSocialRepository(source),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('support-add')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('support-url-0')),
        'https://evil.example/pay',
      );
      await tester.tap(find.byKey(const ValueKey('support-save')));
      await tester.pump();
      expect(
        find.textContaining('Only links to support pages'),
        findsOneWidget,
      );
      expect(source.calls, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('support-url-0')),
        'https://KO-FI.com/ada',
      );
      await tester.enterText(
        find.byKey(const ValueKey('support-label-0')),
        'Tea fund',
      );
      await tester.tap(find.byKey(const ValueKey('support-save')));
      await tester.pump();
      await tester.pump();
      expect(source.calls.single.$1, 'set_my_links');
      expect(source.calls.single.$2['links'], [
        {'url': 'https://ko-fi.com/ada', 'label': 'Tea fund'},
      ]);
    });

    testWidgets('at most 5 links', (tester) async {
      await tester.pumpWidget(
        _host(
          SupportLinksEditor(
            current: [
              for (var i = 0; i < 5; i++)
                SupportLink(url: 'https://ko-fi.com/a$i'),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('support-add')), findsNothing);
    });

    testWidgets('the circle section saves a link and shows the message', (
      tester,
    ) async {
      final source = _Source();
      await tester.pumpWidget(
        _host(
          const CircleSupportLinkSection(circleId: 'c1', available: true),
          overrides: [
            profileSocialRepositoryProvider.overrideWithValue(
              ProfileSocialRepository(source),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('circle-support-url')),
        'https://evil.example/pay',
      );
      await tester.tap(find.byKey(const ValueKey('circle-support-save')));
      await tester.pump();
      expect(
        source.calls.where((call) => call.$1 == 'set_circle_support_url'),
        isEmpty,
      );
      expect(
        find.byKey(const ValueKey('circle-support-message')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('circle-support-url')),
        'https://afdian.net/a/club',
      );
      await tester.tap(find.byKey(const ValueKey('circle-support-save')));
      await tester.pump();
      await tester.pump();
      final set = source.calls.where(
        (call) => call.$1 == 'set_circle_support_url',
      );
      expect(set.single.$2, {
        'target_circle_id': 'c1',
        'url': 'https://afdian.net/a/club',
      });
      expect(find.text('Link saved.'), findsOneWidget);
    });
  });
}

class _Contacts implements ContactsRepository {
  final sent = <String>[];

  @override
  Future<void> sendFriendRequest(String receiverId) async {
    sent.add(receiverId);
  }

  @override
  Future<void> acceptFriendRequest(String requestId) async {}

  @override
  Future<List<IncomingFriendRequest>> listIncomingRequests() async => const [];

  @override
  Future<List<Profile>> listFriends() async => const [];

  @override
  Future<void> rejectFriendRequest(String requestId) async {}

  @override
  Future<List<Profile>> searchProfiles(String query) async => const [];

  @override
  Future<void> setContactAlias({
    required String friendId,
    required String? alias,
  }) async {}
}
