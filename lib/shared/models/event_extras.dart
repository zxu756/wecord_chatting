import 'package:flutter/foundation.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Which kind of event: one in a group or direct chat, or one of a circle.
enum EventKind {
  chat('chat', 'chat-images'),
  circle('circle', 'chat-media');

  const EventKind(this.wire, this.bucket);

  /// What the Events 2.0 functions take as their `p_kind`.
  final String wire;

  /// The Storage bucket the event's cover and pictures live in: the chat's
  /// own folder (`chat-images/<conversation id>/...`) or the circle's
  /// (`chat-media/<circle id>/...`).
  final String bucket;
}

/// How an event repeats. The next one is made once the current one starts.
enum EventRecurrence {
  none(null),
  weekly('weekly'),
  biweekly('biweekly'),
  monthly('monthly');

  const EventRecurrence(this.wire);

  final String? wire;

  String get label => switch (this) {
    none => tr('Does not repeat'),
    weekly => tr('Every week'),
    biweekly => tr('Every two weeks'),
    monthly => tr('Every month'),
  };

  static EventRecurrence fromJson(Object? value) {
    for (final candidate in values) {
      if (candidate.wire != null && candidate.wire == value) {
        return candidate;
      }
    }
    return none;
  }
}

enum EventQuestionType {
  text('text'),
  number('number'),
  choice('choice');

  const EventQuestionType(this.wire);

  final String wire;

  String get label => switch (this) {
    text => tr('Text'),
    number => tr('Number'),
    choice => tr('Choice'),
  };

  static EventQuestionType fromJson(Object? value) {
    for (final candidate in values) {
      if (candidate.wire == value) {
        return candidate;
      }
    }
    return text;
  }
}

/// A question asked when someone signs up for an event.
@immutable
class EventQuestion {
  const EventQuestion({
    required this.id,
    required this.label,
    this.type = EventQuestionType.text,
    this.required = false,
    this.options = const [],
  });

  factory EventQuestion.fromJson(Map<String, dynamic> json) {
    return EventQuestion(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      type: EventQuestionType.fromJson(json['type']),
      required: json['required'] == true,
      options: [
        for (final option in json['options'] as List<dynamic>? ?? const [])
          option.toString(),
      ],
    );
  }

  static const maxCount = 5;
  static const maxLabelLength = 80;
  static const maxOptionLength = 40;
  static const maxAnswerLength = 500;
  static const minOptions = 2;
  static const maxOptions = 8;

