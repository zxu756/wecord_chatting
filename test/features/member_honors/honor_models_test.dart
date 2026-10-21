import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/member_honors/honor_models.dart';
import 'package:wecord/features/member_honors/honor_repository.dart';

import 'honor_fakes.dart';

void main() {
  group('flair', () {
    test('reads a title and the honors that may be shown', () {
      final flair = MemberFlair.fromJson({
        'user_id': 'u1',
        'title': '  Founder ',
        'streak_level': 30,
        'weekly_level': 2,
      });
      expect(flair.title, 'Founder');
      expect(flair.streakLevel, 30);
      expect(flair.weeklyLevel, 2);
      expect(flair.hasHonor, isTrue);
      expect(flairHonorLabel(flair), '30-day streak, Regular last week');
    });

    test('a blank title is no title and no honors is none', () {
      final flair = MemberFlair.fromJson({'user_id': 'u1', 'title': ' '});
      expect(flair.title, isNull);
      expect(flair.hasHonor, isFalse);
      expect(flairHonorLabel(flair), '');
    });

    test('weekly levels have their words', () {
      expect(weeklyLevelLabel(3), 'Full week');
      expect(weeklyLevelLabel(2), 'Regular');
      expect(weeklyLevelLabel(1), 'Present');
      expect(weeklyLevelRule(3), contains('7 days'));
      expect(weeklyLevelRule(2), contains('5 or 6'));
      expect(weeklyLevelRule(1), contains('3 or 4'));
    });
  });

  group('the Honors page', () {
    test('reads the answer of the server', () {
      final honors = CircleHonors.fromJson(honorsJson(canManage: true));
      expect(honors.enabled && honors.eligible && honors.isRunning, isTrue);
      expect(honors.participating, isTrue);
      expect(honors.canManage, isTrue);
      expect(honors.mine?.streak, 12);
      expect(honors.mine?.bestStreak, 31);
      expect(honors.mine?.weekDays, 3);
      expect(honors.mine?.honors, hasLength(2));
      expect(honors.mine?.honors.first.kind, HonorKind.weekly);
      expect(honors.mine?.honors.first.label, 'Full week');
      expect(honors.mine?.honors.last.label, '7-day streak');
      expect(honors.board?.published, isTrue);
      expect(honors.board?.entries, hasLength(6));
      expect(honors.board?.weekStart, DateTime(2026, 10, 19));
    });

    test('a circle that is small or off has no numbers', () {
      final small = CircleHonors.fromJson(honorsJson(eligible: false));
      expect(small.isRunning, isFalse);
      expect(small.mine, isNull);
      expect(small.board, isNull);
      final off = CircleHonors.fromJson(honorsJson(enabled: false));
      expect(off.isRunning, isFalse);
      expect(off.mine, isNull);
    });

    test('an unpublished board has no names', () {
      final honors = CircleHonors.fromJson(honorsJson(published: false));
      expect(honors.board?.published, isFalse);
      expect(honors.board?.entries, isEmpty);
    });

    test('an honor of a kind a newer server sends is left out', () {
      final honors = CircleHonors.fromJson(
        honorsJson(
          honors: [
            {'kind': 'crown', 'level': 1, 'period_start': '2026-10-19'},
            {'kind': 'streak', 'level': 30, 'period_start': '2026-10-19'},
          ],
        ),
      );
      expect(honors.mine?.honors, hasLength(1));
      expect(honors.mine?.honors.single.level, 30);
    });
  });

  group('a title', () {
    test('is up to 10 characters, whatever they are', () {
      expect(memberTitleProblem(''), isNull);
      expect(memberTitleProblem('   '), isNull);
      expect(memberTitleProblem('1234567890'), isNull);
      expect(memberTitleProblem('12345678901'), 'length');
      expect(memberTitleProblem('头衔头衔头衔头衔头衔'), isNull);
      expect(memberTitleProblem('头衔头衔头衔头衔头衔头'), 'length');
    });

    test('cannot hide or disguise itself', () {
      expect(memberTitleProblem('<b>hi</b>'), 'characters');
      expect(memberTitleProblem('Mod\u202Ex'), 'characters');
      expect(memberTitleProblem('a\u200Bb'), 'characters');
      expect(memberTitleProblem('Scout \u{1F3D5}'), isNull);
    });
  });

  group('the calls', () {
    test('send what the server expects', () async {
      final rpc = HonorsRpc(flair: sampleFlair());
      final repository = MemberHonorsRepository(rpc.call);

      final flair = await repository.listFlair('circle-1');
      expect(flair.keys, containsAll(['user-1', 'user-2', 'user-3']));
      expect(flair['user-1']?.title, 'Founder');

      await repository.setTitle(
        circleId: 'circle-1',
        userId: 'user-3',
        title: ' Scout ',
      );
      expect(rpc.paramsOf('set_circle_member_title').single, {
        'target_circle_id': 'circle-1',
        'target_user_id': 'user-3',
        'member_title': 'Scout',
      });
      await repository.setTitle(
        circleId: 'circle-1',
        userId: 'user-3',
        title: '  ',
      );
      expect(
        rpc.paramsOf('set_circle_member_title').last['member_title'],
        null,
      );

      await repository.setCircleHonors('circle-1', on: false);
      expect(rpc.paramsOf('set_circle_honors_enabled').single, {
        'target_circle_id': 'circle-1',
        'honors_on': false,
      });
      await repository.setParticipation('circle-1', on: false);
      expect(rpc.paramsOf('set_my_honors_participation').single, {
        'target_circle_id': 'circle-1',
        'take_part': false,
      });
    });

    test('a failing list shows nothing, a failing page throws', () async {
      final rpc = HonorsRpc()
        ..failing.addAll(['list_circle_member_flair', 'get_circle_honors']);
      final repository = MemberHonorsRepository(rpc.call);
      expect(await repository.listFlair('circle-1'), isEmpty);
      await expectLater(repository.load('circle-1'), throwsStateError);
    });

    test('a suspended circle has no page', () async {
      final rpc = HonorsRpc()..honors = null;
      expect(await MemberHonorsRepository(rpc.call).load('circle-1'), isNull);
    });
  });
}
