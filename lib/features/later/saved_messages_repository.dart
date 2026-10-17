import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/message.dart';

/// A message the user saved for later. [available] is false when the
/// message was deleted or the user can no longer read its conversation: the
/// entry then reads "Message unavailable" and can only be removed.
class SavedMessage {
  const SavedMessage({
    required this.id,
    required this.conversationId,
    required this.savedAt,
    this.messageId,
    this.doneAt,
    this.senderId,
    this.senderName = '',
    this.senderAvatarUrl,
    this.body = '',
    this.type = MessageType.text,
    this.messageCreatedAt,
    this.available = true,
  });

  factory SavedMessage.fromJson(Map<String, dynamic> json) {
    final available = json['available'] as bool? ?? false;
    final webhookName = json['webhook_name'] as String?;
    return SavedMessage(
      id: json['saved_id'] as String,
      messageId: json['message_id'] as String?,
      conversationId: json['conversation_id'] as String,
      savedAt: DateTime.parse(json['saved_at'] as String),
      doneAt: json['done_at'] == null
          ? null
          : DateTime.parse(json['done_at'] as String),
      senderId: json['sender_id'] as String?,
      senderName: webhookName ?? json['sender_display_name'] as String? ?? '',
      senderAvatarUrl: webhookName == null
          ? json['sender_avatar_url'] as String?
          : null,
      body: available ? json['body'] as String? ?? '' : '',
      type: available && json['type'] is String
          ? MessageType.fromJson(json['type'] as String)
          : MessageType.text,
      messageCreatedAt: json['message_created_at'] == null
          ? null
          : DateTime.parse(json['message_created_at'] as String),
      available: available,
    );
  }

  final String id;
  final String? messageId;
  final String conversationId;
  final DateTime savedAt;
  final DateTime? doneAt;
  final String? senderId;
  final String senderName;
  final String? senderAvatarUrl;
  final String body;
  final MessageType type;
  final DateTime? messageCreatedAt;
  final bool available;

  bool get isDone => doneAt != null;
}

abstract interface class SavedMessagesRepository {
  /// Everything the user saved, newest first (active and done).
  Future<List<SavedMessage>> list();

  Future<void> save(String messageId);

  /// Takes a saved message out of the list.
  Future<void> remove(String id);

  /// Marks it done, or active again.
  Future<void> setDone(String id, {required bool done});
}

final savedMessagesRepositoryProvider = Provider<SavedMessagesRepository>((
  ref,
) {
  try {
    return SupabaseSavedMessagesRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedSavedMessagesRepository();
  }
});

/// The user's saved messages.
final savedMessagesProvider = FutureProvider.autoDispose<List<SavedMessage>>((
  ref,
) {
  return ref.watch(savedMessagesRepositoryProvider).list();
});

/// The ids of the messages the user saved (done or not), for the message
/// menu's "Saved" state. Empty until loaded.
final savedMessageIdsProvider = Provider.autoDispose<Set<String>>((ref) {
  return {
    for (final saved
        in ref.watch(savedMessagesProvider).value ?? const <SavedMessage>[])
      ?saved.messageId,
  };
});

/// Saved messages still to do.
final activeSavedCountProvider = Provider.autoDispose<int>((ref) {
  return (ref.watch(savedMessagesProvider).value ?? const <SavedMessage>[])
      .where((saved) => !saved.isDone)
      .length;
});

class SupabaseSavedMessagesRepository implements SavedMessagesRepository {
  const SupabaseSavedMessagesRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<SavedMessage>> list() async {
    final rows = await _client.rpc<List<dynamic>>('list_saved_messages');
    return [
      for (final row in rows)
        SavedMessage.fromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> save(String messageId) async {
    await _client.rpc<dynamic>(
      'save_message',
      params: {'p_message_id': messageId},
    );
  }

  @override
  Future<void> remove(String id) async {
    await _client.from('saved_messages').delete().eq('id', id);
  }

  @override
  Future<void> setDone(String id, {required bool done}) async {
    await _client.rpc<dynamic>(
      'set_saved_message_done',
      params: {'p_id': id, 'p_done': done},
    );
  }
}

class UninitializedSavedMessagesRepository implements SavedMessagesRepository {
  const UninitializedSavedMessagesRepository();

  @override
  Future<List<SavedMessage>> list() async => const [];

  @override
  Future<void> save(String messageId) =>
      throw StateError('Supabase must be initialized to save messages.');

  @override
  Future<void> remove(String id) async {}

  @override
  Future<void> setDone(String id, {required bool done}) async {}
}
