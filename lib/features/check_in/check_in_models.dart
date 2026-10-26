import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/forms/form_models.dart' show FormImageAnswer;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// A calendar date with no time, as the server writes it ('2026-10-22').
DateTime? checkInDateFrom(Object? value) {
  if (value is! String || value.length < 10) {
    return null;
  }
  final year = int.tryParse(value.substring(0, 4));
  final month = int.tryParse(value.substring(5, 7));
  final day = int.tryParse(value.substring(8, 10));
  if (year == null || month == null || day == null) {
    return null;
  }
  return DateTime(year, month, day);
}

/// '2026-10-22' for [date], the way the server reads days.
String checkInDateText(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// A check-in as the card shows it: the title, today's count and the
/// caller's own run.
@immutable
class CheckInSnapshot {
  const CheckInSnapshot({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.today,
    this.messageId,
    this.description = '',
    this.timeZone = 'UTC',
    this.remindMinute,
    this.endsOn,
    this.closed = false,
    this.createdBy,
    this.canManage = false,
    this.todayCount = 0,
    this.memberTotal = 0,
    this.myCheckedIn = false,
    this.myNote = '',
    this.myPhoto,
    this.myStreak = 0,
    this.myBestStreak = 0,
    this.myTotalDays = 0,
  });

  factory CheckInSnapshot.fromJson(Map<String, dynamic> json) {
    return CheckInSnapshot(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      messageId: json['message_id'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      timeZone: json['time_zone'] as String? ?? 'UTC',
      remindMinute: (json['remind_minute'] as num?)?.toInt(),
      endsOn: checkInDateFrom(json['ends_on']),
      today: checkInDateFrom(json['today']) ?? DateTime.now(),
      closed: json['closed'] == true,
      createdBy: json['created_by'] as String?,
      canManage: json['can_manage'] == true,
      todayCount: (json['today_count'] as num?)?.toInt() ?? 0,
      memberTotal: (json['member_total'] as num?)?.toInt() ?? 0,
      myCheckedIn: json['my_checked_in'] == true,
      myNote: json['my_note'] as String? ?? '',
      myPhoto: FormImageAnswer.maybeFrom(json['my_photo']),
      myStreak: (json['my_streak'] as num?)?.toInt() ?? 0,
      myBestStreak: (json['my_best_streak'] as num?)?.toInt() ?? 0,
      myTotalDays: (json['my_total_days'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String conversationId;
  final String? messageId;
  final String title;
  final String description;

  /// The zone whose midnight turns the day over (the maker's device zone).
  final String timeZone;

  /// Minutes after local midnight of the daily reminder, or null.
  final int? remindMinute;

  /// The last day, or null for no end.
  final DateTime? endsOn;

  /// The board's own "today", a date.
  final DateTime today;
  final bool closed;
  final String? createdBy;
  final bool canManage;
  final int todayCount;
  final int memberTotal;
  final bool myCheckedIn;
  final String myNote;
  final FormImageAnswer? myPhoto;

  /// The run that is alive now (0 once a day was missed).
  final int myStreak;
  final int myBestStreak;
  final int myTotalDays;

  /// Whether the card takes check-ins now.
  bool get isOpen => !closed;

  /// The share of people who checked in today, 0 to 1.
  double get todayFraction =>
      memberTotal <= 0 ? 0 : (todayCount / memberTotal).clamp(0.0, 1.0);

  /// The run to show after checking in: today counts only once done, so a
  /// run that ended yesterday still reads as it is until today passes.
  bool get streakAtRisk => myStreak > 0 && !myCheckedIn;
}

/// One person's check-in on one day.
@immutable
class CheckInEntry {
  const CheckInEntry({
    required this.id,
    required this.userId,
    required this.name,
    required this.day,
    this.avatarUrl,
    this.note = '',
    this.photo,
    this.streak = 0,
    this.createdAt,
  });

  factory CheckInEntry.fromJson(Map<String, dynamic> json) {
    return CheckInEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      day: checkInDateFrom(json['day']) ?? DateTime.now(),
      note: json['note'] as String? ?? '',
      photo: FormImageAnswer.maybeFrom(json['photo']),
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse('${json['created_at']}')?.toLocal(),
    );
  }

  final String id;
  final String userId;
  final String name;
  final String? avatarUrl;
  final DateTime day;
  final String note;
  final FormImageAnswer? photo;
  final int streak;
  final DateTime? createdAt;
}

/// A person on the board of long runs.
@immutable
class CheckInLeader {
  const CheckInLeader({
    required this.userId,
    required this.name,
    required this.streak,
    this.avatarUrl,
  });

  factory CheckInLeader.fromJson(Map<String, dynamic> json) {
    return CheckInLeader(
      userId: json['user_id'] as String,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
    );
  }

  final String userId;
  final String name;
  final String? avatarUrl;
  final int streak;
}

/// Everything the check-in page shows: the card, today's list, the longest
/// runs and the caller's own days.
@immutable
class CheckInDetail {
  const CheckInDetail({
    required this.snapshot,
    this.entries = const [],
    this.leaders = const [],
    this.myDays = const {},
  });

  factory CheckInDetail.fromJson(Map<String, dynamic> json) {
    return CheckInDetail(
      snapshot: CheckInSnapshot.fromJson(json),
      entries: [
        for (final item in (json['entries'] as List? ?? const []))
          if (item is Map)
            CheckInEntry.fromJson(Map<String, dynamic>.from(item)),
      ],
      leaders: [
        for (final item in (json['leaders'] as List? ?? const []))
          if (item is Map)
            CheckInLeader.fromJson(Map<String, dynamic>.from(item)),
      ],
      myDays: {
        for (final item in (json['my_days'] as List? ?? const []))
          ?checkInDateFrom(item),
      },
    );
  }

  final CheckInSnapshot snapshot;
  final List<CheckInEntry> entries;
  final List<CheckInLeader> leaders;

  /// The days (dates) the caller checked in on, over the last 120 days.
  final Set<DateTime> myDays;
}

/// One day's list (a day other than today).
@immutable
class CheckInDay {
  const CheckInDay({
    required this.day,
    required this.count,
    this.entries = const [],
  });

  factory CheckInDay.fromJson(Map<String, dynamic> json) {
    return CheckInDay(
      day: checkInDateFrom(json['day']) ?? DateTime.now(),
      count: (json['count'] as num?)?.toInt() ?? 0,
      entries: [
        for (final item in (json['entries'] as List? ?? const []))
          if (item is Map)
            CheckInEntry.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }

  final DateTime day;
  final int count;
  final List<CheckInEntry> entries;
}

/// What a check-in said back.
@immutable
class CheckInResult {
  const CheckInResult({
    this.updated = false,
    this.noteHeld = false,
    this.streak = 0,
    this.bestStreak = 0,
    this.totalDays = 0,
  });

  factory CheckInResult.fromJson(Map<String, dynamic> json) {
    return CheckInResult(
      updated: json['updated'] == true,
      noteHeld: json['note_held'] == true,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      bestStreak: (json['best_streak'] as num?)?.toInt() ?? 0,
      totalDays: (json['total_days'] as num?)?.toInt() ?? 0,
    );
  }

  /// The person had already checked in today and this changed the note.
  final bool updated;

  /// The circle's AI guard kept the note out.
  final bool noteHeld;
  final int streak;
  final int bestStreak;
  final int totalDays;
}

/// What the person set when making a check-in.
@immutable
class CheckInDraft {
  const CheckInDraft({
    required this.title,
    this.description = '',
    this.timeZone,
    this.remindMinute,
    this.endsOn,
  });

  final String title;
  final String description;

  /// The IANA zone of the device (the day turns over there).
  final String? timeZone;
  final int? remindMinute;
  final DateTime? endsOn;
}

/// What a check-in card in a chat points at (the message's attachment).
@immutable
class CheckInCard {
  const CheckInCard({required this.checkInId, this.title = ''});

  final String checkInId;
  final String title;

  static CheckInCard? maybeFromAttachment(Map<String, dynamic>? attachment) {
    if (attachment == null || attachment['kind'] != 'check_in') {
      return null;
    }
    final id = attachment['check_in_id'];
    if (id is! String) {
      return null;
    }
    return CheckInCard(
      checkInId: id,
      title: attachment['title'] as String? ?? '',
    );
  }
}

extension CheckInMessageCard on ChatMessage {
  /// The check-in this message is the card of, or null.
  CheckInCard? get checkInCard {
    if (type != MessageType.text || recalledAt != null) {
      return null;
    }
    return CheckInCard.maybeFromAttachment(attachment);
  }
}

enum CheckInFailureKind {
  closed,
  notAllowed,
  tooMany,
  badTitle,
  badText,
  badReminder,
  badEnd,
  badPhoto,
  badDay,
  forbidden,
  gone,
  imageUpload,
  other,
}

/// A write the server refused.
class CheckInException implements Exception {
  const CheckInException(this.kind);

  /// Reads the server's refusal (the error texts of migration
  /// 202610280510).
  factory CheckInException.fromPostgrest(PostgrestException error) {
    final kind = switch (error.message) {
      'check_in_closed' => CheckInFailureKind.closed,
      'check_in_not_allowed' => CheckInFailureKind.notAllowed,
      'check_in_too_many' => CheckInFailureKind.tooMany,
      'check_in_title_invalid' => CheckInFailureKind.badTitle,
      'check_in_text_too_long' => CheckInFailureKind.badText,
      'check_in_remind_invalid' => CheckInFailureKind.badReminder,
      'check_in_end_invalid' => CheckInFailureKind.badEnd,
      'check_in_photo_invalid' => CheckInFailureKind.badPhoto,
      'check_in_day_invalid' => CheckInFailureKind.badDay,
      'Check-in not found' ||
      'Conversation not found' => CheckInFailureKind.gone,
      _ when error.code == '42501' => CheckInFailureKind.forbidden,
      _ => CheckInFailureKind.other,
    };
    return CheckInException(kind);
  }

  final CheckInFailureKind kind;

  /// What to tell the person.
  String get message => switch (kind) {
    CheckInFailureKind.closed => tr('This check-in is closed.'),
    CheckInFailureKind.notAllowed => tr(
      'Check-ins work in groups and circle channels.',
    ),
    CheckInFailureKind.tooMany => tr(
      'This chat already has 5 open check-ins. Close one first.',
    ),
    CheckInFailureKind.badTitle => tr('Give the check-in a title.'),
    CheckInFailureKind.badText => tr('That is too long.'),
    CheckInFailureKind.badReminder => tr('Pick a time for the reminder.'),
    CheckInFailureKind.badEnd => tr('Pick a last day that is not in the past.'),
    CheckInFailureKind.badPhoto => tr("That picture can't be used."),
    CheckInFailureKind.badDay => tr('That day is not available.'),
    CheckInFailureKind.forbidden => tr("You can't do that here."),
    CheckInFailureKind.gone => tr("This check-in isn't available any more."),
    CheckInFailureKind.imageUpload => tr(
      "The picture didn't upload. Try again.",
    ),
    CheckInFailureKind.other => tr("That didn't work. Try again."),
  };

  @override
  String toString() => 'CheckInException($kind)';
}
