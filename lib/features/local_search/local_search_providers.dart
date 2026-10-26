import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/app_lock/chat_lock_controller.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/local_search/indexed_chat_cache.dart';
import 'package:wecord/features/local_search/local_message_search.dart';

/// Conversations the offline search must never return when it looks in more
/// than one place, besides the chats the person locked (G2, which it always
/// leaves out, as the server's search does).
///
/// Empty for now. The advanced chat privacy setting (G6, "restrict sharing":
/// no forwarding, saving, export or AI reading) is the one that will fill
/// this in: override this provider with the ids of the conversations that
/// have it on. The index itself needs no change, because the setting is read
/// when a search runs, not when a message is indexed.
final localSearchBlockedConversationIdsProvider = Provider<Set<String>>(
  (ref) => const <String>{},
);

/// The search over this device's cache, or null when the cache is not one
/// that keeps an index (tests, a platform without storage, or a key that
/// could not be had).
final localMessageSearchProvider = Provider<LocalMessageSearch?>((ref) {
  final cache = ref.watch(chatCacheProvider);
  if (cache is! IndexedChatCache) {
    return null;
  }
  return LocalMessageSearch(
    cache: cache,
    index: cache.index,
    userId: () {
      try {
        return ref.read(authRepositoryProvider).currentUser?.id;
      } on Object {
        return null;
      }
    },
    excludedConversations: () => {
      ...ref.read(lockedConversationIdsProvider),
      ...ref.read(localSearchBlockedConversationIdsProvider),
    },
  );
});

/// Builds the offline search index for the chats that were cached before the
/// search existed, a conversation at a time and only once the app has been up
/// for a while, so starting and scrolling are not slowed. Watched by the app
/// for as long as it runs.
final localSearchBackfillProvider = Provider<void>((ref) {
  var disposed = false;
  ref.onDispose(() => disposed = true);

  Future<void> run() async {
    final cache = ref.read(chatCacheProvider);
    final user = ref.read(authRepositoryProvider).currentUser?.id;
    if (disposed || cache is! IndexedChatCache || user == null) {
      return;
    }
    try {
      await cache.backfill(
        user,
        // A short breath between conversations.
        pause: () => Future<void>.delayed(const Duration(milliseconds: 40)),
        shouldStop: () =>
            disposed ||
            ref.read(authRepositoryProvider).currentUser?.id != user,
      );
    } on Object {
      // Tried again at the next start; searching works on what is indexed.
    }
  }

  // Well after the first frame, and again when someone signs in.
  Timer? timer;
  void later() {
    timer?.cancel();
    timer = Timer(const Duration(seconds: 6), () => unawaited(run()));
  }

  ref.onDispose(() => timer?.cancel());
  WidgetsBinding.instance.addPostFrameCallback((_) => later());
  ref.listen(authStateProvider, (previous, next) {
    if (next.value?.id != previous?.value?.id && next.value != null) {
      later();
    }
  });
});
