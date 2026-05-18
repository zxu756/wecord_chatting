import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';

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
      leading: _ConversationAvatar(
        title: title,
        avatarUrl: conversation.avatarUrl,
      ),
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
          extra: ChatThreadRouteExtra(
            title: title,
            type: conversation.type,
            avatarUrl: conversation.avatarUrl,
          ),
        );
      },
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
