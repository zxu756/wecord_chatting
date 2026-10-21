import 'package:wecord/shared/models/event_extras.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_notification_settings.dart';
import 'package:wecord/shared/models/profile.dart';

/// Where an event happens: a voice or text channel of the circle, or
/// somewhere else described in text.
enum CircleEventLocationType {
  voice('voice', 'Voice channel'),
  text('text', 'Text channel'),
  external('external', 'Somewhere else');

  const CircleEventLocationType(this.value, this._label);

  /// The `circle_events.location_type` value.
  final String value;
  final String _label;

  String get label => tr(_label);

  /// Unknown values (newer servers) read as external.
  static CircleEventLocationType fromJson(Object? value) {
    for (final type in values) {
      if (type.value == value) {
        return type;
      }
    }
    return external;
  }
}

/// Where an event stands at a given time.
enum CircleEventStatus { scheduled, ongoing, over, cancelled }

/// A member shown with an event: its creator or someone interested.
class CircleEventPerson {
  const CircleEventPerson({required this.profile, this.nickname});

  factory CircleEventPerson.fromJson(Map<String, dynamic> json) {
    return CircleEventPerson(
      profile: Profile.fromJson(json),
      nickname: json['nickname'] as String?,
    );
  }

  final Profile profile;

  /// Their nickname in the event's circle, if any.
  final String? nickname;

  /// Nickname, then display name, then username.
  String get name {
    final nickname = this.nickname?.trim();
    if (nickname != null && nickname.isNotEmpty) {
      return nickname;
    }
    return profile.displayName.trim().isEmpty
        ? profile.username
        : profile.displayName;
  }
}

/// A scheduled event of a circle, as `list_circle_events` returns it.
class CircleEvent {
  const CircleEvent({
    required this.id,
    required this.circleId,
    required this.title,
    required this.locationType,
    required this.startsAt,
    this.description,
    this.channelId,
    this.channelName,
    this.channelConversationId,
    this.locationText,
    this.endsAt,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.cancelledAt,
    this.creator,
    this.interestedCount = 0,
    this.interestedByMe = false,
    this.canManage = false,
    this.extras = EventExtras.none,
  });

  factory CircleEvent.fromJson(Map<String, dynamic> json) {
    final creator = json['creator'];
    return CircleEvent(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      title: json['title'] as String,
      description: switch (json['description']) {
        final String text when text.trim().isNotEmpty => text,
        _ => null,
      },
      locationType: CircleEventLocationType.fromJson(json['location_type']),
      channelId: json['channel_id'] as String?,
      channelName: json['channel_name'] as String?,
      channelConversationId: json['channel_conversation_id'] as String?,
      locationText: json['location_text'] as String?,
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: _parseTime(json['ends_at']),
      createdBy: json['created_by'] as String?,
      createdAt: _parseTime(json['created_at']),
      updatedAt: _parseTime(json['updated_at']),
      cancelledAt: _parseTime(json['cancelled_at']),
      creator: creator is Map<String, dynamic>
          ? CircleEventPerson.fromJson(creator)
          : null,
      interestedCount: (json['interested_count'] as num?)?.toInt() ?? 0,
      interestedByMe: json['interested_by_me'] == true,
      canManage: json['can_manage'] == true,
      extras: EventExtras.fromJson(json),
    );
  }

  static const maxTitleLength = 100;
  static const maxDescriptionLength = 2000;
  static const maxLocationLength = 200;

  /// How long an event without an end time lasts (as on the server).
  static const defaultDuration = Duration(hours: 2);

  /// How long before the start interested members are reminded.
  static const reminderLead = Duration(minutes: 15);

  final String id;
  final String circleId;
  final String title;
  final String? description;
  final CircleEventLocationType locationType;

  /// The voice or text channel; null for external events and once the
  /// channel is deleted.
  final String? channelId;
  final String? channelName;
  final String? channelConversationId;

  /// The place of an external event.
  final String? locationText;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? cancelledAt;

