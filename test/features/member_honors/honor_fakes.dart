import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/circles/circle_rpc.dart';

import '../../mobile/phone_test_support.dart';

/// Answers the database functions behind titles and honors. A title or a
/// switch changes what the next read says, as the server would. Unknown
/// functions fail, as an uninitialized Supabase client would.
class HonorsRpc {
  HonorsRpc({Map<String, dynamic>? honors, List<Map<String, dynamic>>? flair})
    : honors = honors ?? honorsJson(),
      flair = flair ?? [];

  /// The Honors page; null stands for a suspended circle.
  Map<String, dynamic>? honors;

  /// The rows of list_circle_member_flair.
  List<Map<String, dynamic>> flair;
  final calls = <(String, Map<String, dynamic>)>[];

  /// Makes the next call to this function fail.
  final failing = <String>{};

  CircleRpc get call => _call;

  Future<Object?> _call(String name, Map<String, dynamic> params) async {
    calls.add((name, params));
    if (failing.contains(name)) {
      throw StateError('offline');
    }
    switch (name) {
      case 'get_circle_honors':
        return honors;
      case 'list_circle_member_flair':
        return flair;
      case 'list_profile_badges':
        return const [];
      case 'set_circle_member_title':
        final title = params['member_title'] as String?;
        final userId = params['target_user_id'] as String;
        flair = [
          for (final row in flair)
            if (row['user_id'] != userId) row,
          if (title != null) {'user_id': userId, 'title': title},
        ];
        return title;
      case 'set_circle_honors_enabled':
        final on = params['honors_on'] as bool;
        honors = {...?honors, 'enabled': on};
        return on;
      case 'set_my_honors_participation':
        final on = params['take_part'] as bool;
        honors = {...?honors, 'participating': on, if (!on) 'mine': null};
        return on;
    }
    throw StateError('Unexpected $name');
  }

  List<Map<String, dynamic>> paramsOf(String name) => [
    for (final call in calls)
      if (call.$1 == name) call.$2,
  ];

  List<Override> get overrides => [circleRpcProvider.overrideWithValue(call)];
}

/// What get_circle_honors answers for the sample circle: a streak of 12 and
/// a good week, and last week's board with six people on it.
Map<String, dynamic> honorsJson({
  bool enabled = true,
  bool eligible = true,
  bool participating = true,
  bool canManage = false,
  bool published = true,
  bool withMine = true,
  List<Map<String, dynamic>>? honors,
  int streak = 12,
}) => {
  'circle_id': 'circle-1',
  'enabled': enabled,
  'eligible': eligible,
  'participating': participating,
  'can_manage': canManage,
  'mine': withMine && enabled && eligible && participating
      ? {
          'streak': streak,
          'best_streak': 31,
          'week_days': 3,
          'honors':
              honors ??
              [
                {'kind': 'weekly', 'level': 3, 'period_start': '2026-10-19'},
                {'kind': 'streak', 'level': 7, 'period_start': '2026-10-14'},
              ],
        }
      : null,
  'board': enabled && eligible
      ? {
          'week_start': '2026-10-19',
          'published': published,
          'entries': published
              ? [
                  {'user_id': 'user-1', 'level': 3},
                  {'user_id': 'user-3', 'level': 3},
                  {'user_id': 'user-2', 'level': 2},
                  {'user_id': 'user-4', 'level': 2},
                  {'user_id': 'user-5', 'level': 1},
                  {'user_id': 'user-6', 'level': 1},
                ]
              : <Map<String, dynamic>>[],
        }
      : null,
};

/// Titles and honors shown next to some of the sample circle's members.
List<Map<String, dynamic>> sampleFlair() => [
  {'user_id': 'user-1', 'title': 'Founder', 'weekly_level': 3},
  {'user_id': 'user-2', 'title': 'Trail boss', 'streak_level': 30},
  {'user_id': 'user-3', 'streak_level': 7, 'weekly_level': 2},
  {'user_id': 'user-4', 'title': 'Photo editor'},
];

/// The phone test world with titles and honors answered by [rpc].
class HonorsWorld {
  HonorsWorld({PhoneWorld? world, HonorsRpc? rpc})
    : world = world ?? PhoneWorld(),
      rpc = rpc ?? HonorsRpc();

  final PhoneWorld world;
  final HonorsRpc rpc;

  /// Applies the overrides to [world] (call before opening anything).
  void install() {
    world.extraOverrides = [...world.extraOverrides, ...rpc.overrides];
  }
}
