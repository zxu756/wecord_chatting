import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/event_extras.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

final events2RepositoryProvider = Provider<Events2Repository>((ref) {
  try {
    return SupabaseEvents2Repository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedEvents2Repository();
  }
});

/// A call of Events 2.0 that the server (or the network) refused.
class EventException implements Exception {
  const EventException(this.failure);

  final EventFailure failure;

  @override
  String toString() => 'EventException(${failure.name})';
}

/// The parts of events that came with Events 2.0 (roadmap C10): signing up
/// with answers, ending a series, checking in, the organiser's list and the
/// pictures. Creating and changing an event, and the plain answers, are in
/// the chat and circle repositories as before.
abstract interface class Events2Repository {
  /// Says Going (with answers to the event's questions), Maybe or Can't for a
  /// chat event; null clears the answer. A full event puts a Going on the
  /// waiting list.
  Future<void> rsvpChat(
    String eventId,
    String? status, {
    Map<String, String>? answers,
  });

  /// Signs up for a circle event with answers; a full event puts the person on
  /// the waiting list.
  Future<void> registerCircle(String eventId, Map<String, String> answers);

  /// Leaves a circle event or its waiting list.
  Future<void> unregisterCircle(String eventId);

  /// Cancels the event and ends its series: no more occurrences are made and
  /// the ones ahead are cancelled.
  Future<void> cancelSeries(EventKind kind, String eventId);

  /// A new check-in code, for an organiser to show as a QR code. It cancels the
  /// one before.
  Future<EventCheckInCode> createCheckInCode(EventKind kind, String eventId);

  /// Checks the caller in with a scanned code.
  Future<EventCheckInResult> checkIn(String code);

  /// An organiser ticks [userId] on or off by hand.
  Future<void> setCheckedIn(
    EventKind kind,
    String eventId,
    String userId, {
    required bool checkedIn,
  });

  /// Everyone signed up with their answers, the waiting list in order and the
  /// walk-ins, for an organiser.
  Future<EventRegistrations> listRegistrations(EventKind kind, String eventId);

  Future<List<EventPhoto>> listPhotos(EventKind kind, String eventId);

  /// Uploads a picture to the chat's or the circle's folder and adds it to the
  /// event.
  Future<EventPhoto> addPhoto(
    EventKind kind,
    String eventId,
    String scopeId,
    ChatImageUpload image,
  );

  Future<void> deletePhoto(EventPhoto photo);

  /// Uploads a cover picture and returns its path, to send with the event.
  Future<String> uploadCover(
    EventKind kind,
    String scopeId,
    ChatImageUpload image,
  );

  /// A short-lived link to a picture of an event (a cover or a photo).
  Future<String> pictureUrl(String bucket, String path);
}

class SupabaseEvents2Repository implements Events2Repository {
  const SupabaseEvents2Repository(this._client);

  final SupabaseClient _client;

  static final _random = math.Random.secure();

