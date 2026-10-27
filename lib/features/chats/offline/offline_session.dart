import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/media_cache.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/outbox_provider.dart';
import 'package:wecord/features/local_data/local_data_wipe.dart';
import 'package:wecord/features/lists/task_patch_sync.dart';

/// Keeps the offline copy to the signed-in user: when they sign out (or
/// another account signs in) the cache, the outbox, the cached media
/// links, the texts read from messages and the key that encrypts them are
/// wiped. Watched by the app for as long as it runs.
final offlineSessionGuardProvider = Provider<void>((ref) {
  var userId = ref.read(authRepositoryProvider).currentUser?.id;

  Future<void> wipe() async {
    imageDimensionCache.clear();
    ref.invalidate(chatSignedUrlCacheProvider);
    try {
      await ref.read(chatCacheProvider).clear();
    } catch (_) {
      // Nothing to wipe, or storage is gone.
    }
    try {
      // Task changes that were never sent go with the account.
      await ref.read(taskPatchStoreProvider).clearAll();
    } catch (_) {
      // Nothing kept, or storage is gone.
    }
    // Texts read from pictures, transcripts, drafts, recent searches, and
    // then the key all of it was encrypted with (G8).
    await wipeLocalChatData(ref);
  }

  if (userId == null) {
    // Signed out while the app was closed.
    unawaited(wipe());
  }
  // Riverpod 3 pauses a provider nothing listens to, and with it the
  // outbox's own listener on the connection. Keep it running for as long
  // as the app does, so queued messages go out when the connection
  // returns even with no chat open.
  ref.listen(outboxProvider, (previous, next) {});
  // Likewise for task changes left over from lists that were closed (or an
  // app that was) before they were sent.
  ref.listen(taskPatchSyncProvider, (previous, next) {});
  ref.listen<AsyncValue<AuthUser?>>(authStateProvider, (previous, next) {
    if (!next.hasValue) {
      return;
    }
    final nextUserId = next.value?.id;
    if (nextUserId == userId) {
      return;
    }
    final hadUser = userId != null;
    userId = nextUserId;
    if (hadUser) {
      unawaited(wipe());
    }
    ref.invalidate(outboxProvider);
  });
});
