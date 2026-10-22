/// What kind of thing an agenda entry is.
enum AgendaKind {
  /// An event of a group or direct chat I said Going or Maybe to.
  chatEvent('chat_event'),

  /// A circle event I am interested in.
  circleEvent('circle_event'),

  /// A task assigned to me, open, with a due date.
  task('task'),

  /// A reminder I set about a message.
  reminder('reminder'),

  /// A message of mine waiting to be sent.
  scheduledMessage('scheduled_message');

  const AgendaKind(this.wire);

  /// The name the server uses (`get_my_agenda` → `kind`).
  final String wire;

  static AgendaKind? fromWire(String? value) {
    for (final kind in values) {
      if (kind.wire == value) {
        return kind;
      }
    }
    return null;
  }

  bool get isEvent => this == chatEvent || this == circleEvent;
}

/// One row of `get_my_agenda`: something with a time that concerns me,
/// wherever it lives.
class AgendaItem {
  const AgendaItem({
    required this.kind,
    required this.startsAt,
    required this.targetId,
    this.title,
    this.endsAt,
    this.allDay = false,
    this.conversationId,
    this.circleId,
    this.parentId,
    this.placeName,
    this.subtitle,
    this.meta = const {},
  });

  /// Null for a row of a kind this app does not know (a newer server).
  static AgendaItem? tryParse(Map<String, dynamic> json) {
    final kind = AgendaKind.fromWire(json['kind'] as String?);
    final startsAt = DateTime.tryParse('${json['starts_at']}');
    final targetId = json['target_id'];
    if (kind == null || startsAt == null || targetId is! String) {
      return null;
    }
    final endsAt = json['ends_at'] == null
        ? null
        : DateTime.tryParse('${json['ends_at']}');
    final meta = json['meta'];
    return AgendaItem(
      kind: kind,
      title: _text(json['title']),
      startsAt: startsAt.toUtc(),
      endsAt: endsAt?.toUtc(),
      allDay: json['all_day'] == true,
      conversationId: json['conversation_id'] as String?,
      circleId: json['circle_id'] as String?,
      targetId: targetId,
      parentId: json['parent_id'] as String?,
      placeName: _text(json['place_name']),
      subtitle: _text(json['subtitle']),
      meta: meta is Map<String, dynamic> ? meta : const {},
    );
  }

  final AgendaKind kind;

  /// What the person wrote: an event's or task's title, the text of the
  /// message of a reminder or scheduled message. Null when the server
  /// leaves it out (a reminder about a message that is gone or hidden).
  final String? title;

  /// A UTC instant: an event's start, a task's due time, a reminder's time,
  /// the moment a scheduled message goes out.
  final DateTime startsAt;
  final DateTime? endsAt;

  /// A task due on a day with no time of day.
  final bool allDay;
  final String? conversationId;
  final String? circleId;

  /// The event, task, reminder or scheduled message.
  final String targetId;

  /// A task's list; a reminder's message.
  final String? parentId;

  /// The conversation or circle it belongs to, as the server names it.
  final String? placeName;

  /// An event's place or link.
  final String? subtitle;
  final Map<String, dynamic> meta;

  String get key => '${kind.wire}:$targetId';

  DateTime get localStart => startsAt.toLocal();

  /// My answer to an event: `going`, `maybe` or `interested`.
  String? get rsvp => meta['status'] as String?;

  /// The call link code of an event that carries a scheduled call, while the
  /// link works; null for everything else.
  String? get callLinkCode {
    final code = meta['call_link_code'];
    return code is String && code.isNotEmpty ? code : null;
  }

  bool get hasCall => callLinkCode != null;

  /// 0 none, 1 low, 2 medium, 3 high (tasks).
  int get priority => (meta['priority'] as num?)?.toInt() ?? 0;

  /// The type of the message of a reminder (`image`, `voice`…), null when
  /// the message is gone.
  String? get messageType => meta['message_type'] as String?;

  /// The last moment the entry covers.
  DateTime get endOrStart => (endsAt ?? startsAt);

  /// A task past its due time, or a reminder that has come due and was not
  /// dismissed: something that needs me.
  bool isOverdue(DateTime now) =>
      (kind == AgendaKind.task || kind == AgendaKind.reminder) &&
      startsAt.isBefore(now.toUtc());

  /// The calendar day (local) the entry sits on.
  DateTime get day {
    final local = localStart;
    return DateTime(local.year, local.month, local.day);
  }