  Future<T> _call<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (error) {
      throw EventException(EventFailure.fromMessage(error.message));
    }
  }

  @override
  Future<void> rsvpChat(
    String eventId,
    String? status, {
    Map<String, String>? answers,
  }) {
    return _call(
      () => _client.rpc<dynamic>(
        'rsvp_chat_event',
        params: {
          'target_event_id': eventId,
          'rsvp_status': status,
          'rsvp_answers': answers,
        },
      ),
    );
  }

  @override
  Future<void> registerCircle(String eventId, Map<String, String> answers) {
    return _call(
      () => _client.rpc<dynamic>(
        'register_circle_event',
        params: {'target_event_id': eventId, 'event_answers': answers},
      ),
    );
  }

  @override
  Future<void> unregisterCircle(String eventId) {
    return _call(
      () => _client.rpc<dynamic>(
        'unregister_circle_event',
        params: {'target_event_id': eventId},
      ),
    );
  }

  @override
  Future<void> cancelSeries(EventKind kind, String eventId) {
    return _call(
      () => _client.rpc<dynamic>(
        kind == EventKind.chat ? 'cancel_chat_event' : 'cancel_circle_event',
        params: {'target_event_id': eventId, 'cancel_series': true},
      ),
    );
  }

  @override
  Future<EventCheckInCode> createCheckInCode(EventKind kind, String eventId) {
    return _call(() async {
      final row = await _client.rpc<dynamic>(
        'create_event_check_in_code',
        params: {'p_kind': kind.wire, 'p_event_id': eventId},
      );
      return EventCheckInCode.fromJson(Map<String, dynamic>.from(row as Map));
    });
  }

  @override
  Future<EventCheckInResult> checkIn(String code) {
    return _call(() async {
      final row = await _client.rpc<dynamic>(
        'check_in_event',
        params: {'p_code': code},
      );
      return EventCheckInResult.fromJson(Map<String, dynamic>.from(row as Map));
    });
  }

  @override
  Future<void> setCheckedIn(
    EventKind kind,
    String eventId,
    String userId, {
    required bool checkedIn,
  }) {
    return _call(
      () => _client.rpc<dynamic>(
        'set_event_check_in',
        params: {
          'p_kind': kind.wire,
          'p_event_id': eventId,
          'p_user_id': userId,
          'p_checked_in': checkedIn,
        },
      ),
    );
  }

  @override
  Future<EventRegistrations> listRegistrations(EventKind kind, String eventId) {
    return _call(() async {
      final row = await _client.rpc<dynamic>(
        'list_event_registrations',
        params: {'p_kind': kind.wire, 'p_event_id': eventId},
      );
      return EventRegistrations.fromJson(Map<String, dynamic>.from(row as Map));
    });
  }

  @override
  Future<List<EventPhoto>> listPhotos(EventKind kind, String eventId) {
    return _call(() async {
      final rows = await _client.rpc<List<dynamic>>(
        'list_event_photos',
        params: {'p_kind': kind.wire, 'p_event_id': eventId},
      );
      return [
        for (final row in rows)
          EventPhoto.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    });
  }

  String _newPath(String scopeId, String folder, ChatImageUpload image) {
    final seed =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${_random.nextInt(1 << 32).toRadixString(36)}';
    final extension = switch (image.mimeType.toLowerCase()) {
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      _ => 'jpg',
    };
    return '$scopeId/events/$folder$seed.$extension';
  }

  Future<void> _upload(String bucket, String path, ChatImageUpload image) {
    return _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          image.bytes,
          fileOptions: FileOptions(contentType: image.mimeType),
        )
        .timeout(const Duration(seconds: 60));
  }

  @override
  Future<EventPhoto> addPhoto(
    EventKind kind,
    String eventId,
    String scopeId,
    ChatImageUpload image,
  ) {
    return _call(() async {
      final path = _newPath(scopeId, '', image);
      await _upload(kind.bucket, path, image);
      final row = await _client.rpc<dynamic>(
        'add_event_photo',
        params: {'p_kind': kind.wire, 'p_event_id': eventId, 'p_path': path},
      );
      return EventPhoto.fromJson(Map<String, dynamic>.from(row as Map));
    });
  }

  @override
  Future<void> deletePhoto(EventPhoto photo) async {
    await _call(
      () => _client.rpc<dynamic>(
        'delete_event_photo',
        params: {'p_photo_id': photo.id},
      ),
    );
    try {
      await _client.storage.from(photo.bucket).remove([photo.path]);
    } on Object {
      // The picture is off the event; the file may stay until the person's
      // storage is cleared.
    }
  }

  @override
  Future<String> uploadCover(
    EventKind kind,
    String scopeId,
    ChatImageUpload image,
  ) async {
    final path = _newPath(scopeId, 'cover-', image);
    await _upload(kind.bucket, path, image);
    return path;
  }

  @override
  Future<String> pictureUrl(String bucket, String path) {
    return _client.storage.from(bucket).createSignedUrl(path, 3600);
  }
}

class UninitializedEvents2Repository implements Events2Repository {
  const UninitializedEvents2Repository();

  Future<T> _fail<T>() =>
      Future.error(StateError('Events need a signed-in session.'));

  @override
  Future<void> rsvpChat(
    String eventId,
    String? status, {
    Map<String, String>? answers,
  }) => _fail();

  @override
  Future<void> registerCircle(String eventId, Map<String, String> answers) =>
      _fail();

  @override
  Future<void> unregisterCircle(String eventId) => _fail();

  @override
  Future<void> cancelSeries(EventKind kind, String eventId) => _fail();

  @override
  Future<EventCheckInCode> createCheckInCode(EventKind kind, String eventId) =>
      _fail();

  @override
  Future<EventCheckInResult> checkIn(String code) => _fail();

  @override
  Future<void> setCheckedIn(
    EventKind kind,
    String eventId,
    String userId, {
    required bool checkedIn,
  }) => _fail();

  @override
  Future<EventRegistrations> listRegistrations(
    EventKind kind,
    String eventId,
  ) async => const EventRegistrations();

  @override
  Future<List<EventPhoto>> listPhotos(EventKind kind, String eventId) async =>
      const [];

  @override
  Future<EventPhoto> addPhoto(
    EventKind kind,
    String eventId,
    String scopeId,
    ChatImageUpload image,
  ) => _fail();

  @override
  Future<void> deletePhoto(EventPhoto photo) => _fail();

  @override
  Future<String> uploadCover(
    EventKind kind,
    String scopeId,
    ChatImageUpload image,
  ) => _fail();

  @override
  Future<String> pictureUrl(String bucket, String path) => _fail();
}
