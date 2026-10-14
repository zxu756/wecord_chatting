import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_moderation.dart';
import 'package:wecord/shared/models/circle.dart';

Map<String, dynamic> _member({Object? timedOutUntil}) => {
  'role': 'member',
  'nickname': null,
  'is_current_user': false,
  'role_ids': const <String>[],
  'timed_out_until': timedOutUntil,
  'profile': {
    'id': 'user-2',
    'username': 'bo',
    'display_name': 'Bo',
    'avatar_url': null,
    'bio': '',
    'created_at': '2026-10-14T00:00:00Z',
    'updated_at': '2026-10-14T00:00:00Z',
  },
};

void main() {
  test('a member is timed out until the time passes', () {
    final future = DateTime.now().toUtc().add(const Duration(hours: 1));
    final member = CircleMember.fromJson(
      _member(timedOutUntil: future.toIso8601String()),
    );
    expect(member.activeTimeoutUntil, isNotNull);

    final past = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    expect(
      CircleMember.fromJson(
        _member(timedOutUntil: past.toIso8601String()),
      ).activeTimeoutUntil,
      isNull,
    );
    expect(CircleMember.fromJson(_member()).activeTimeoutUntil, isNull);
  });

  test('timeout ends read as a time today, otherwise with the date', () {
    final now = DateTime(2026, 10, 14, 9);
    expect(formatTimeoutEnd(DateTime(2026, 10, 14, 15, 5), now: now), '15:05');
    expect(
      formatTimeoutEnd(DateTime(2026, 10, 21, 9, 30), now: now),
      '10/21 09:30',
    );
  });
}
