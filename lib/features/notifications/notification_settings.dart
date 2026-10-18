/// A time of day without a date, for the quiet hours window.
class QuietTime implements Comparable<QuietTime> {
  const QuietTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  final int hour;
  final int minute;

  int get minutesOfDay => hour * 60 + minute;

  /// "22:00" or "22:00:00" (a Postgres `time`); null when it isn't one.
  static QuietTime? tryParse(Object? value) {
    if (value is! String) {
      return null;
    }
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) {
      return null;
    }
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) {
      return null;
    }
    return QuietTime(hour, minute);
  }

  /// The form the database takes: "22:00:00".
  String toSql() =>
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}:00';

  @override
  int compareTo(QuietTime other) => minutesOfDay.compareTo(other.minutesOfDay);

  @override
  bool operator ==(Object other) =>
      other is QuietTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => toSql().substring(0, 5);
}

/// What a message must be to break through quiet hours.
class QuietMessage {
  const QuietMessage({
    this.senderId,
    this.mentionsMe = false,
    this.isCall = false,
  });

  final String? senderId;
  final bool mentionsMe;
  final bool isCall;
}

/// The person's notification settings kept on the server
/// (`user_notification_settings`): quiet hours and the important contacts,
/// and the message previews switch that used to live only on the device.
///
/// The rule is the one of `public.quiet_window_contains` in
/// supabase/migrations/202610210310_quiet_hours.sql and of the push
/// functions (supabase/functions/push/quiet_hours.ts); the three share their
/// test cases.
class NotificationSettings {
  const NotificationSettings({
    this.timezone,
    this.quietEnabled = false,
    this.quietDays = allDays,
    this.quietStart = const QuietTime(22, 0),
    this.quietEnd = const QuietTime(7, 0),
    this.allowStarred = true,
    this.allowMentions = true,
    this.allowCalls = true,
    this.vipUserIds = const {},
    this.showPreviews,
  });

  /// ISO weekdays: 1 is Monday, 7 is Sunday.
  static const allDays = {1, 2, 3, 4, 5, 6, 7};

  static const defaults = NotificationSettings();

  /// The IANA zone the device reported ('Asia/Shanghai'), if it has.
  final String? timezone;
  final bool quietEnabled;

  /// The weekdays a window starts on. One that runs past midnight goes on
  /// into the next morning, so that morning is quiet when the day before is
  /// picked.
  final Set<int> quietDays;
  final QuietTime quietStart;
  final QuietTime quietEnd;
  final bool allowStarred;
  final bool allowMentions;
  final bool allowCalls;

  /// Friends who are heard even in quiet hours.
  final Set<String> vipUserIds;

  /// Null until the device's own switch has been moved to the server.
  final bool? showPreviews;

  /// Whether the window runs past midnight (starts later than it ends).
  bool get crossesMidnight => quietStart.compareTo(quietEnd) > 0;

  /// Whether [wall], a clock time in the person's zone (the device's local
  /// time), is inside the window.
  bool isQuietAt(DateTime wall) {
    if (!quietEnabled || quietDays.isEmpty || quietStart == quietEnd) {
      return false;
    }
    final minutes = wall.hour * 60 + wall.minute;
    final start = quietStart.minutesOfDay;
    final end = quietEnd.minutesOfDay;
    final day = wall.weekday;
    if (start < end) {
      return quietDays.contains(day) && minutes >= start && minutes < end;
    }
    final previous = day == DateTime.monday ? DateTime.sunday : day - 1;
    return (minutes >= start && quietDays.contains(day)) ||
        (minutes < end && quietDays.contains(previous));
  }

  /// The next time the window opens or closes after [wall] (on the clock of
  /// [wall]), to wake up at; at most a day away.
  DateTime nextBoundaryAfter(DateTime wall) {
    DateTime at(int dayOffset, QuietTime time) => DateTime(
      wall.year,
      wall.month,
      wall.day + dayOffset,
      time.hour,
      time.minute,
    );
    final candidates = [
      for (final offset in [0, 1])
        for (final time in [quietStart, quietEnd]) at(offset, time),
    ]..removeWhere((time) => !time.isAfter(wall));
    candidates.sort();
    return candidates.first;
  }

