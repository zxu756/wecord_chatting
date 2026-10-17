import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/chat_event.dart';

final chatEventsRepositoryProvider = Provider<ChatEventsRepository>((ref) {
  try {
    return SupabaseChatEventsRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedChatEventsRepository();
  }
});

/// What a person fills in for an event.
class ChatEventDraft {
  const ChatEventDraft({
    required this.title,
    required this.startsAt,
    this.endsAt,
    this.description,
    this.location,
    this.link,
    this.reminderLeads = const [15],
    this.pin = false,
  });

  final String title;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? description;
  final String? location;
  final String? link;
  final List<int> reminderLeads;

  /// Pin it to the chat header (a new event only).
  final bool pin;
}

abstract interface class ChatEventsRepository {
  /// The chat's events, soonest first; past and cancelled ones too when
  /// [includePast].
  Future<List<ChatEvent>> listEvents(
    String conversationId, {
    bool includePast = false,
  });

  Future<ChatEvent?> getEvent(String eventId);

  Future<ChatEvent> createEvent(String conversationId, ChatEventDraft draft);

  Future<ChatEvent> updateEvent(String eventId, ChatEventDraft draft);

  Future<ChatEvent> cancelEvent(String eventId);

  /// Sets the caller's answer; null clears it.
  Future<ChatEvent> rsvp(String eventId, ChatEventRsvp? status);

  Future<ChatEvent> setPinned(String eventId, {required bool pinned});

  /// Fires when an event or an answer in the chat changes.
  Stream<void> changes(String conversationId);

  /// The caller's reminders from the last two days, newest first.
  Future<List<ChatEventReminder>> listReminders({int limit = 20});

  Future<void> markRemindersRead([List<String>? ids]);
}

class SupabaseChatEventsRepository implements ChatEventsRepository {
  const SupabaseChatEventsRepository(this._client);

  final SupabaseClient _client;

  ChatEvent _event(Object? json) =>
      ChatEvent.fromJson(Map<String, dynamic>.from(json! as Map));

  @override
  Future<List<ChatEvent>> listEvents(
    String conversationId, {
    bool includePast = false,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_chat_events',
      params: {
        'target_conversation_id': conversationId,
        'include_past': includePast,
      },
    );
    return [for (final row in rows) _event(row)];
  }

  @override
  Future<ChatEvent?> getEvent(String eventId) async {
    final row = await _client.rpc<dynamic>(
      'get_chat_event',
      params: {'target_event_id': eventId},
    );
    return row == null ? null : _event(row);
  }

  Map<String, dynamic> _fields(ChatEventDraft draft) => {
    'event_title': draft.title.trim(),
    'event_starts_at': draft.startsAt.toUtc().toIso8601String(),
    'event_ends_at': draft.endsAt?.toUtc().toIso8601String(),
    'event_description': draft.description?.trim(),
    'event_location': draft.location?.trim(),
    'event_link': draft.link?.trim(),
    'event_reminder_leads': draft.reminderLeads,
  };

  @override
  Future<ChatEvent> createEvent(
    String conversationId,
    ChatEventDraft draft,
  ) async {
    final row = await _client.rpc<dynamic>(
      'create_chat_event',
      params: {
        'target_conversation_id': conversationId,
        ..._fields(draft),
        'pin_event': draft.pin,
      },
    );
    return _event(row);
  }

  @override
  Future<ChatEvent> updateEvent(String eventId, ChatEventDraft draft) async {
    final row = await _client.rpc<dynamic>(
      'update_chat_event',
      params: {'target_event_id': eventId, ..._fields(draft)},
    );
    return _event(row);
  }

  @override
  Future<ChatEvent> cancelEvent(String eventId) async {
    final row = await _client.rpc<dynamic>(
      'cancel_chat_event',
      params: {'target_event_id': eventId},
    );
    return _event(row);
  }

  @override
  Future<ChatEvent> rsvp(String eventId, ChatEventRsvp? status) async {
    final row = await _client.rpc<dynamic>(
      'rsvp_chat_event',
      params: {'target_event_id': eventId, 'rsvp_status': status?.value},
    );
    return _event(row);
  }

  @override
  Future<ChatEvent> setPinned(String eventId, {required bool pinned}) async {
    final row = await _client.rpc<dynamic>(
      'pin_chat_event',
      params: {'target_event_id': eventId, 'pinned': pinned},
    );
    return _event(row);
  }

  @override
  Stream<void> changes(String conversationId) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    PostgresChangeFilter filter() => PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'conversation_id',
      value: conversationId,
    );
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('chat-events-$conversationId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'chat_events',
              filter: filter(),
              callback: (_) => controller.add(null),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'chat_event_rsvps',
              filter: filter(),
              callback: (_) => controller.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  Future<List<ChatEventReminder>> listReminders({int limit = 20}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_chat_event_reminders',
      params: {'max_reminders': limit},
    );
    return [
      for (final row in rows)
        ChatEventReminder.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  @override
  Future<void> markRemindersRead([List<String>? ids]) async {
    await _client.rpc<dynamic>(
      'mark_chat_event_reminders_read',
      params: {'reminder_ids': ids},
    );
  }
}

class UninitializedChatEventsRepository implements ChatEventsRepository {
  const UninitializedChatEventsRepository();

  @override
  Future<List<ChatEvent>> listEvents(
    String conversationId, {
    bool includePast = false,
  }) async => const [];

  @override
  Future<ChatEvent?> getEvent(String eventId) async => null;

  @override
  Future<ChatEvent> createEvent(String conversationId, ChatEventDraft draft) =>
      Future.error(StateError('Events need a signed-in session.'));

  @override
  Future<ChatEvent> updateEvent(String eventId, ChatEventDraft draft) =>
      Future.error(StateError('Events need a signed-in session.'));

  @override
  Future<ChatEvent> cancelEvent(String eventId) =>
      Future.error(StateError('Events need a signed-in session.'));

  @override
  Future<ChatEvent> rsvp(String eventId, ChatEventRsvp? status) =>
      Future.error(StateError('Events need a signed-in session.'));

  @override
  Future<ChatEvent> setPinned(String eventId, {required bool pinned}) =>
      Future.error(StateError('Events need a signed-in session.'));

  @override
  Stream<void> changes(String conversationId) => const Stream<void>.empty();

  @override
  Future<List<ChatEventReminder>> listReminders({int limit = 20}) async =>
      const [];

  @override
  Future<void> markRemindersRead([List<String>? ids]) async {}
}
