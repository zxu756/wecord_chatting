import 'package:wecord/shared/models/event_extras.dart';

/// How a member answered an event invitation.
enum ChatEventRsvp {
  going('going'),
  maybe('maybe'),
  declined('declined');

  const ChatEventRsvp(this.value);

  /// The `chat_event_rsvps.status` value.
  final String value;

  static ChatEventRsvp? maybeFromJson(Object? value) {
    for (final status in values) {
      if (status.value == value) {
        return status;
      }
    }
    return null;
  }
}

/// Where an event of a chat stands at a given time.
enum ChatEventStatus { upcoming, live, over, cancelled }

/// Someone who said Going or Maybe.
class ChatEventAttendee {
  const ChatEventAttendee({
    required this.id,
    required this.username,
    required this.displayName,
    required this.status,
    this.avatarUrl,
  });

  factory ChatEventAttendee.fromJson(Map<String, dynamic> json) {
    return ChatEventAttendee(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      status:
          ChatEventRsvp.maybeFromJson(json['status']) ?? ChatEventRsvp.going,
    );
  }

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final ChatEventRsvp status;

  String get name => displayName.trim().isEmpty ? username : displayName;
}

/// An event posted in a group chat or direct message, as
/// `list_chat_events` returns it.
class ChatEvent {
  const ChatEvent({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.startsAt,
    this.description,
    this.locationText,
    this.linkUrl,
    this.endsAt,
    this.reminderLeads = const [15],
    this.messageId,
    this.pinnedAt,
    this.cancelledAt,
    this.createdBy,
    this.creatorName,
    this.goingCount = 0,
    this.maybeCount = 0,
    this.declinedCount = 0,
    this.myStatus,
    this.attendees = const [],
    this.canManage = false,
    this.extras = EventExtras.none,
  });

  factory ChatEvent.fromJson(Map<String, dynamic> json) {
    final creator = json['creator'];
    return ChatEvent(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      title: json['title'] as String,
      description: _text(json['description']),
      locationText: _text(json['location_text']),
      linkUrl: _text(json['link_url']),
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: _time(json['ends_at']),
      reminderLeads: [
        for (final lead
            in json['reminder_leads'] as List<dynamic>? ?? const [15])
          (lead as num).toInt(),
      ],
      messageId: json['message_id'] as String?,
      pinnedAt: _time(json['pinned_at']),
      cancelledAt: _time(json['cancelled_at']),
      createdBy: json['created_by'] as String?,
      creatorName: creator is Map<String, dynamic>
          ? _text(creator['display_name']) ?? _text(creator['username'])
          : null,
      goingCount: (json['going_count'] as num?)?.toInt() ?? 0,
      maybeCount: (json['maybe_count'] as num?)?.toInt() ?? 0,
      declinedCount: (json['declined_count'] as num?)?.toInt() ?? 0,
      myStatus: ChatEventRsvp.maybeFromJson(json['my_status']),
      attendees: [
        for (final attendee in json['attendees'] as List<dynamic>? ?? const [])
          ChatEventAttendee.fromJson(attendee as Map<String, dynamic>),
      ],
      canManage: json['can_manage'] == true,
      extras: EventExtras.fromJson(json),
    );
  }

  static const maxTitleLength = 100;
  static const maxDescriptionLength = 2000;
  static const maxLocationLength = 200;
  static const maxLinkLength = 500;

  /// How long an event without an end time lasts (as on the server).
  static const defaultDuration = Duration(hours: 2);

  /// The reminders an event can ask for, in minutes before the start.
  static const reminderChoices = [15, 60];

  final String id;
  final String conversationId;
  final String title;
  final String? description;
  final String? locationText;
  final String? linkUrl;
  final DateTime startsAt;
  final DateTime? endsAt;

  /// Minutes before the start at which Going and Maybe members are
  /// reminded; empty for none.
  final List<int> reminderLeads;

  /// The chat message that announced it.
  final String? messageId;
  final DateTime? pinnedAt;
  final DateTime? cancelledAt;
  final String? createdBy;
  final String? creatorName;
  final int goingCount;
  final int maybeCount;
  final int declinedCount;
  final ChatEventRsvp? myStatus;

  /// Up to a dozen people who are Going (first) or Maybe.
  final List<ChatEventAttendee> attendees;
  final bool canManage;

  /// The cover, repeat, questions, seats and check-in of the event (Events
  /// 2.0).
  final EventExtras extras;

  bool get isCancelled => cancelledAt != null;
  bool get isPinned => pinnedAt != null;

  DateTime get effectiveEndsAt => endsAt ?? startsAt.add(defaultDuration);

  /// Whether the event has somewhere to go: a place, a link or both.
  bool get hasPlace => locationText != null || linkUrl != null;

  ChatEventStatus statusAt(DateTime now) {
    if (isCancelled) return ChatEventStatus.cancelled;
    if (!now.isBefore(effectiveEndsAt)) return ChatEventStatus.over;
    if (!now.isBefore(startsAt)) return ChatEventStatus.live;
    return ChatEventStatus.upcoming;
  }

  ChatEvent copyWithRsvp(ChatEventRsvp? status) {
    int adjust(int count, ChatEventRsvp which) {
      var next = count;
      if (myStatus == which) next--;
      if (status == which) next++;
      return next < 0 ? 0 : next;
    }

    return ChatEvent(
      id: id,
      conversationId: conversationId,
      title: title,
      startsAt: startsAt,
      description: description,
      locationText: locationText,
      linkUrl: linkUrl,
      endsAt: endsAt,
      reminderLeads: reminderLeads,
      messageId: messageId,
      pinnedAt: pinnedAt,
      cancelledAt: cancelledAt,
      createdBy: createdBy,
      creatorName: creatorName,
      goingCount: adjust(goingCount, ChatEventRsvp.going),
      maybeCount: adjust(maybeCount, ChatEventRsvp.maybe),
      declinedCount: adjust(declinedCount, ChatEventRsvp.declined),
      myStatus: status,
      attendees: attendees,
      canManage: canManage,
      extras: extras,
    );
  }

  static String? _text(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value;
  }

  static DateTime? _time(Object? value) {
    return value is String ? DateTime.parse(value) : null;
  }
}

/// A reminder in the inbox: an event that is about to start.
class ChatEventReminder {
  const ChatEventReminder({
    required this.id,
    required this.eventId,
    required this.conversationId,
    required this.title,
    required this.startsAt,
    required this.leadMinutes,
    required this.createdAt,
    required this.isUnread,
  });

  factory ChatEventReminder.fromJson(Map<String, dynamic> json) {
    return ChatEventReminder(
      id: json['reminder_id'] as String,
      eventId: json['event_id'] as String,
      conversationId: json['conversation_id'] as String,
      title: json['title'] as String,
      startsAt: DateTime.parse(json['starts_at'] as String),
      leadMinutes: (json['lead_minutes'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      isUnread: json['is_unread'] == true,
    );
  }

  final String id;
  final String eventId;
  final String conversationId;
  final String title;
  final DateTime startsAt;
  final int leadMinutes;
  final DateTime createdAt;
  final bool isUnread;
}
