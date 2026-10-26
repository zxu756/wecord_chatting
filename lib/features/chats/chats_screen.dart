import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/app_lock/chat_lock_actions.dart';
import 'package:wecord/features/app_lock/chat_lock_controller.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chat_folders/add_to_folder_sheet.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/connectivity.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';

class ChatThreadRouteExtra {
  const ChatThreadRouteExtra({
    required this.title,
    required this.type,
    this.avatarUrl,
    this.circleId,
  });

  final String title;
  final ConversationType type;
  final String? avatarUrl;

  /// Set for circle channels opened from the circle, which then offer the
  /// circle's member list.
  final String? circleId;
}

/// The current user's conversations. With the offline cache, the last
/// known list shows at once (and while offline) and is replaced when the
/// server answers; reconnecting loads it again.
final conversationsProvider =
    FutureProvider.autoDispose<List<ConversationSummary>>((ref) async {
      final repository = ref.watch(chatsRepositoryProvider);
      // Locked chats are marked so no list shows their latest message (G2).
      final locked = ref.watch(lockedConversationIdsProvider);
      List<ConversationSummary> marked(List<ConversationSummary> list) =>
          locked.isEmpty
          ? list
          : [
              for (final conversation in list)
                locked.contains(conversation.id)
                    ? conversation.copyWith(isLocked: true)
                    : conversation,
            ];
      ref.watch(reconnectCountProvider);
      final subscription = repository.conversationChanges().listen((_) {
        ref.invalidateSelf();
      });
      ref.onDispose(subscription.cancel);
      if (repository is! ConversationRowsSource) {
        return marked(await repository.listConversations());
      }
      final rowsSource = repository as ConversationRowsSource;
      final memo = ref.read(_conversationRowsMemoProvider);
      final cache = ref.watch(chatCacheProvider);
      final userId = ref.watch(authRepositoryProvider).currentUser?.id;

      List<ConversationSummary> parse(List<Map<String, dynamic>> rows) {
        return marked([for (final row in rows) ?_tryConversation(row)]);
      }

      void keep(List<Map<String, dynamic>> rows) {
        if (userId != null) {
          unawaited(
            cache.writeConversations(userId, rows).catchError((Object _) {}),
          );
        }
      }

      // Answered after the cached list was shown (see below).
      if (memo.take(userId) case final fresh?) {
        return parse(fresh);
      }
      final request = rowsSource.listConversationRows();
      List<Map<String, dynamic>>? cached;
      if (userId != null && !memo.shownOnce) {
        try {
          cached = await cache.readConversations(userId);
        } catch (_) {
          cached = null;
        }
      }
      if (cached == null || cached.isEmpty) {
        final rows = await request;
        memo.shownOnce = true;
        keep(rows);
        return parse(rows);
      }
      // Show the cached list now, and the server's when it answers.
      memo.shownOnce = true;
      var disposed = false;
      ref.onDispose(() => disposed = true);
      unawaited(
        request.then(
          (rows) {
            keep(rows);
            memo.put(userId, rows);
            if (!disposed) {
              ref.invalidateSelf();
            }
          },
          onError: (Object _) {
            // Offline: the cached list stays until the connection returns.
          },
        ),
      );
      return parse(cached);
    });

/// [conversationsProvider] without the locked chats the person hid from the
/// lists (G2). Lists and pickers watch this one; a page that looks a chat up
/// by id, and the chat itself, still use the full list.
final listedConversationsProvider =
    Provider.autoDispose<AsyncValue<List<ConversationSummary>>>((ref) {
      final all = ref.watch(conversationsProvider);
      final hidden = ref.watch(hiddenConversationIdsProvider);
      if (hidden.isEmpty) {
        return all;
      }
      return all.whenData(
        (list) => [
          for (final conversation in list)
            if (!hidden.contains(conversation.id)) conversation,
        ],
      );
    });

ConversationSummary? _tryConversation(Map<String, dynamic> row) {
  try {
    return ConversationSummary.fromJson(row);
  } catch (_) {
    return null;
  }
}

/// Hands the server's list to the next build of [conversationsProvider]
/// after the cached one was shown.
class _ConversationRowsMemo {
  String? _userId;
  List<Map<String, dynamic>>? _rows;

  /// The cache is read on the first build only; later builds (realtime
  /// changes) go to the server.
  var shownOnce = false;

  void put(String? userId, List<Map<String, dynamic>> rows) {
    _userId = userId;
    _rows = rows;
  }

