import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_models.dart';
import 'package:wecord/features/push/push_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Why the server refused to merge and forward the messages.
enum MergedForwardRefusal {
  /// A message cannot be forwarded: view-once media, a deleted, expired or
  /// waiting-for-review message, a poll, sticker or system line.
  someMessages,

  /// The chat it goes to takes no chat history (a circle channel).
  target,

  /// Anything else.
  other,
}

class MergedForwardException implements Exception {
  const MergedForwardException(this.refusal);

  final MergedForwardRefusal refusal;

  @override
  String toString() => switch (refusal) {
    MergedForwardRefusal.someMessages => tr(
      'Some of these messages cannot be forwarded. View-once, deleted and expired messages are left out.',
    ),
    MergedForwardRefusal.target => tr(
      'Chat history can be sent to direct chats and groups.',
    ),
    MergedForwardRefusal.other => tr('Could not forward messages. Try again.'),
  };
}

/// Sends selected messages as one chat history and reads one back
/// (`202610180070_merged_forward.sql`).
abstract interface class MergedForwardRepository {
  /// Forwards [sourceMessageIds] (up to [maxMergedForwardMessages], all from
  /// one chat) to [targetConversationId] as a single chat-history message
  /// titled with [title]. Returns the new message's id. Throws
  /// [MergedForwardException], or a [SendRefusedException] for AutoMod and
  /// circle-rules refusals.
  Future<String> forwardMerged({
    required List<String> sourceMessageIds,
    required String targetConversationId,
    required String title,
  });

  /// The messages of the chat-history message [messageId].
  Future<ChatHistoryBundle> loadBundle(String messageId);
}

final mergedForwardRepositoryProvider = Provider<MergedForwardRepository>((
  ref,
) {
  try {
    return SupabaseMergedForwardRepository(
      ref.watch(supabaseClientProvider),
      onSent: ref.watch(pushRepositoryProvider).notifySent,
    );
  } on ProviderException {
    return const UninitializedMergedForwardRepository();
  }
});

/// The messages of a chat-history message, read once per card.
final chatHistoryBundleProvider = FutureProvider.autoDispose
    .family<ChatHistoryBundle, String>((ref, messageId) {
      return ref.watch(mergedForwardRepositoryProvider).loadBundle(messageId);
    });

class SupabaseMergedForwardRepository implements MergedForwardRepository {
  const SupabaseMergedForwardRepository(this._client, {this.onSent});

  final SupabaseClient _client;
  final Future<void> Function(String messageId)? onSent;

  @override
  Future<String> forwardMerged({
    required List<String> sourceMessageIds,
    required String targetConversationId,
    required String title,
  }) async {
    final Object? created;
    try {
      created = await _client.rpc<Object?>(
        'forward_messages_merged',
        params: {
          'source_message_ids': sourceMessageIds,
          'target_conversation_id': targetConversationId,
          'conversation_title': title,
        },
      );
    } on PostgrestException catch (error) {
      throw SendRefusedException.fromPostgrest(error) ??
          _refusalFrom(error) ??
          error;
    }
    if (created is! String) {
      // AutoMod dropped it quietly.
      throw const AutoModBlockedException();
    }
    await onSent?.call(created);
    return created;
  }

  static MergedForwardException? _refusalFrom(PostgrestException error) {
    if (error.code != '42501') {
      return null;
    }
    final message = error.message;
    if (message.contains('direct chats and groups')) {
      return const MergedForwardException(MergedForwardRefusal.target);
    }
    if (message.contains('cannot be forwarded')) {
      return const MergedForwardException(MergedForwardRefusal.someMessages);
    }
    return const MergedForwardException(MergedForwardRefusal.other);
  }

  @override
  Future<ChatHistoryBundle> loadBundle(String messageId) async {
    final row = await _client
        .from('message_bundles')
        .select('title,items')
        .eq('message_id', messageId)
        .maybeSingle();
    if (row == null) {
      throw const MergedForwardException(MergedForwardRefusal.other);
    }
    return ChatHistoryBundle.fromJson(row);
  }
}

class UninitializedMergedForwardRepository implements MergedForwardRepository {
  const UninitializedMergedForwardRepository();

  @override
  Future<String> forwardMerged({
    required List<String> sourceMessageIds,
    required String targetConversationId,
    required String title,
  }) => throw StateError('Supabase is not initialized');

  @override
  Future<ChatHistoryBundle> loadBundle(String messageId) =>
      throw StateError('Supabase is not initialized');
}
