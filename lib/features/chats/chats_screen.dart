import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

class ChatThreadRouteExtra {
  const ChatThreadRouteExtra({
    required this.title,
    required this.type,
    this.avatarUrl,
  });

  final String title;
  final ConversationType type;
  final String? avatarUrl;
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

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  static const path = '/chats';

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            tooltip: 'Search all messages',
            icon: const Icon(Icons.search),
            onPressed: () {
              context.go(GlobalMessageSearchScreen.path);
            },
          ),
        ],
      ),
      body: conversations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(
            error.toString(),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        data: (conversations) {
          final visibleConversations = ref
              .read(chatsRepositoryProvider)
              .searchConversations(conversations, _query);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Search chats',
                  ),
                  onChanged: (value) {
                    setState(() {
                      _query = value;
                    });
                  },
                ),
              ),
              Expanded(
                child: conversations.isEmpty
                    ? const Center(child: Text('No conversations yet'))
                    : visibleConversations.isEmpty
                    ? const Center(child: Text('No matching conversations'))
                    : ListView.separated(
                        itemCount: visibleConversations.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          return _ConversationTile(
                            conversation: visibleConversations[index],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _ConversationAction { pin, mute, markReadState, hide }

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = conversation.title?.trim().isNotEmpty == true
        ? conversation.title!
        : 'Conversation';
    final lastMessage = conversation.lastMessageType == MessageType.voice
        ? '[Voice]'
        : conversation.lastMessageBody?.trim().isNotEmpty == true
        ? conversation.lastMessageBody!
        : 'No messages yet';

    final hasUnread = conversation.unreadCount > 0;
    final appearsUnread = hasUnread || conversation.isMarkedUnread;
    final groupMeta =
        conversation.type == ConversationType.group &&
            conversation.memberCount > 0
        ? '${conversation.memberCount} members'
        : null;

    return ListTile(
      leading: _ConversationAvatar(
        title: title,
        avatarUrl: conversation.avatarUrl,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (conversation.pinnedAt != null) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.push_pin,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
          if (conversation.isMuted) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.notifications_off_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
      subtitle: groupMeta == null
          ? Text(lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis)
          : Row(
              children: [
                Expanded(
                  child: Text(
                    lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(groupMeta),
              ],
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (conversation.lastMessageAt case final lastMessageAt?) ...[
            Text(_formatTime(lastMessageAt)),
            const SizedBox(width: 12),
          ],
          if (appearsUnread)
            hasUnread
                ? Badge(label: Text(conversation.unreadCount.toString()))
                : const Badge(),
          PopupMenuButton<_ConversationAction>(
            tooltip: 'Conversation actions',
            icon: const Icon(Icons.more_horiz),
            onSelected: (action) {
              _handleAction(context, ref, action);
            },
            itemBuilder: (context) {
              return [
                PopupMenuItem(
                  value: _ConversationAction.pin,
                  child: Text(
                    conversation.pinnedAt == null ? 'Pin chat' : 'Unpin chat',
                  ),
                ),
                PopupMenuItem(
                  value: _ConversationAction.mute,
                  child: Text(conversation.isMuted ? 'Unmute' : 'Mute'),
                ),
                PopupMenuItem(
                  value: _ConversationAction.markReadState,
                  child: Text(appearsUnread ? 'Mark read' : 'Mark unread'),
                ),
                const PopupMenuItem(
                  value: _ConversationAction.hide,
                  child: Text('Delete conversation'),
                ),
              ];
            },
          ),
        ],
      ),
      onTap: () {
        context.go(
          '${ChatsScreen.path}/${conversation.id}',
          extra: ChatThreadRouteExtra(
            title: title,
            type: conversation.type,
            avatarUrl: conversation.avatarUrl,
          ),
        );
      },
    );
  }

  void _handleAction(
    BuildContext context,
    WidgetRef ref,
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
              const SnackBar(content: Text('Could not update conversation.')),
            );
          }),
    );
  }
}

class _ConversationAvatar extends ConsumerWidget {
  const _ConversationAvatar({required this.title, required this.avatarUrl});

  final String title;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayUrl = ref.watch(avatarDisplayUrlProvider(avatarUrl));
    final image = displayUrl.valueOrNull == null
        ? null
        : NetworkImage(displayUrl.valueOrNull!);
    return CircleAvatar(
      backgroundImage: image,
      onBackgroundImageError: image == null ? null : (_, _) {},
      child: image == null ? Text(_initials(title)) : null,
    );
  }
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return '?';
  }
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts.last.characters.first : '';
  return '$first$second'.toUpperCase();
}

String _formatTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
