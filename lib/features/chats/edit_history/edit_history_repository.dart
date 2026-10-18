import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/edit_history/edit_version.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Reads the earlier versions of an edited message.
abstract interface class EditHistoryRepository {
  /// The versions that came before the message's current text, newest first.
  /// Empty when there are none, or when the viewer cannot see the message.
  Future<List<MessageEditVersion>> versions(String messageId);
}

class SupabaseEditHistoryRepository implements EditHistoryRepository {
  const SupabaseEditHistoryRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<MessageEditVersion>> versions(String messageId) async {
    final rows = await _client
        .from('message_edits')
        .select('version, body, mentions, edited_at')
        .eq('message_id', messageId)
        .order('version', ascending: false);
    return [
      for (final row in rows)
        MessageEditVersion.fromJson(Map<String, dynamic>.from(row)),
    ];
  }
}

class _UninitializedEditHistoryRepository implements EditHistoryRepository {
  const _UninitializedEditHistoryRepository();

  @override
  Future<List<MessageEditVersion>> versions(String messageId) async => const [];
}

final editHistoryRepositoryProvider = Provider<EditHistoryRepository>((ref) {
  try {
    return SupabaseEditHistoryRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedEditHistoryRepository();
  }
});

/// A message's earlier versions, newest first.
final messageEditHistoryProvider = FutureProvider.autoDispose
    .family<List<MessageEditVersion>, String>((ref, messageId) {
      return ref.watch(editHistoryRepositoryProvider).versions(messageId);
    });