  final String id;
  final String label;
  final EventQuestionType type;
  final bool required;
  final List<String> options;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label.trim(),
    'type': type.wire,
    'required': required,
    if (type == EventQuestionType.choice) 'options': options,
  };

  EventQuestion copyWith({
    String? label,
    EventQuestionType? type,
    bool? required,
    List<String>? options,
  }) {
    return EventQuestion(
      id: id,
      label: label ?? this.label,
      type: type ?? this.type,
      required: required ?? this.required,
      options: options ?? this.options,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EventQuestion &&
      other.id == id &&
      other.label == label &&
      other.type == type &&
      other.required == required &&
      listEquals(other.options, options);

  @override
  int get hashCode => Object.hash(id, label, type, required, options.length);
}

/// The Events 2.0 part of an event as the server sends it, shared by chat
/// events and circle events.
@immutable
class EventExtras {
  const EventExtras({
    this.coverPath,
    this.recurrence = EventRecurrence.none,
    this.recurrenceTimeZone,
    this.seriesId,
    this.questions = const [],
    this.capacity,
    this.waitlistCount = 0,
    this.myWaitlisted = false,
    this.myAnswers = const {},
    this.checkedInCount = 0,
    this.myCheckedIn = false,
    this.photoCount = 0,
    this.callLinkCode,
  });

  factory EventExtras.fromJson(Map<String, dynamic> json) {
    final answers = json['my_answers'];
    return EventExtras(
      coverPath: switch (json['cover_path']) {
        final String path when path.isNotEmpty => path,
        _ => null,
      },
      recurrence: EventRecurrence.fromJson(json['recurrence']),
      recurrenceTimeZone: json['recurrence_tz'] as String?,
      seriesId: json['series_id'] as String?,
      questions: [
        for (final question in json['questions'] as List<dynamic>? ?? const [])
          EventQuestion.fromJson(Map<String, dynamic>.from(question as Map)),
      ],
      capacity: (json['capacity'] as num?)?.toInt(),
      waitlistCount: (json['waitlist_count'] as num?)?.toInt() ?? 0,
      myWaitlisted: json['my_waitlisted'] == true,
      myAnswers: answers is Map
          ? {
              for (final entry in answers.entries)
                entry.key.toString(): entry.value.toString(),
            }
          : const {},
      checkedInCount: (json['checked_in_count'] as num?)?.toInt() ?? 0,
      myCheckedIn: json['my_checked_in'] == true,
      photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
      callLinkCode: switch (json['call_link_code']) {
        final String code when code.isNotEmpty => code,
        _ => null,
      },
    );
  }

  static const none = EventExtras();

  /// A file under the chat's or the circle's folder in Storage.
  final String? coverPath;
  final EventRecurrence recurrence;
  final String? recurrenceTimeZone;
  final String? seriesId;
  final List<EventQuestion> questions;
  final int? capacity;
  final int waitlistCount;
  final bool myWaitlisted;
  final Map<String, String> myAnswers;
  final int checkedInCount;
  final bool myCheckedIn;
  final int photoCount;

  /// The code of the event's call link while it works (scheduled calls); null
  /// for an event without a call.
  final String? callLinkCode;

  bool get hasCall => callLinkCode != null;

  bool get repeats => recurrence != EventRecurrence.none;
  bool get hasQuestions => questions.isNotEmpty;
  bool get hasCapacity => capacity != null;

  /// Whether anything of Events 2.0 is in use (for showing its chips).
  bool get isPlain =>
      coverPath == null &&
      !repeats &&
      !hasQuestions &&
      !hasCapacity &&
      waitlistCount == 0 &&
      checkedInCount == 0 &&
      photoCount == 0 &&
      !hasCall;

  /// Whether all seats are taken, given how many are.
  bool isFull(int seatsTaken) => capacity != null && seatsTaken >= capacity!;

  int? seatsLeft(int seatsTaken) =>
      capacity == null ? null : (capacity! - seatsTaken).clamp(0, capacity!);
}

/// What an organiser sets for an event: sent as `event_options`.
@immutable
class EventOptions {
  const EventOptions({
    this.recurrence = EventRecurrence.none,
    this.coverPath,
    this.questions = const [],
    this.capacity,
    this.timeZone,
    this.call,
  });

  /// The options an event has now, to edit. [supportsCall] is true for the
  /// events of chats, which can carry a call.
  factory EventOptions.fromExtras(
    EventExtras extras, {
    bool supportsCall = false,
  }) {
    return EventOptions(
      recurrence: extras.recurrence,
      coverPath: extras.coverPath,
      questions: extras.questions,
      capacity: extras.capacity,
      timeZone: extras.recurrenceTimeZone,
      call: supportsCall ? extras.hasCall : null,
    );
  }

  static const maxCapacity = 10000;

  final EventRecurrence recurrence;
  final String? coverPath;
  final List<EventQuestion> questions;
  final int? capacity;

  /// The IANA zone of this device. A repeating event keeps its wall-clock time
  /// in it, whatever daylight saving does.
  final String? timeZone;

  /// Whether the event carries a call (scheduled calls): true or false for the
  /// events of chats, null where the event cannot have one (circle events), in
  /// which case it is not sent.
  final bool? call;

  EventOptions copyWith({
    EventRecurrence? recurrence,
    Object? coverPath = _keep,
    List<EventQuestion>? questions,
    Object? capacity = _keep,
    bool? call,
  }) {
    return EventOptions(
      recurrence: recurrence ?? this.recurrence,
      coverPath: identical(coverPath, _keep)
          ? this.coverPath
          : coverPath as String?,
      questions: questions ?? this.questions,
      capacity: identical(capacity, _keep) ? this.capacity : capacity as int?,
      timeZone: timeZone,
      call: call ?? this.call,
    );
  }

  /// The `event_options` argument. All keys are always sent, so an update
  /// takes back what the person cleared.
  Map<String, Object?> toJson() => {
    'recurrence': recurrence.wire,
    if (timeZone != null) 'timezone': timeZone,
    'cover_path': coverPath,
    'questions': [for (final question in questions) question.toJson()],
    'capacity': capacity,
    'call': ?call,
  };

  @override
  bool operator ==(Object other) =>
      other is EventOptions &&
      other.recurrence == recurrence &&
      other.coverPath == coverPath &&
      listEquals(other.questions, questions) &&
      other.capacity == capacity &&
      other.call == call;

  @override
  int get hashCode =>
      Object.hash(recurrence, coverPath, questions.length, capacity, call);
}

const Object _keep = Object();

/// Someone who signed up (or waits, or walked in), for an organiser.
@immutable
class EventRegistration {
  const EventRegistration({
    required this.userId,
    required this.name,
    this.username = '',
    this.avatarUrl,
    this.status,
    this.answers = const {},
    this.signedUpAt,
    this.checkedInAt,
  });

  factory EventRegistration.fromJson(Map<String, dynamic> json) {
    final answers = json['answers'];
    final displayName = (json['display_name'] as String?)?.trim() ?? '';
    final username = json['username'] as String? ?? '';
    return EventRegistration(
      userId: json['user_id'] as String,
      name: displayName.isEmpty ? username : displayName,
      username: username,
      avatarUrl: json['avatar_url'] as String?,
      status: json['status'] as String?,
      answers: answers is Map
          ? {
              for (final entry in answers.entries)
                entry.key.toString(): entry.value.toString(),
            }
          : const {},
      signedUpAt: _time(json['signed_up_at'] ?? json['joined_at']),
      checkedInAt: _time(json['checked_in_at']),
    );
  }

  final String userId;
  final String name;
  final String username;
  final String? avatarUrl;

  /// going / maybe / declined for chat events; null for the waiting list and
  /// walk-ins.
  final String? status;
  final Map<String, String> answers;
  final DateTime? signedUpAt;
  final DateTime? checkedInAt;

  bool get checkedIn => checkedInAt != null;
}

/// The organiser's view of an event's sign-ups.
@immutable
class EventRegistrations {
  const EventRegistrations({
    this.questions = const [],
    this.capacity,
    this.registrations = const [],
    this.waitlist = const [],
    this.walkIns = const [],
  });

  factory EventRegistrations.fromJson(Map<String, dynamic> json) {
    List<EventRegistration> people(Object? value) => [
      for (final row in value as List<dynamic>? ?? const [])
        EventRegistration.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
    return EventRegistrations(
      questions: [
        for (final question in json['questions'] as List<dynamic>? ?? const [])
          EventQuestion.fromJson(Map<String, dynamic>.from(question as Map)),
      ],
      capacity: (json['capacity'] as num?)?.toInt(),
      registrations: people(json['registrations']),
      waitlist: people(json['waitlist']),
      walkIns: people(json['walk_ins']),
    );
  }

  final List<EventQuestion> questions;
  final int? capacity;
  final List<EventRegistration> registrations;
  final List<EventRegistration> waitlist;
  final List<EventRegistration> walkIns;

  int get checkedInCount =>
      registrations.where((r) => r.checkedIn).length + walkIns.length;
}

/// A picture added to an event.
@immutable
class EventPhoto {
  const EventPhoto({
    required this.id,
    required this.bucket,
    required this.path,
    required this.userId,
    this.uploaderName = '',
    this.createdAt,
    this.mine = false,
    this.canDelete = false,
  });

  factory EventPhoto.fromJson(Map<String, dynamic> json) {
    return EventPhoto(
      id: json['id'] as String,
      bucket: json['bucket'] as String,
      path: json['path'] as String,
      userId: json['user_id'] as String? ?? '',
      uploaderName: json['uploader_name'] as String? ?? '',
      createdAt: _time(json['created_at']),
      mine: json['mine'] == true,
      canDelete: json['can_delete'] == true,
    );
  }

  final String id;
  final String bucket;
  final String path;
  final String userId;
  final String uploaderName;
  final DateTime? createdAt;
  final bool mine;
  final bool canDelete;
}

/// A check-in code an organiser shows as a QR code.
@immutable
class EventCheckInCode {
  const EventCheckInCode({required this.code, required this.expiresAt});

  factory EventCheckInCode.fromJson(Map<String, dynamic> json) {
    return EventCheckInCode(
      code: json['code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final String code;
  final DateTime expiresAt;
}

/// What scanning a check-in code did.
@immutable
class EventCheckInResult {
  const EventCheckInResult({
    required this.kind,
    required this.eventId,
    required this.scopeId,
    required this.title,
    required this.startsAt,
    required this.already,
  });

  factory EventCheckInResult.fromJson(Map<String, dynamic> json) {
    return EventCheckInResult(
      kind: json['kind'] == 'circle' ? EventKind.circle : EventKind.chat,
      eventId: json['event_id'] as String,
      scopeId: json['scope_id'] as String,
      title: json['title'] as String? ?? '',
      startsAt: DateTime.parse(json['starts_at'] as String),
      already: json['already'] == true,
    );
  }

  final EventKind kind;
  final String eventId;

  /// The conversation (chat events) or the circle (circle events).
  final String scopeId;
  final String title;
  final DateTime startsAt;

  /// The person was already checked in.
  final bool already;
}

/// Why a call of Events 2.0 failed, from the server's error.
enum EventFailure {
  needsAnswers,
  eventOver,
  notAllowed,
  waitingList,
  codeInvalid,
  checkInNotOpen,
  photoLimit,
  other;

  String get message => switch (this) {
    needsAnswers => tr('Please answer the required questions.'),
    eventOver => tr('This event is over or was cancelled.'),
    notAllowed => tr('You cannot do that.'),
    waitingList => tr('You are on the waiting list.'),
    codeInvalid => tr('This check-in code does not work. It may have expired.'),
    checkInNotOpen => tr('Check-in has not opened yet.'),
    photoLimit => tr('No more pictures can be added.'),
    other => tr('Something went wrong. Try again.'),
  };

  /// Reads the message of a Postgres error the functions raise.
  static EventFailure fromMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('required questions')) return needsAnswers;
    if (lower.contains('over') || lower.contains('cancelled')) {
      return eventOver;
    }
    if (lower.contains('waiting list')) return waitingList;
    if (lower.contains('check-in code')) return codeInvalid;
    if (lower.contains('has not opened')) return checkInNotOpen;
    if (lower.contains('pictures') && lower.contains('up to') ||
        lower.contains('all the pictures')) {
      return photoLimit;
    }
    if (lower.contains('permission') ||
        lower.contains('cannot') ||
        lower.contains('not found') ||
        lower.contains('suspended') ||
        lower.contains('taken down') ||
        lower.contains('only people who')) {
      return notAllowed;
    }
    return other;
  }
}

DateTime? _time(Object? value) {
  return value is String ? DateTime.tryParse(value) : null;
}
