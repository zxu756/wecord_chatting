import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chat_folders/chat_folder.dart';
import 'package:wecord/features/chat_folders/chat_folder_rules.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/conversation.dart';

/// Why a folder could not be saved.
enum ChatFolderProblem {
  /// The person already has [maxChatFolders].
  limit,

  /// Another folder is already folded (only one can be).
  alreadyFolded,

  /// The name is empty or too long.
  name,
}

class ChatFolderException implements Exception {
  const ChatFolderException(this.problem);

  final ChatFolderProblem problem;

  @override
  String toString() => 'ChatFolderException($problem)';
}

/// The first thing wrong with [name], or null.
ChatFolderProblem? checkChatFolderName(String name) {
  final length = name.trim().runes.length;
  return length == 0 || length > maxChatFolderNameLength
      ? ChatFolderProblem.name
      : null;
}

/// Reads and writes the person's chat folders (table `chat_folders`, owner
/// only by row level security). Every call is the signed-in person's own.
abstract interface class ChatFoldersRepository {
  /// The folders in the person's order.
  Future<List<ChatFolder>> load();

  /// Makes [draft] the last folder; throws [ChatFolderException].
  Future<ChatFolder> create(ChatFolder draft);

  /// Saves the rules of [folder]; throws [ChatFolderException].
  Future<void> update(ChatFolder folder);

  Future<void> delete(String folderId);

  /// Puts the folders in the order of [folderIds].
  Future<void> reorder(List<String> folderIds);

  /// Pings when the person's folders changed (here or on another device).
  Stream<void> changes();
}

class SupabaseChatFoldersRepository implements ChatFoldersRepository {
  const SupabaseChatFoldersRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Sign in to use chat folders.');
    }
    return id;
  }

  @override
  Future<List<ChatFolder>> load() async {
    final rows = await _client
        .from('chat_folders')
        .select()
        .order('sort_key')
        .order('created_at');
    return [
      for (final row in rows)
        ChatFolder.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<ChatFolder> create(ChatFolder draft) async {
    final problem = checkChatFolderName(draft.name);
    if (problem != null) {
      throw ChatFolderException(problem);
    }
    try {
      final row = await _client
          .from('chat_folders')
          .insert({
            ...draft.toRules(),
            'user_id': _userId,
            'sort_key': draft.sortKey,
          })
          .select()
          .single();
      return ChatFolder.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (error) {
      throw _problemOf(error) ?? error;
    }
  }

  @override
  Future<void> update(ChatFolder folder) async {
    final problem = checkChatFolderName(folder.name);
    if (problem != null) {
      throw ChatFolderException(problem);
    }
    try {
      await _client
          .from('chat_folders')
          .update(folder.toRules())
          .eq('id', folder.id);
    } on PostgrestException catch (error) {
      throw _problemOf(error) ?? error;
    }
  }

  @override
  Future<void> delete(String folderId) async {
    await _client.from('chat_folders').delete().eq('id', folderId);
  }

  @override
  Future<void> reorder(List<String> folderIds) async {
    await _client.rpc<void>(
      'reorder_chat_folders',
      params: {'folder_ids': folderIds},
    );
  }

  ChatFolderException? _problemOf(PostgrestException error) {
    if (error.code == '23505') {
      return const ChatFolderException(ChatFolderProblem.alreadyFolded);
    }
    if (error.code == '23514') {
      return ChatFolderException(
        error.message.contains('at most')
            ? ChatFolderProblem.limit
            : ChatFolderProblem.name,
      );
    }
    return null;
  }

  @override
  Stream<void> changes() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Stream<void>.empty();
    }
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('chat-folders-$userId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'chat_folders',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId,
              ),
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
}

/// Stands in before Supabase is set up (tests): no folders, nothing stored.
class UninitializedChatFoldersRepository implements ChatFoldersRepository {
  const UninitializedChatFoldersRepository();

  @override
  Future<List<ChatFolder>> load() async => const [];

  @override
  Future<ChatFolder> create(ChatFolder draft) {
    throw StateError('Supabase must be initialized to make chat folders.');
  }

  @override
  Future<void> update(ChatFolder folder) {
    throw StateError('Supabase must be initialized to change chat folders.');
  }

  @override
  Future<void> delete(String folderId) {
    throw StateError('Supabase must be initialized to change chat folders.');
  }

  @override
  Future<void> reorder(List<String> folderIds) {
    throw StateError('Supabase must be initialized to change chat folders.');
  }

  @override
  Stream<void> changes() => const Stream<void>.empty();
}

final chatFoldersRepositoryProvider = Provider<ChatFoldersRepository>((ref) {
  try {
    return SupabaseChatFoldersRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedChatFoldersRepository();
  }
});

/// The person's folders: fetched on entry, then refreshed whenever one of
/// their own rows changes (on this device or another).
final chatFoldersProvider = FutureProvider.autoDispose<List<ChatFolder>>((ref) {
  final repository = ref.watch(chatFoldersRepositoryProvider);
  final subscription = repository.changes().listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(subscription.cancel);
  return repository.load();
});

/// Which entry of the folder strip is selected: null for All,
/// [unreadFilterId], or a folder's id. Kept for this session only.
class ChatFolderSelection extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final chatFolderSelectionProvider =
    NotifierProvider<ChatFolderSelection, String?>(ChatFolderSelection.new);

/// The selection, or null (All) if its folder is gone.
final effectiveChatFolderSelectionProvider = Provider.autoDispose<String?>((
  ref,
) {
  final selected = ref.watch(chatFolderSelectionProvider);
  if (selected == null || selected == unreadFilterId) {
    return selected;
  }
  final folders = ref.watch(chatFoldersProvider).value;
  // While the folders load, keep what was chosen.
  if (folders == null || folders.any((folder) => folder.id == selected)) {
    return selected;
  }
  return null;
});

/// The chats a folder strip filters: direct and group chats, the note to
/// self first, as the list shows them.
final chatFolderChatsProvider = Provider.autoDispose<List<ConversationSummary>>(
  (ref) {
    final all = ref.watch(conversationsProvider).value ?? const [];
    return [
      for (final chat in all)
        if (chat.isDirectMessage) chat,
    ];
  },
);