  static String? _text(Object? value) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? null : text;
  }
}

/// The groups of the list view, in order.
enum AgendaBucket { overdue, today, tomorrow, thisWeek, later }

/// [date] at midnight, local.
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// The first day of the week, as `DateTime.monday`…`DateTime.sunday`, for
/// [MaterialLocalizations.firstDayOfWeekIndex] (0 is Sunday).
int weekdayFromFirstDayIndex(int index) => index == 0 ? DateTime.sunday : index;

/// Where [item] sits in the list view at [now]: overdue ones first, then
/// by day. "This week" is what is left of the current week after tomorrow.
AgendaBucket agendaBucketOf(
  AgendaItem item,
  DateTime now, {
  int firstDayOfWeek = DateTime.monday,
}) {
  if (item.isOverdue(now)) {
    return AgendaBucket.overdue;
  }
  final today = dateOnly(now);
  final day = item.day;
  final difference = _daysBetween(today, day);
  if (difference <= 0) {
    return AgendaBucket.today;
  }
  if (difference == 1) {
    return AgendaBucket.tomorrow;
  }
  final sinceWeekStart = (today.weekday - firstDayOfWeek + 7) % 7;
  final weekEnd = DateTime(
    today.year,
    today.month,
    today.day - sinceWeekStart + 7,
  );
  return day.isBefore(weekEnd) ? AgendaBucket.thisWeek : AgendaBucket.later;
}

/// Whole calendar days from [from] to [to] (both at midnight, local),
/// right across daylight saving changes.
int _daysBetween(DateTime from, DateTime to) {
  return DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}

/// Whether the list view still shows [item]: overdue things stay until done;
/// anything else until its day is over.
bool agendaShowsInList(AgendaItem item, DateTime now) {
  if (item.isOverdue(now)) {
    return true;
  }
  return !item.endOrStart.toLocal().isBefore(dateOnly(now));
}

/// [items] for the list view, grouped by bucket and in time order inside
/// each (overdue: the longest overdue first). Empty buckets are left out.
Map<AgendaBucket, List<AgendaItem>> groupAgenda(
  Iterable<AgendaItem> items,
  DateTime now, {
  int firstDayOfWeek = DateTime.monday,
}) {
  final groups = <AgendaBucket, List<AgendaItem>>{};
  for (final item in items) {
    if (!agendaShowsInList(item, now)) {
      continue;
    }
    groups
        .putIfAbsent(
          agendaBucketOf(item, now, firstDayOfWeek: firstDayOfWeek),
          () => [],
        )
        .add(item);
  }
  for (final list in groups.values) {
    list.sort((a, b) {
      final byTime = a.startsAt.compareTo(b.startsAt);
      return byTime != 0 ? byTime : a.key.compareTo(b.key);
    });
  }
  return {for (final bucket in AgendaBucket.values) bucket: ?groups[bucket]};
}

/// How many entries need me right now: overdue tasks and reminders.
int agendaOverdueCount(Iterable<AgendaItem> items, DateTime now) =>
    items.where((item) => item.isOverdue(now)).length;

/// The weeks of [month] as a grid of days (local midnights), starting on
/// [firstDayOfWeek] and padded with the days of the neighbouring months.
List<List<DateTime>> monthGrid(
  DateTime month, {
  int firstDayOfWeek = DateTime.monday,
}) {
  final first = DateTime(month.year, month.month);
  final lead = (first.weekday - firstDayOfWeek + 7) % 7;
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final weeks = ((lead + daysInMonth) / 7).ceil();
  return [
    for (var week = 0; week < weeks; week++)
      [
        for (var weekday = 0; weekday < 7; weekday++)
          DateTime(month.year, month.month, 1 - lead + week * 7 + weekday),
      ],
  ];
}

/// The entries of [items] on [day], in time order.
List<AgendaItem> agendaOnDay(Iterable<AgendaItem> items, DateTime day) {
  final target = dateOnly(day);
  return [
    for (final item in items)
      if (item.day == target) item,
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
}

/// Entries by their day, for the month view's dots.
Map<DateTime, List<AgendaItem>> agendaByDay(Iterable<AgendaItem> items) {
  final byDay = <DateTime, List<AgendaItem>>{};
  for (final item in items) {
    byDay.putIfAbsent(item.day, () => []).add(item);
  }
  return byDay;
}
