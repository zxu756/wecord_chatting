import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/conversation_navigation.dart'
    show openPage;
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_repository.dart';
import 'package:wecord/features/whiteboard/whiteboard_sync.dart';

/// The boards of a chat: `/chats/<id>/whiteboards`.
String whiteboardListPath(String conversationId) =>
    '/chats/$conversationId/whiteboards';

/// One board: `/chats/<id>/whiteboards/<board id>`.
String whiteboardPath(String conversationId, String boardId) =>
    '/chats/$conversationId/whiteboards/$boardId';

/// Opens the list of boards of [conversationId].
void openWhiteboards(BuildContext context, String conversationId) {
  openPage(context, whiteboardListPath(conversationId));
}

/// Opens one board; [title] is shown while it loads.
void openWhiteboard(
  BuildContext context, {
  required String conversationId,
  required String boardId,
  String? title,
}) {
  openPage(context, whiteboardPath(conversationId, boardId), extra: title);
}

/// Re-runs a provider when [changes] fires, at most every 300 ms.
void _invalidateOnChanges(Ref ref, Stream<void> changes) {
  Timer? pending;
  final subscription = changes.listen((_) {
    pending ??= Timer(const Duration(milliseconds: 300), () {
      pending = null;
      ref.invalidateSelf();
    });
  }, onError: (Object _) {});
  ref.onDispose(() {
    pending?.cancel();
    unawaited(subscription.cancel());
  });
}

/// The boards of a conversation, newest change first.
final whiteboardListProvider = FutureProvider.autoDispose
    .family<List<WhiteboardSummary>, String>((ref, conversationId) {
      final repository = ref.watch(whiteboardRepositoryProvider);
      _invalidateOnChanges(ref, repository.listChanges(conversationId));
      return repository.listBoards(conversationId);
    });

/// Where unsent drawing is kept. Tests swap in memory.
final whiteboardDraftStoreProvider = Provider<WhiteboardDraftStore>(
  (ref) => const SharedPreferencesWhiteboardDraftStore(),
);
