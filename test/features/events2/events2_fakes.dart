// Fakes and samples for Events 2.0 (C10): an Events2Repository that records its
// calls, a small chat events repository, and events that use covers, repeats,
// questions, seats and check-in.
import 'dart:async';
import 'dart:typed_data';

import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/events2/events2_repository.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/models/circle_event.dart';
import 'package:wecord/shared/models/event_extras.dart';

const eventsConversationId = 'conv-1';
const eventsCircleId = 'circle-1';

const picnicQuestions = [
  EventQuestion(
    id: 'meal',
    label: 'Vegetarian?',
    type: EventQuestionType.choice,
    required: true,
    options: ['Yes', 'No'],
  ),
  EventQuestion(
    id: 'guests',
    label: 'How many guests?',
    type: EventQuestionType.number,
  ),
  EventQuestion(id: 'note', label: 'Anything we should know?'),
];

/// A chat event that uses Events 2.0.
ChatEvent chatEventWith({
  String id = 'e-1',
  String title = 'Saturday hike',
  DateTime? startsAt,
  EventExtras extras = const EventExtras(),
  ChatEventRsvp? myStatus,
  int going = 3,
  int maybe = 1,
  bool canManage = true,
  bool cancelled = false,
}) {
  return ChatEvent(
    id: id,
    conversationId: eventsConversationId,
    title: title,
    startsAt: startsAt ?? DateTime.now().add(const Duration(days: 2)),
    locationText: 'The trailhead',
    createdBy: 'user-1',
    creatorName: 'Ada',
    goingCount: going,
    maybeCount: maybe,
    myStatus: myStatus,
    canManage: canManage,
    cancelledAt: cancelled ? DateTime.now() : null,
    attendees: const [
      ChatEventAttendee(
        id: 'user-1',
        username: 'ada',
        displayName: 'Ada',
        status: ChatEventRsvp.going,
      ),
    ],
    extras: extras,
  );
}

/// A circle event that uses Events 2.0.
CircleEvent circleEventWith({
  String id = 'event-picnic',
  String title = 'Club picnic',
  DateTime? startsAt,
  EventExtras extras = const EventExtras(),
  int interested = 4,
  bool interestedByMe = false,
  bool canManage = true,
}) {
  return CircleEvent(
    id: id,
    circleId: eventsCircleId,
    title: title,
    locationType: CircleEventLocationType.external,
    locationText: 'Fairmount Park',
    startsAt: startsAt ?? DateTime.now().add(const Duration(days: 2)),
    interestedCount: interested,
    interestedByMe: interestedByMe,
    canManage: canManage,
    extras: extras,
  );
}

EventRegistrations sampleRegistrations() {
  return EventRegistrations(
    questions: picnicQuestions,
    capacity: 3,
    registrations: [
      EventRegistration(
        userId: 'user-1',
        name: 'Ada Lovelace',
        status: 'going',
        answers: const {'meal': 'Yes', 'guests': '2'},
        signedUpAt: DateTime(2026, 10, 20),
        checkedInAt: DateTime(2026, 10, 24, 10),
      ),
      const EventRegistration(
        userId: 'user-2',
        name: 'Bart, the "Bold"',
        status: 'going',
        answers: {'meal': 'No', 'note': 'Allergic to nuts'},
      ),
      const EventRegistration(userId: 'user-3', name: 'Grace', status: 'maybe'),
    ],
    waitlist: const [
      EventRegistration(
        userId: 'user-4',
        name: 'Linus',
        answers: {'meal': 'Yes'},
      ),
      EventRegistration(userId: 'user-5', name: 'Margaret'),
    ],
    walkIns: [
      EventRegistration(
        userId: 'user-6',
        name: 'Dennis',
        checkedInAt: DateTime(2026, 10, 24, 10, 5),
      ),
    ],
  );
}

class FakeEvents2Repository implements Events2Repository {
  final calls = <String>[];
  Map<String, String>? lastAnswers;
  Object? error;
  EventRegistrations registrations = sampleRegistrations();
  List<EventPhoto> photos = const [];
  var codeCounter = 0;
  EventCheckInResult? checkInResult = EventCheckInResult(
    kind: EventKind.chat,
    eventId: 'e-1',
    scopeId: eventsConversationId,
    title: 'Saturday hike',
    startsAt: DateTime(2026, 10, 24, 10),
    already: false,
  );

  Future<T> _run<T>(String call, T Function() body) async {
    calls.add(call);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return body();
  }

  @override
  Future<void> rsvpChat(
    String eventId,
    String? status, {
    Map<String, String>? answers,
  }) => _run('rsvp-chat $eventId $status', () {
    lastAnswers = answers;
  });

  @override
  Future<void> registerCircle(String eventId, Map<String, String> answers) =>
      _run('register $eventId', () {
        lastAnswers = answers;
      });

