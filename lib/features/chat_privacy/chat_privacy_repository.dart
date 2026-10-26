import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// A chat's advanced chat privacy (roadmap G6): whether it is restricted, and
/// who asked. A restricted chat cannot be forwarded, saved, copied out or read
/// by AI; the database enforces it, the app hides what it would refuse.
class ChatPrivacy {
  const ChatPrivacy({required this.restricted, this.requestedBy = const {}});

  /// Not restricted; what a chat is until the server says otherwise.
  static const open = ChatPrivacy(restricted: false);

  final bool restricted;

  /// The people who asked (both people of a direct chat can; a group keeps
  /// the admin who last turned it on).
  final Set<String> requestedBy;

  /// Whether [userId] asked for it themselves.
  bool requestedByUser(String? userId) =>
      userId != null && requestedBy.contains(userId);

  /// A direct chat the other person asked to restrict: turning off your own
  /// request does not open it.
  bool onlyOthersAsked(String? userId) =>
      restricted && !requestedByUser(userId);

  @override
  bool operator ==(Object other) =>
      other is ChatPrivacy &&
      other.restricted == restricted &&
      other.requestedBy.length == requestedBy.length &&
      other.requestedBy.containsAll(requestedBy);

  @override
  int get hashCode => Object.hash(restricted, requestedBy.length);
}

/// Reads and changes a chat's advanced chat privacy.
abstract interface class ChatPrivacyRepository {
  Future<ChatPrivacy> read(String conversationId);

  /// Turns the caller's switch on or off (in a group: the group's, for an
  /// owner or admin). Returns whether the chat is restricted afterwards.
  Future<bool> set(String conversationId, bool enabled);
}

class SupabaseChatPrivacyRepository implements ChatPrivacyRepository {
  const SupabaseChatPrivacyRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ChatPrivacy> read(String conversationId) async {
    final row = await _client
        .from('conversations')
        .select('restrict_sharing, restrict_sharing_by')
        .eq('id', conversationId)
        .maybeSingle();
    if (row == null) {
      return ChatPrivacy.open;
    }
    final by = row['restrict_sharing_by'];
    return ChatPrivacy(
      restricted: row['restrict_sharing'] == true,
      requestedBy: {
        if (by is List)
          for (final id in by)
            if (id is String) id,
      },
    );
  }

  @override
  Future<bool> set(String conversationId, bool enabled) async {
    final result = await _client.rpc<Object?>(
      'set_chat_restrict_sharing',
      params: {'target_conversation_id': conversationId, 'enabled': enabled},
    );
    return result == true;
  }
}

class _UninitializedChatPrivacyRepository implements ChatPrivacyRepository {
  const _UninitializedChatPrivacyRepository();

  @override
  Future<ChatPrivacy> read(String conversationId) async => ChatPrivacy.open;

  @override
  Future<bool> set(String conversationId, bool enabled) {
    throw StateError('Supabase must be initialized before changing privacy.');
  }
}

final chatPrivacyRepositoryProvider = Provider<ChatPrivacyRepository>((ref) {
  try {
    return SupabaseChatPrivacyRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedChatPrivacyRepository();
  }
});

/// A chat's advanced chat privacy. A server without the feature, or one that
/// cannot be reached, reads as open. The chat page refreshes it when a notice
/// about the setting arrives (see ChatPrivacyBanner).
final chatPrivacyProvider = FutureProvider.autoDispose
    .family<ChatPrivacy, String>((ref, conversationId) async {
      try {
        return await ref
            .watch(chatPrivacyRepositoryProvider)
            .read(conversationId);
      } on Object {
        return ChatPrivacy.open;
      }
    });

/// Whether the chat is restricted, false until the server has said so.
final restrictSharingProvider = Provider.autoDispose.family<bool, String>(
  (ref, conversationId) =>
      ref.watch(chatPrivacyProvider(conversationId)).value?.restricted ?? false,
);
