import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
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

final conversationsProvider =
    FutureProvider.autoDispose<List<ConversationSummary>>((ref) {
      final repository = ref.watch(chatsRepositoryProvider);
      final subscription = repository.conversationChanges().listen((_) {
        ref.invalidateSelf();
      });
      ref.onDispose(subscription.cancel);
      return repository.listConversations();
    });

/// The direct messages route. Phones list direct and group chats on Home,
/// wide layouts in the Home sidebar beside the Friends page; conversations
/// open under it (`/chats/<id>`).
abstract final class ChatsScreen {
  static const path = '/chats';
}

enum _ConversationAction { pin, mute, markReadState, hide }

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
