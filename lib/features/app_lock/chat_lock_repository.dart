import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Which chats the person locked, on the server.
///
/// The lock itself is on the device: the server never sees a PIN, a secret
/// code or whether a chat is hidden from the list. It keeps only the list of
/// locked chats (in the person's notification settings,
/// `user_notification_settings.locked_conversation_ids`), so that
///
///  * a push about a locked chat shows no sender and no text, on every
///    device of the person,
///  * the daily digest and AI questions leave locked chats out, and
///  * every device agrees on which chats are locked.
abstract interface class ChatLockRepository {
  /// The ids of the locked chats; empty while the person has none.
  Future<Set<String>> load();

  /// Locks or unlocks one chat.
  Future<void> setLocked(String conversationId, {required bool locked});
}

class SupabaseChatLockRepository implements ChatLockRepository {
  const SupabaseChatLockRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Set<String>> load() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const {};
    }
    final row = await _client
        .from('user_notification_settings')
        .select('locked_conversation_ids')
        .eq('user_id', userId)
        .maybeSingle();
    final ids = row?['locked_conversation_ids'];
    return ids is List ? {...ids.whereType<String>()} : const {};
  }

  @override
  Future<void> setLocked(String conversationId, {required bool locked}) async {
    await _client.rpc(
      'set_conversation_locked',
      params: {'target_conversation_id': conversationId, 'locked': locked},
    );
  }
}

/// Keeps the list in memory: stands in before Supabase is set up (tests) and
/// for tests that need a server to look at.
class InMemoryChatLockRepository implements ChatLockRepository {
  InMemoryChatLockRepository([Set<String> locked = const {}])
    : locked = {...locked};

  /// What the "server" holds.
  final Set<String> locked;

  /// Makes every call fail, to test the errors.
  Object? failWith;

  var calls = 0;

  void _check() {
    final failure = failWith;
    if (failure != null) {
      throw failure;
    }
  }

  @override
  Future<Set<String>> load() async {
    _check();
    return {...locked};
  }

  @override
  Future<void> setLocked(String conversationId, {required bool locked}) async {
    _check();
    calls++;
    locked
        ? this.locked.add(conversationId)
        : this.locked.remove(conversationId);
  }
}

final chatLockRepositoryProvider = Provider<ChatLockRepository>((ref) {
  try {
    return SupabaseChatLockRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return InMemoryChatLockRepository();
  }
});
