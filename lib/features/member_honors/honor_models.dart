import 'package:wecord/shared/l10n/l10n.dart';

/// The longest title a member can be given; mirrors the server's check.
const maxMemberTitleLength = 10;

/// Streak milestones, in days, as the server awards them.
const streakMilestones = <int>[7, 30, 100];

/// A streak is looked at over the 120 days the dashboard remembers.
const streakLookBackDays = 120;

/// What shows next to a member's name in one circle: the title a moderator
/// gave them and the honors that may be shown to others (the streak
/// milestone they are on, last week's level). Never a count of days.
class MemberFlair {
  const MemberFlair({
    required this.userId,
    this.title,
    this.streakLevel,
    this.weeklyLevel,
  });

  factory MemberFlair.fromJson(Map<String, dynamic> json) {
    final title = json['title'];
    return MemberFlair(
      userId: json['user_id'] as String,
      title: title is String && title.trim().isNotEmpty ? title.trim() : null,
      streakLevel: (json['streak_level'] as num?)?.toInt(),
      weeklyLevel: (json['weekly_level'] as num?)?.toInt(),
    );
  }

  final String userId;
  final String? title;
  final int? streakLevel;
  final int? weeklyLevel;

  bool get hasHonor => streakLevel != null || weeklyLevel != null;
}

/// Last week's level: 7 active days, 5 or 6, 3 or 4.
String weeklyLevelLabel(int level) {
  return switch (level) {
    3 => tr('Full week'),
    2 => tr('Regular'),
    _ => tr('Present'),
  };
}

/// A short explanation of what earns a weekly level.
String weeklyLevelRule(int level) {
  return switch (level) {
    3 => tr('Active all 7 days of the week'),
    2 => tr('Active 5 or 6 days of the week'),
    _ => tr('Active 3 or 4 days of the week'),
  };
}

String streakLabel(int days) {
  return tr('{days}-day streak', {'days': days});
}

/// The honor that goes with a flair, for a tooltip and screen readers.
String flairHonorLabel(MemberFlair flair) {
  final parts = [
    if (flair.streakLevel case final level?) streakLabel(level),
    if (flair.weeklyLevel case final level?)
      tr('{level} last week', {'level': weeklyLevelLabel(level)}),
  ];
  return parts.join(', ');
}

enum HonorKind {
  weekly,
  streak;

  static HonorKind? parse(Object? value) {
    return switch (value) {
      'weekly' => weekly,
      'streak' => streak,
      _ => null,
    };
  }
}

/// An honor the current member earned.
class EarnedHonor {
  const EarnedHonor({
    required this.kind,
    required this.level,
    required this.periodStart,
  });

  /// Null for a kind a newer server sends.
  static EarnedHonor? maybeFromJson(Map<String, dynamic> json) {
    final kind = HonorKind.parse(json['kind']);
    final level = (json['level'] as num?)?.toInt();
    final start = DateTime.tryParse('${json['period_start']}');
    if (kind == null || level == null || start == null) {
      return null;
    }
    return EarnedHonor(kind: kind, level: level, periodStart: start);
  }

  final HonorKind kind;

  /// 1 to 3 for a week; 7, 30 or 100 for a streak.
  final int level;

  /// The Monday of the week, or the day the streak got that long (UTC).
  final DateTime periodStart;

  String get label => switch (kind) {
    HonorKind.weekly => weeklyLevelLabel(level),
    HonorKind.streak => streakLabel(level),
  };
}

/// The current member's own numbers. Nobody else's are ever sent.
class MyHonors {
  const MyHonors({
    required this.streak,
    required this.bestStreak,
    required this.weekDays,
    required this.honors,
  });

  factory MyHonors.fromJson(Map<String, dynamic> json) {
    return MyHonors(
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      bestStreak: (json['best_streak'] as num?)?.toInt() ?? 0,
      weekDays: (json['week_days'] as num?)?.toInt() ?? 0,
      honors: [
        for (final item in (json['honors'] as List?) ?? const [])
          if (item is Map)
            ?EarnedHonor.maybeFromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }

  /// Consecutive active days up to now.
  final int streak;
  final int bestStreak;

  /// Active days so far this week (Monday to today, UTC).
  final int weekDays;
  final List<EarnedHonor> honors;
}

/// One person on last week's board: who and which level, nothing more.
class HonorEntry {
  const HonorEntry({required this.userId, required this.level});

  final String userId;
  final int level;
}

/// Last week's board. [entries] is empty unless [published]: it is shown only
/// when 5 or more people are on it.
class HonorBoard {
  const HonorBoard({
    required this.weekStart,
    required this.published,
    required this.entries,
  });

  factory HonorBoard.fromJson(Map<String, dynamic> json) {
    return HonorBoard(
      weekStart: DateTime.tryParse('${json['week_start']}'),
      published: json['published'] == true,
      entries: [
        for (final item in (json['entries'] as List?) ?? const [])
          if (item is Map && item['user_id'] is String)
            HonorEntry(
              userId: item['user_id'] as String,
              level: (item['level'] as num?)?.toInt() ?? 1,
            ),
      ],
    );
  }

  final DateTime? weekStart;
  final bool published;
  final List<HonorEntry> entries;
}

/// What the Honors page reads for one circle.
class CircleHonors {
  const CircleHonors({
    required this.circleId,
    required this.enabled,
    required this.eligible,
    required this.participating,
    required this.canManage,
    this.mine,
    this.board,
  });

  factory CircleHonors.fromJson(Map<String, dynamic> json) {
    final mine = json['mine'];
    final board = json['board'];
    return CircleHonors(
      circleId: json['circle_id'] as String? ?? '',
      enabled: json['enabled'] == true,
      eligible: json['eligible'] == true,
      participating: json['participating'] != false,
      canManage: json['can_manage'] == true,
      mine: mine is Map ? MyHonors.fromJson(Map.from(mine)) : null,
      board: board is Map ? HonorBoard.fromJson(Map.from(board)) : null,
    );
  }

  final String circleId;

  /// The circle has honors on.
  final bool enabled;

  /// The circle has 5 or more people; below that nothing is worked out.
  final bool eligible;
  final bool participating;

  /// The current member may switch honors on and off for the circle.
  final bool canManage;
  final MyHonors? mine;
  final HonorBoard? board;

  /// Honors are working here.
  bool get isRunning => enabled && eligible;
}

/// Why [input] cannot be a title, or null when it can (blank takes the title
/// off). Mirrors the server's check.
String? memberTitleProblem(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return null;
  }
  if (text.runes.length > maxMemberTitleLength) {
    return 'length';
  }
  if (RegExp(
    '[<>\\u0000-\\u001f\\u007f-\\u009f\\u200b-\\u200f\\u202a-\\u202e'
    '\\u2060-\\u206f\\ufeff]',
  ).hasMatch(text)) {
    return 'characters';
  }
  return null;
}
