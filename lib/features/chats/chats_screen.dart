import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/conversation.dart';

class ChatThreadRouteExtra {
  const ChatThreadRouteExtra({required this.title, required this.type});

  final String title;
  final ConversationType type;
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

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  static const path = '/chats';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: conversations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(
            error.toString(),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        data: (conversations) {
          if (conversations.isEmpty) {
            return const Center(child: Text('No conversations yet'));
          }

          return ListView.separated(
            itemCount: conversations.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              return _ConversationTile(conversation: conversations[index]);
            },
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    final title = conversation.title?.trim().isNotEmpty == true
        ? conversation.title!
        : 'Conversation';
    final lastMessage = conversation.lastMessageBody?.trim().isNotEmpty == true
        ? conversation.lastMessageBody!
        : 'No messages yet';

    return ListTile(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (conversation.lastMessageAt case final lastMessageAt?) ...[
            Text(_formatTime(lastMessageAt)),
            const SizedBox(width: 12),
          ],
          if (conversation.unreadCount > 0)
            Badge(label: Text(conversation.unreadCount.toString())),
        ],
      ),
      onTap: () {
        context.go(
          '${ChatsScreen.path}/${conversation.id}',
          extra: ChatThreadRouteExtra(title: title, type: conversation.type),
        );
      },
    );
  }
}

String _formatTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
