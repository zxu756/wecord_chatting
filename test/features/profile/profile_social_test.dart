import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/features/profile/support_links.dart';
import 'package:wecord/shared/l10n/l10n.dart';

class _Source implements ProfileDataSource {
  final calls = <(String, Map<String, dynamic>)>[];
  Object? result;
  Object? error;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    calls.add((functionName, params));
    if (error != null) {
      throw error!;
    }
    return result;
  }
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('status bubble text', () {
    test('keeps the emoji and the first 12 characters', () {
      const status = FriendStatus(
        userId: 'u',
        emoji: '📚',
        text: 'Studying for the exam tomorrow',
      );
      expect(status.bubbleLabel, '📚 Studying for…');
      expect(status.fullLabel, '📚 Studying for the exam tomorrow');
    });

    test(
      'a short text is kept whole, a long Chinese text is cut by letter',
      () {
        expect(
          const FriendStatus(userId: 'u', text: 'In the library').bubbleLabel,
          'In the libra…',
        );
        expect(
          const FriendStatus(userId: 'u', text: 'Out to lunch').bubbleLabel,
          'Out to lunch',
        );
        expect(
          const FriendStatus(userId: 'u', text: '正在图书馆复习明天的考试内容').bubbleLabel,
          '正在图书馆复习明天的考试…',
        );
      },
    );

    test('an emoji alone is a bubble, spaces collapse', () {
      expect(const FriendStatus(userId: 'u', emoji: '🎧').bubbleLabel, '🎧');
      expect(
        const FriendStatus(userId: 'u', text: '  on   a call ').bubbleLabel,
        'on a call',
      );
    });

    test('an expired or empty status is not active', () {
      final now = DateTime.utc(2026, 10, 19, 12);
      expect(
        FriendStatus(
          userId: 'u',
          text: 'x',
          expiresAt: now.subtract(const Duration(seconds: 1)),
        ).isActiveAt(now),
        isFalse,
      );
      expect(
        FriendStatus(
          userId: 'u',
          text: 'x',
          expiresAt: now.add(const Duration(minutes: 1)),
        ).isActiveAt(now),
        isTrue,
      );
      expect(const FriendStatus(userId: 'u').isActiveAt(now), isFalse);
      expect(
        const FriendStatus(userId: 'u', text: 'x').isActiveAt(now),
        isTrue,
      );
    });
  });

  group('birthday', () {
    test('reads as a month and a day, in either language', () {
      const birthday = ProfileBirthday(month: 10, day: 18);
      AppStrings.isChinese = false;
      expect(birthday.label, 'October 18');
      AppStrings.isChinese = true;
      expect(birthday.label, '10 月 18 日');
    });

    test('February has 29 days, April 30', () {
      expect(ProfileBirthday.daysIn(2), 29);
      expect(ProfileBirthday.daysIn(4), 30);
      expect(ProfileBirthday.daysIn(12), 31);
    });

    test('only a month and a day parse', () {
      expect(
        ProfileBirthday.maybeFromJson({'month': 3, 'day': 4}),
        const ProfileBirthday(month: 3, day: 4),
      );
      expect(ProfileBirthday.maybeFromJson(null), isNull);
      expect(ProfileBirthday.maybeFromJson({'month': 3}), isNull);
    });

    test('my extras parse the audience and the reminders', () {
      final extras = MyProfileExtras.fromJson({
        'birthday': {
          'month': 10,
          'day': 18,
          'visibility': 'self',
          'reminders': false,
        },
        'status_visibility': 'starred',
        'links': [
          {'url': 'https://ko-fi.com/ada', 'label': 'Ko-fi'},
          {'url': 'https://evil.example/pay'},
        ],
      });
      expect(
        extras.birthday.birthday,
        const ProfileBirthday(month: 10, day: 18),
      );
      expect(extras.birthday.visibility, BirthdayVisibility.self);
      expect(extras.birthday.reminders, isFalse);
      expect(extras.statusVisibility, StatusVisibility.starred);
      // A link the app would not open is dropped even if the server sent it.
      expect(extras.links.map((link) => link.url), ['https://ko-fi.com/ada']);
    });
  });

  group('mutuals and sources', () {
    test('the numbers are always there, the names only for a friend', () {
      final stranger = Mutuals.fromJson({
        'friend_count': 2,
        'group_count': 1,
        'circle_count': 0,
        'friends': const [],
        'groups': const [],
        'circles': const [],
      });
      expect(stranger.friendCount, 2);
      expect(stranger.groupCount, 1);
      expect(stranger.groups, isEmpty);
      expect(stranger.isEmpty, isFalse);

      final friend = Mutuals.fromJson({
        'friend_count': 1,
        'group_count': 1,
        'circle_count': 1,
        'friends': [
          {'id': 'u3', 'username': 'grace', 'display_name': 'Grace'},
        ],
        'groups': [
          {'id': 'g1', 'title': 'Study group'},
        ],
        'circles': [
          {'id': 'c1', 'name': 'Chess club'},
        ],
      });
      expect(friend.friends.single.title, 'Grace');
      expect(friend.groups.single.title, 'Study group');
      expect(friend.circles.single.title, 'Chess club');
      expect(Mutuals.fromJson(null).isEmpty, isTrue);
    });

    test('sources have wire names and labels', () {
      expect(FriendSource.fromWire('qr'), FriendSource.qr);
      expect(FriendSource.fromWire('rumour'), isNull);
      expect(FriendSource.fromWire(null), isNull);
      AppStrings.isChinese = true;
      expect(FriendSource.group.label, '来自群聊');
      expect(FriendSource.qr.label, '扫了二维码');
    });
  });

  group('repository', () {
    test('reads the profile extras of a person', () async {
      final source = _Source()
        ..result = {
          'birthday': {'month': 10, 'day': 18},
          'links': [
            {'url': 'https://afdian.net/a/ada', 'label': null},
          ],
          'source': 'circle',
          'mutuals': {'friend_count': 3, 'group_count': 2, 'circle_count': 1},
        };
      final insights = await ProfileSocialRepository(
        source,
      ).getProfileInsights('u2');
      expect(source.calls.single.$1, 'get_profile_extras');
      expect(source.calls.single.$2, {'target_user_id': 'u2'});
      expect(insights.source, FriendSource.circle);
      expect(insights.mutuals.friendCount, 3);
      expect(insights.birthday?.day, 18);
      expect(insights.links.single.title, '爱发电');
    });

    test(
      'mutual counts ask for at most 50 people and map the answer',
      () async {
        final source = _Source()
          ..result = [
            {'user_id': 'u2', 'friend_count': 4},
          ];
        final counts = await ProfileSocialRepository(
          source,
        ).mutualFriendCounts([for (var i = 0; i < 60; i++) 'u$i']);
        expect((source.calls.single.$2['user_ids'] as List).length, 50);
        expect(counts, {'u2': 4});
        source.calls.clear();
        expect(
          await ProfileSocialRepository(source).mutualFriendCounts([]),
          {},
        );
        expect(source.calls, isEmpty);
      },
    );

    test('a note of where a request came from never throws', () async {
      final source = _Source()..error = StateError('offline');
      await ProfileSocialRepository(
        source,
      ).setFriendRequestSource('u2', FriendSource.qr);
      expect(source.calls.single.$1, 'set_friend_request_source');
      expect(source.calls.single.$2, {'target_user_id': 'u2', 'source': 'qr'});
    });

    test('saves the birthday and the audience', () async {
      final source = _Source();
      final repository = ProfileSocialRepository(source);
      await repository.setMyBirthday(
        birthday: const ProfileBirthday(month: 2, day: 29),
        visibility: BirthdayVisibility.self,
        reminders: false,
      );
      expect(source.calls.last.$1, 'set_my_birthday');
      expect(source.calls.last.$2, {
        'p_month': 2,
        'p_day': 29,
        'p_visibility': 'self',
        'p_reminders': false,
      });
      await repository.setMyBirthday(
        birthday: null,
        visibility: BirthdayVisibility.friends,
        reminders: true,
      );
      expect(source.calls.last.$2['p_month'], isNull);
      await repository.setStatusVisibility(StatusVisibility.starred);
      expect(source.calls.last.$1, 'set_status_visibility');
      expect(source.calls.last.$2, {'visibility': 'starred'});
    });

    test('friends\' statuses and today\'s birthdays', () async {
      final source = _Source()
        ..result = [
          {
            'user_id': 'u2',
            'emoji': '🎯',
            'status_text': 'Focusing',
            'expires_at': '2026-10-19T12:00:00+00:00',
          },
          {
            'user_id': 'u3',
            'emoji': null,
            'status_text': ' ',
            'expires_at': null,
          },
        ];
      final statuses = await ProfileSocialRepository(source).friendStatuses();
      expect(statuses['u2']?.text, 'Focusing');
      expect(statuses['u2']?.expiresAt, DateTime.utc(2026, 10, 19, 12));
      expect(statuses['u3']?.text, isNull);

      source.result = [
        {
          'user_id': 'u2',
          'username': 'ada',
          'display_name': 'Ada',
          'avatar_url': null,
        },
      ];
      final friends = await ProfileSocialRepository(
        source,
      ).birthdaysOn(DateTime(2026, 3, 4));
      expect(source.calls.last.$1, 'list_birthdays_today');
      expect(source.calls.last.$2, {'on_date': '2026-03-04'});
      expect(friends.single.displayName, 'Ada');
    });

    test('links are sent as the editor made them', () async {
      final source = _Source();
      await ProfileSocialRepository(source).setMyLinks(const [
        SupportLink(url: 'https://ko-fi.com/ada', label: 'Ko-fi'),
        SupportLink(url: 'https://patreon.com/ada'),
      ]);
      expect(source.calls.single.$1, 'set_my_links');
      expect(source.calls.single.$2['links'], [
        {'url': 'https://ko-fi.com/ada', 'label': 'Ko-fi'},
        {'url': 'https://patreon.com/ada', 'label': null},
      ]);
    });

    test('a circle\'s link is read and written by id', () async {
      final source = _Source()..result = 'https://afdian.net/a/club';
      final repository = ProfileSocialRepository(source);
      expect(
        await repository.circleSupportUrl('c1'),
        'https://afdian.net/a/club',
      );
      source.result = 'https://evil.example/pay';
      expect(await repository.circleSupportUrl('c1'), isNull);
      await repository.setCircleSupportUrl('c1', null);
      expect(source.calls.last.$1, 'set_circle_support_url');
      expect(source.calls.last.$2, {'target_circle_id': 'c1', 'url': null});
    });
  });
}