  /// Whether [message] is heard in quiet hours: a call, an @mention of the
  /// person, an important contact or a starred friend, each as far as the
  /// person allows it. [starredFriendIds] are the friends they starred.
  bool breaksThrough(
    QuietMessage message, {
    Set<String> starredFriendIds = const {},
  }) {
    if (allowCalls && message.isCall) {
      return true;
    }
    if (allowMentions && message.mentionsMe) {
      return true;
    }
    final sender = message.senderId;
    if (sender == null) {
      return false;
    }
    return vipUserIds.contains(sender) ||
        (allowStarred && starredFriendIds.contains(sender));
  }

  NotificationSettings copyWith({
    String? timezone,
    bool? quietEnabled,
    Set<int>? quietDays,
    QuietTime? quietStart,
    QuietTime? quietEnd,
    bool? allowStarred,
    bool? allowMentions,
    bool? allowCalls,
    Set<String>? vipUserIds,
    bool? showPreviews,
  }) {
    return NotificationSettings(
      timezone: timezone ?? this.timezone,
      quietEnabled: quietEnabled ?? this.quietEnabled,
      quietDays: quietDays ?? this.quietDays,
      quietStart: quietStart ?? this.quietStart,
      quietEnd: quietEnd ?? this.quietEnd,
      allowStarred: allowStarred ?? this.allowStarred,
      allowMentions: allowMentions ?? this.allowMentions,
      allowCalls: allowCalls ?? this.allowCalls,
      vipUserIds: vipUserIds ?? this.vipUserIds,
      showPreviews: showPreviews ?? this.showPreviews,
    );
  }

  /// A row of `user_notification_settings`.
  factory NotificationSettings.fromRow(Map<String, dynamic> row) {
    final days = row['quiet_days'];
    final vips = row['vip_user_ids'];
    return NotificationSettings(
      timezone: row['timezone'] as String?,
      quietEnabled: row['quiet_enabled'] as bool? ?? false,
      quietDays: days is List
          ? {
              for (final day in days)
                if (day is int && day >= 1 && day <= 7) day,
            }
          : allDays,
      quietStart: QuietTime.tryParse(row['quiet_start']) ?? defaults.quietStart,
      quietEnd: QuietTime.tryParse(row['quiet_end']) ?? defaults.quietEnd,
      allowStarred: row['allow_starred'] as bool? ?? true,
      allowMentions: row['allow_mentions'] as bool? ?? true,
      allowCalls: row['allow_calls'] as bool? ?? true,
      vipUserIds: vips is List ? {for (final id in vips) id as String} : {},
      showPreviews: row['show_previews'] as bool?,
    );
  }

  /// The quiet hours columns, to save. Previews and the important contacts
  /// are saved on their own so that one device never overwrites what another
  /// changed.
  Map<String, dynamic> quietColumns() {
    final days = quietDays.toList()..sort();
    return {
      'quiet_enabled': quietEnabled,
      'quiet_days': days,
      'quiet_start': quietStart.toSql(),
      'quiet_end': quietEnd.toSql(),
      'allow_starred': allowStarred,
      'allow_mentions': allowMentions,
      'allow_calls': allowCalls,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is NotificationSettings &&
        other.timezone == timezone &&
        other.quietEnabled == quietEnabled &&
        _sameSet(other.quietDays, quietDays) &&
        other.quietStart == quietStart &&
        other.quietEnd == quietEnd &&
        other.allowStarred == allowStarred &&
        other.allowMentions == allowMentions &&
        other.allowCalls == allowCalls &&
        _sameSet(other.vipUserIds, vipUserIds) &&
        other.showPreviews == showPreviews;
  }

  @override
  int get hashCode => Object.hash(
    timezone,
    quietEnabled,
    Object.hashAllUnordered(quietDays),
    quietStart,
    quietEnd,
    allowStarred,
    allowMentions,
    allowCalls,
    Object.hashAllUnordered(vipUserIds),
    showPreviews,
  );
}

bool _sameSet<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);
