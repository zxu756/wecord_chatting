import 'package:clock/clock.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/agenda/agenda_models.dart';
import 'package:wecord/features/agenda/agenda_repository.dart';
import 'package:wecord/features/agenda/calendar_feed_repository.dart';

/// An agenda that serves [items] inside the asked range, as the server does.
class FakeAgendaRepository implements AgendaRepository {
  FakeAgendaRepository([List<AgendaItem> items = const []])
    : items = [...items];

  List<AgendaItem> items;
  final requests = <({DateTime from, DateTime to})>[];

  /// Fails every fetch with this.
  Object? failWith;

  @override
  Future<List<AgendaItem>> fetch(DateTime from, DateTime to) async {
    requests.add((from: from, to: to));
    if (failWith case final error?) {
      throw error;
    }
    return [
      for (final item in items)
        if (!item.startsAt.isBefore(from.toUtc()) &&
            item.startsAt.isBefore(to.toUtc()))
          item,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }
}

/// The subscription settings of one person, and the secrets it handed out.
class FakeCalendarFeedRepository implements CalendarFeedRepository {
  FakeCalendarFeedRepository({
    this.enabled = false,
    this.includeContent = false,
    this.lastUsedAt,
  });

  bool enabled;
  bool includeContent;
  DateTime? lastUsedAt;
  final tokens = <String>[];
  final options = <({bool includeContent, int offset, String language})>[];
  var deleted = 0;

  /// Fails every write with this.
  Object? failWith;

  @override
  Future<CalendarFeedSettings> settings() async => CalendarFeedSettings(
    enabled: enabled,
    includeContent: includeContent,
    createdAt: enabled ? DateTime.utc(2026, 10, 18) : null,
    lastUsedAt: lastUsedAt,
  );

  @override
  Future<String> createToken({
    required bool includeContent,
    required int utcOffsetMinutes,
    required String language,
  }) async {
    if (failWith case final error?) {
      throw error;
    }
    final token = (tokens.length + 1).toString().padLeft(48, 'a');
    tokens.add(token);
    enabled = true;
    this.includeContent = includeContent;
    options.add((
      includeContent: includeContent,
      offset: utcOffsetMinutes,
      language: language,
    ));
    return token;
  }

  @override
  Future<void> setOptions({
    required bool includeContent,
    required int utcOffsetMinutes,
    required String language,
  }) async {
    if (failWith case final error?) {
      throw error;
    }
    this.includeContent = includeContent;
    options.add((
      includeContent: includeContent,
      offset: utcOffsetMinutes,
      language: language,
    ));
  }

  @override
  Future<void> delete() async {
    if (failWith case final error?) {
      throw error;
    }
    enabled = false;
    deleted++;
  }
}

class InMemoryCalendarFeedTokenStore implements CalendarFeedTokenStore {
  InMemoryCalendarFeedTokenStore([Map<String, String> initial = const {}])
    : tokens = {...initial};

  final Map<String, String> tokens;

  @override
  Future<String?> read(String userId) async => tokens[userId];

  @override
  Future<void> write(String userId, String token) async =>
      tokens[userId] = token;

  @override
  Future<void> clear(String userId) async => tokens.remove(userId);
}

List<Override> agendaOverrides({
  FakeAgendaRepository? agenda,
  FakeCalendarFeedRepository? feed,
  InMemoryCalendarFeedTokenStore? tokens,
}) => [
  agendaRepositoryProvider.overrideWithValue(agenda ?? FakeAgendaRepository()),
  calendarFeedRepositoryProvider.overrideWithValue(
    feed ?? FakeCalendarFeedRepository(),
  ),
  calendarFeedTokenStoreProvider.overrideWithValue(
    tokens ?? InMemoryCalendarFeedTokenStore(),
  ),
];

/// [day] (a local date) at [hour]:[minute], as the UTC instant the server
/// sends.
DateTime agendaAt(DateTime day, int hour, [int minute = 0]) =>
    DateTime(day.year, day.month, day.day, hour, minute).toUtc();

AgendaItem agendaItem(
  AgendaKind kind,
  String id, {
  required DateTime startsAt,
  String? title,
  DateTime? endsAt,
  bool allDay = false,
  String? conversationId = 'group-1',
  String? circleId,
  String? parentId,
  String? placeName = 'Trail crew',
  String? subtitle,
  Map<String, dynamic> meta = const {},
}) => AgendaItem(
  kind: kind,
  targetId: id,
  title: title,
  startsAt: startsAt,
  endsAt: endsAt,
  allDay: allDay,
  conversationId: conversationId,
  circleId: circleId,
  parentId: parentId,
  placeName: placeName,
  subtitle: subtitle,
  meta: meta,
);

/// A believable agenda around today: something overdue, a thing or two today
/// and tomorrow, one later this week when the week still has days, and one
/// next month.
List<AgendaItem> sampleAgenda([DateTime? now]) {
  final today = dateOnly(now ?? clock.now());
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final soon = DateTime(today.year, today.month, today.day + 3);
  final far = DateTime(today.year, today.month, today.day + 40);
  return [
    agendaItem(
      AgendaKind.task,
      'task-overdue',
      title: 'Send the trail permit form',
      startsAt: agendaAt(yesterday, 23, 59),
      allDay: true,
      parentId: 'list-1',
      meta: {'priority': 3},
    ),
    agendaItem(
      AgendaKind.reminder,
      'reminder-old',
      title: 'Bring the tripod',
      startsAt: agendaAt(yesterday, 9),
      conversationId: 'dm-1',
      placeName: 'Bart the Bold',
      parentId: 'message-1',
      meta: {'message_type': 'text', 'fired': true},
    ),
    agendaItem(
      AgendaKind.chatEvent,
      'event-today',
      title: 'Bouldering night',
      startsAt: agendaAt(today, 23),
      endsAt: agendaAt(today, 23, 30),
      subtitle: 'The gym on 5th',
      meta: {'status': 'going'},
    ),
    agendaItem(
      AgendaKind.task,
      'task-today',
      title: 'Book the cabin',
      startsAt: agendaAt(today, 23, 59),
      allDay: true,
      parentId: 'list-1',
    ),
    agendaItem(
      AgendaKind.scheduledMessage,
      'scheduled-tomorrow',
      title: 'Happy birthday, Grace!',
      startsAt: agendaAt(tomorrow, 9),
      conversationId: 'dm-2',
      placeName: 'Grace Hopper',
    ),
    agendaItem(
      AgendaKind.circleEvent,
      'circle-event-soon',
      title: 'Sunrise hike',
      startsAt: agendaAt(soon, 6, 30),
      endsAt: agendaAt(soon, 9),
      conversationId: null,
      circleId: 'circle-1',
      placeName: 'WeCord Hikers',
      subtitle: 'North trail',
      meta: {'status': 'interested'},
    ),
    agendaItem(
      AgendaKind.chatEvent,
      'event-far',
      title: 'Book club',
      startsAt: agendaAt(far, 19),
      meta: {'status': 'maybe'},
    ),
  ];
}