  /// Null when the creator's account is gone.
  final CircleEventPerson? creator;
  final int interestedCount;
  final bool interestedByMe;

  /// The current user created the event or may manage events.
  final bool canManage;

  /// The cover, repeat, questions, seats and check-in of the event (Events
  /// 2.0).
  final EventExtras extras;

  /// When the event is over: its end, or [defaultDuration] after it starts.
  DateTime get effectiveEndsAt => endsAt ?? startsAt.add(defaultDuration);

  bool get isCancelled => cancelledAt != null;

  CircleEventStatus statusAt(DateTime now) {
    if (isCancelled) {
      return CircleEventStatus.cancelled;
    }
    if (!effectiveEndsAt.isAfter(now)) {
      return CircleEventStatus.over;
    }
    if (!startsAt.isAfter(now)) {
      return CircleEventStatus.ongoing;
    }
    return CircleEventStatus.scheduled;
  }

  /// Upcoming or ongoing, so interest can still be marked.
  bool isActiveAt(DateTime now) {
    final status = statusAt(now);
    return status == CircleEventStatus.scheduled ||
        status == CircleEventStatus.ongoing;
  }

  /// What the event shows as its place: `#channel`, the external place,
  /// or a note that the channel is gone.
  String get locationLabel {
    if (locationType == CircleEventLocationType.external) {
      return locationText ?? '';
    }
    final name = channelName;
    return name == null ? tr('Deleted channel') : '#$name';
  }

  CircleEvent copyWith({bool? interestedByMe, int? interestedCount}) {
    return CircleEvent(
      id: id,
      circleId: circleId,
      title: title,
      description: description,
      locationType: locationType,
      channelId: channelId,
      channelName: channelName,
      channelConversationId: channelConversationId,
      locationText: locationText,
      startsAt: startsAt,
      endsAt: endsAt,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
      cancelledAt: cancelledAt,
      creator: creator,
      interestedCount: interestedCount ?? this.interestedCount,
      interestedByMe: interestedByMe ?? this.interestedByMe,
      canManage: canManage,
      extras: extras,
    );
  }
}

/// An event the current user is interested in that starts within a day,
/// as `list_my_upcoming_event_reminders` returns it.
class CircleEventReminder {
  const CircleEventReminder({
    required this.eventId,
    required this.circleId,
    required this.circleName,
    required this.title,
    required this.startsAt,
    this.location,
    this.notificationLevel = CircleNotificationLevel.all,
    this.mutedUntil,
  });

  factory CircleEventReminder.fromJson(Map<String, dynamic> json) {
    return CircleEventReminder(
      eventId: json['event_id'] as String,
      circleId: json['circle_id'] as String,
      circleName: json['circle_name'] as String? ?? '',
      title: json['title'] as String,
      startsAt: DateTime.parse(json['starts_at'] as String),
      location: json['location'] as String?,
      notificationLevel: CircleNotificationLevel.fromJson(
        json['notification_level'] as String?,
      ),
      mutedUntil: _parseTime(json['muted_until']),
    );
  }

  final String eventId;
  final String circleId;
  final String circleName;
  final String title;
  final DateTime startsAt;
  final String? location;

  /// The current user's notification settings for the circle.
  final CircleNotificationLevel notificationLevel;
  final DateTime? mutedUntil;
}

/// The notification payload of an event reminder; tapping it opens the
/// event.
String circleEventNotificationPayload(String circleId, String eventId) {
  return 'circle-event:$circleId:$eventId';
}

/// The circle and event of an event reminder's [payload], or null for
/// other notifications.
({String circleId, String eventId})? parseCircleEventNotificationPayload(
  String payload,
) {
  final parts = payload.split(':');
  if (parts.length != 3 ||
      parts[0] != 'circle-event' ||
      parts[1].isEmpty ||
      parts[2].isEmpty) {
    return null;
  }
  return (circleId: parts[1], eventId: parts[2]);
}

DateTime? _parseTime(Object? value) {
  return value is String ? DateTime.tryParse(value) : null;
}