  List<Map<String, dynamic>>? take(String? userId) {
    final rows = _userId == userId ? _rows : null;
    _rows = null;
    _userId = null;
    return rows;
  }
}

final _conversationRowsMemoProvider = Provider<_ConversationRowsMemo>((ref) {
  ref.watch(chatsRepositoryProvider);
  return _ConversationRowsMemo();
});

/// The direct messages route. Phones list direct and group chats on Home,
/// wide layouts in the Home sidebar beside the Friends page; conversations
/// open under it (`/chats/<id>`).
abstract final class ChatsScreen {
  static const path = '/chats';
}

enum _ConversationAction { pin, mute, markReadState, folders, lock, hide }

Map<_ConversationAction, String> _conversationActionLabels(
  ConversationSummary conversation,
) {
  return {
    _ConversationAction.pin: conversation.pinnedAt == null
        ? tr('Pin chat')
        : tr('Unpin chat'),
    _ConversationAction.mute: conversation.isMuted ? tr('Unmute') : tr('Mute'),
    _ConversationAction.markReadState:
        conversation.unreadCount > 0 || conversation.isMarkedUnread
        ? tr('Mark read')
        : tr('Mark unread'),
    _ConversationAction.folders: tr('Add to folder…'),
    if (conversation.isDirectMessage)
      _ConversationAction.lock: chatLockLabel(locked: conversation.isLocked),
    _ConversationAction.hide: tr('Delete conversation'),
  };
}

/// Pin, mute, mark read / unread or delete [conversation], picked from a
/// bottom sheet.
Future<void> showConversationActions(
  BuildContext context,
  WidgetRef ref,
  ConversationSummary conversation,
) async {
  // The note to self stays where it is: nothing to pin, mute or delete.
  if (conversation.isNoteToSelf) {
    return;
  }
  final title = conversation.title?.trim().isNotEmpty == true
      ? conversation.title!
      : tr('Conversation');
  final actionLabels = _conversationActionLabels(conversation);
  final action = await showModalBottomSheet<_ConversationAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              for (final MapEntry(key: action, value: label)
                  in actionLabels.entries)
                ListTile(
                  leading: Icon(switch (action) {
                    _ConversationAction.pin => Icons.push_pin_outlined,
                    _ConversationAction.mute =>
                      Icons.notifications_off_outlined,
                    _ConversationAction.markReadState =>
                      Icons.mark_chat_read_outlined,
                    _ConversationAction.folders => Icons.folder_outlined,
                    _ConversationAction.lock =>
                      conversation.isLocked
                          ? Icons.lock_open_rounded
                          : Icons.lock_outline_rounded,
                    _ConversationAction.hide => Icons.delete_outline,
                  }),
                  title: Text(label),
                  onTap: () => Navigator.of(sheetContext).pop(action),
                ),
            ],
          ),
        ),
      );
    },
  );
  if (action == _ConversationAction.folders && context.mounted) {
    await showAddToFolderSheet(context, conversation);
    return;
  }
  if (action == _ConversationAction.lock && context.mounted) {
    await toggleChatLock(context, ref, conversation.id);
    return;
  }
  if (action != null && context.mounted) {
    _handleConversationAction(context, ref, conversation, action);
  }
}

void _handleConversationAction(
  BuildContext context,
  WidgetRef ref,
  ConversationSummary conversation,
  _ConversationAction action,
) {
  final repository = ref.read(chatsRepositoryProvider);
  final Future<void> operation = switch (action) {
    _ConversationAction.pin => repository.setConversationPinned(
      conversationId: conversation.id,
      pinned: conversation.pinnedAt == null,
    ),
    _ConversationAction.mute => repository.setConversationMuted(
      conversationId: conversation.id,
      muted: !conversation.isMuted,
    ),
    _ConversationAction.markReadState =>
      conversation.unreadCount > 0 || conversation.isMarkedUnread
          ? repository.markConversationRead(conversation.id)
          : repository.markConversationUnread(conversation.id),
    // Handled by the caller: it opens a sheet of its own.
    _ConversationAction.folders ||
    _ConversationAction.lock => Future<void>.value(),
    _ConversationAction.hide => repository.hideConversation(conversation.id),
  };

  unawaited(
    operation
        .then((_) {
          ref.invalidate(conversationsProvider);
        })
        .catchError((Object _) {
          if (!context.mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('Could not update conversation.'))),
          );
        }),
  );
}
