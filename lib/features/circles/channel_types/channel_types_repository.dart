import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/circles/channel_types/qa_models.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/forum.dart';

/// The calls of Q&A channels (migration 202610270310): the state of a
/// question, marking it solved or open again, and the list with a solved
/// filter. Media channels use the forum's calls unchanged.
class ChannelTypesRepository {
  const ChannelTypesRepository(this._rpc, {this.postChangesStream});

  final CircleRpc _rpc;

  /// Emits when a post's row changes (it was solved or reopened by someone
  /// else); null where there is no realtime connection.
  final Stream<void> Function(String conversationId)? postChangesStream;

  /// Null when [conversationId] is not a Q&A post the person belongs to.
  Future<QaPostState?> postState(String conversationId) async {
    final result = await _rpc('get_qa_post_state', {
      'target_conversation_id': conversationId,
    });
    if (result is! Map) {
      return null;
    }
    return QaPostState.fromJson(Map<String, dynamic>.from(result));
  }

  /// Marks the question solved, with [answerMessageId] as the accepted answer
  /// when given. Returns the new state.
  Future<QaPostState?> markSolved(
    String threadId, {
    String? answerMessageId,
  }) async {
    final result = await _rpc('mark_post_solved', {
      'target_thread_id': threadId,
      'answer_message_id': answerMessageId,
    });
    return result is Map
        ? QaPostState.fromJson(Map<String, dynamic>.from(result))
        : null;
  }

  Future<QaPostState?> reopen(String threadId) async {
    final result = await _rpc('reopen_qa_post', {'target_thread_id': threadId});
    return result is Map
        ? QaPostState.fromJson(Map<String, dynamic>.from(result))
        : null;
  }

  /// A page of a Q&A channel's questions; [status] narrows it to the solved
  /// or the open ones.
  Future<List<ForumPost>> listPosts({
    required String channelId,
    ForumPostSort sort = ForumPostSort.activity,
    String? tagId,
    QaStatusFilter status = QaStatusFilter.all,
    ForumPostCursor? before,
    int limit = 25,
  }) async {
    final rows = await _rpc('list_qa_posts', {
      'target_channel_id': channelId,
      'sort_order': sort.value,
      'filter_tag_id': tagId,
      'filter_status': status.value,
      'before_at': before?.at.toUtc().toIso8601String(),
      'before_id': before?.id,
      'limit_count': limit,
    });
    return [for (final row in rpcRows(rows)) ForumPost.fromJson(row)];
  }

  Stream<void> postChanges(String conversationId) {
    return postChangesStream?.call(conversationId) ??
        const Stream<void>.empty();
  }
}

final channelTypesRepositoryProvider = Provider<ChannelTypesRepository>((ref) {
  return ChannelTypesRepository(
    ref.watch(circleRpcProvider),
    postChangesStream: (conversationId) {
      late RealtimeChannel channel;
      late StreamController<void> controller;
      SupabaseClient client;
      try {
        client = ref.read(supabaseClientProvider);
      } on ProviderException {
        return const Stream<void>.empty();
      }
      controller = StreamController<void>(
        onListen: () {
          channel = client
              .channel('qa-post-$conversationId')
              .onPostgresChanges(
                event: PostgresChangeEvent.update,
                schema: 'public',
                table: 'conversation_threads',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'conversation_id',
                  value: conversationId,
                ),
                callback: (_) => controller.add(null),
              )
              .subscribe();
        },
        onCancel: () async {
          await client.removeChannel(channel);
        },
      );
      return controller.stream;
    },
  );
});

/// A Q&A post's mark; null for anything that is not one (or when it cannot be
/// read: the server still enforces every rule). Refreshes when someone else
/// solves or reopens the post.
final qaPostStateProvider = FutureProvider.autoDispose
    .family<QaPostState?, String>((ref, conversationId) async {
      final repository = ref.watch(channelTypesRepositoryProvider);
      try {
        final sub = repository
            .postChanges(conversationId)
            .listen((_) => ref.invalidateSelf());
        ref.onDispose(sub.cancel);
      } on Object {
        // No live updates; the state is read again when the page opens.
      }
      try {
        return await repository.postState(conversationId);
      } on Object {
        return null;
      }
    });
