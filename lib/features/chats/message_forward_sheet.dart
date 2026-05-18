import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

class MessageForwardSheet extends ConsumerStatefulWidget {
  const MessageForwardSheet({required this.message, super.key});

  final ChatMessage message;

  @override
  ConsumerState<MessageForwardSheet> createState() =>
      _MessageForwardSheetState();
}

class _MessageForwardSheetState extends ConsumerState<MessageForwardSheet> {
  var _query = '';
  var _isForwarding = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Forward to',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  autofocus: true,
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
              if (_errorText != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    _errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Flexible(
                child: conversations.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        error.toString(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                  data: _buildConversationList,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversationList(List<ConversationSummary> conversations) {
    final normalizedQuery = _query.trim().toLowerCase();
    final visibleConversations = conversations
        .where((conversation) {
          if (conversation.id == widget.message.conversationId) {
            return false;
          }
          if (normalizedQuery.isEmpty) {
            return true;
          }
          return conversation.title?.toLowerCase().contains(normalizedQuery) ??
              false;
        })
        .toList(growable: false);

    if (visibleConversations.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No matching conversations'),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: visibleConversations.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final conversation = visibleConversations[index];
        final title = conversation.title?.trim().isNotEmpty == true
            ? conversation.title!.trim()
            : 'Conversation';
        return ListTile(
          enabled: !_isForwarding,
          leading: Icon(
            conversation.type == ConversationType.group
                ? Icons.group_outlined
                : Icons.person_outline,
          ),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            conversation.type == ConversationType.group ? 'Group' : 'Direct',
          ),
          onTap: _isForwarding
              ? null
              : () => _forwardToConversation(conversation.id),
        );
      },
    );
  }

  Future<void> _forwardToConversation(String conversationId) async {
    setState(() {
      _isForwarding = true;
      _errorText = null;
    });
    final repository = ref.read(chatsRepositoryProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repository.forwardMessage(
        sourceMessageId: widget.message.id,
        targetConversationId: conversationId,
      );
      ref.invalidate(conversationsProvider);
      if (!mounted) {
        return;
      }
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Message forwarded')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isForwarding = false;
        _errorText = 'Could not forward message. Try again.';
      });
    }
  }
}