  @override
  Future<void> unregisterCircle(String eventId) =>
      _run('unregister $eventId', () {});

  @override
  Future<void> cancelSeries(EventKind kind, String eventId) =>
      _run('cancel-series ${kind.wire} $eventId', () {});

  @override
  Future<EventCheckInCode> createCheckInCode(EventKind kind, String eventId) =>
      _run(
        'code ${kind.wire} $eventId',
        () => EventCheckInCode(
          code: 'abcd2345wxyz',
          expiresAt: DateTime.now().add(const Duration(hours: 5)),
        ),
      );

  @override
  Future<EventCheckInResult> checkIn(String code) =>
      _run('check-in $code', () => checkInResult!);

  @override
  Future<void> setCheckedIn(
    EventKind kind,
    String eventId,
    String userId, {
    required bool checkedIn,
  }) => _run('tick $userId $checkedIn', () {});

  @override
  Future<EventRegistrations> listRegistrations(
    EventKind kind,
    String eventId,
  ) => _run('list ${kind.wire} $eventId', () => registrations);

  @override
  Future<List<EventPhoto>> listPhotos(EventKind kind, String eventId) =>
      _run('photos ${kind.wire} $eventId', () => photos);

  @override
  Future<EventPhoto> addPhoto(
    EventKind kind,
    String eventId,
    String scopeId,
    ChatImageUpload image,
  ) => _run('add-photo ${kind.wire} $eventId', () {
    final photo = EventPhoto(
      id: 'photo-${photos.length + 1}',
      bucket: kind.bucket,
      path: '$scopeId/events/new.jpg',
      userId: 'user-1',
      uploaderName: 'Ada',
      mine: true,
      canDelete: true,
    );
    photos = [photo, ...photos];
    return photo;
  });

  @override
  Future<void> deletePhoto(EventPhoto photo) {
    return _run('delete-photo ${photo.id}', () {
      photos = [
        for (final other in photos)
          if (other.id != photo.id) other,
      ];
    });
  }

  @override
  Future<String> uploadCover(
    EventKind kind,
    String scopeId,
    ChatImageUpload image,
  ) => _run('cover ${kind.wire} $scopeId', () => '$scopeId/events/cover-1.jpg');

  @override
  Future<String> pictureUrl(String bucket, String path) async =>
      'https://files.example.com/$bucket/$path';
}

/// A chat events repository over a list, recording what the widgets ask.
class FakeEventsChatRepository implements ChatEventsRepository {
  FakeEventsChatRepository(this.events);

  List<ChatEvent> events;
  final rsvps = <(String, ChatEventRsvp?)>[];
  final cancelled = <String>[];
  final created = <ChatEventDraft>[];
  final updated = <(String, ChatEventDraft)>[];

  /// Thrown by [createEvent] when set.
  Object? createError;

  @override
  Future<List<ChatEvent>> listEvents(
    String conversationId, {
    bool includePast = false,
  }) async => events;

  @override
  Future<ChatEvent?> getEvent(String eventId) async =>
      events.where((e) => e.id == eventId).firstOrNull;

  @override
  Future<ChatEvent> createEvent(
    String conversationId,
    ChatEventDraft draft,
  ) async {
    final failure = createError;
    if (failure != null) {
      throw failure;
    }
    created.add(draft);
    return chatEventWith(id: 'new-1', title: draft.title);
  }

  @override
  Future<ChatEvent> updateEvent(String eventId, ChatEventDraft draft) async {
    updated.add((eventId, draft));
    return events.firstWhere((e) => e.id == eventId);
  }

  @override
  Future<ChatEvent> cancelEvent(String eventId) async {
    cancelled.add(eventId);
    return events.firstWhere((e) => e.id == eventId);
  }

  @override
  Future<ChatEvent> rsvp(String eventId, ChatEventRsvp? status) async {
    rsvps.add((eventId, status));
    return events.firstWhere((e) => e.id == eventId);
  }

  @override
  Future<ChatEvent> setPinned(String eventId, {required bool pinned}) async =>
      events.firstWhere((e) => e.id == eventId);

  @override
  Stream<void> changes(String conversationId) => const Stream<void>.empty();

  @override
  Future<List<ChatEventReminder>> listReminders({int limit = 20}) async =>
      const [];

  @override
  Future<void> markRemindersRead([List<String>? ids]) async {}
}

/// Picks the image it was given.
class FakeEventImagePicker implements ImagePickerService {
  ChatImageUpload? next = ChatImageUpload(
    bytes: Uint8List.fromList(const [1, 2, 3]),
    fileName: 'cover.png',
    mimeType: 'image/png',
  );

  @override
  Future<ChatImageUpload?> pickImage() async => next;
}
