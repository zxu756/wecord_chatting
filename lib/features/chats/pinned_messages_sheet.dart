import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/poll.dart';
import 'package:wecord/shared/models/pinned_message.dart';

final pinnedMessagesProvider = FutureProvider.autoDispose
    .family<List<PinnedMessage>, String>((ref, conversationId) {
      return ref
          .watch(chatsRepositoryProvider)
          .listPinnedMessages(conversationId);
    });

final canPinMessagesProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  conversationId,
) {
  return ref.watch(chatsRepositoryProvider).canPinMessages(conversationId);
});

/// Lists a conversation's pinned messages. Tapping one pops the sheet with
/// that message's id so the thread can scroll to it.
class PinnedMessagesSheet extends ConsumerWidget {
  const PinnedMessagesSheet({
    required this.conversationId,
    required this.canManagePins,
    required this.onUnpin,
    super.key,
  });

  final String conversationId;
  final bool canManagePins;
  final Future<void> Function(String messageId) onUnpin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(pinnedMessagesProvider(conversationId));
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Pinned messages',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: pinned.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stackTrace) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load pinned messages.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No pinned messages yet'),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _PinnedMessageTile(
                        item: item,
                        canManagePins: canManagePins,
                        onOpen: () {
                          Navigator.of(context).pop(item.message.id);
                        },
                        onUnpin: () => unawaited(onUnpin(item.message.id)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedMessageTile extends StatelessWidget {
  const _PinnedMessageTile({
    required this.item,
    required this.canManagePins,
    required this.onOpen,
    required this.onUnpin,
  });

  final PinnedMessage item;
  final bool canManagePins;
  final VoidCallback onOpen;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pinnedByName = item.pinnedByName?.trim();
    return ListTile(
      leading: const Icon(Icons.push_pin_outlined),
      title: Text(
        item.sender.displayLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pinnedMessagePreview(item.message),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (pinnedByName != null && pinnedByName.isNotEmpty)
            Text(
              'Pinned by $pinnedByName',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      trailing: canManagePins
          ? IconButton(
              tooltip: 'Unpin',
              icon: const Icon(Icons.close),
              onPressed: onUnpin,
            )
          : null,
      onTap: onOpen,
    );
  }
}

String pinnedMessagePreview(ChatMessage message) {
  final body = message.body.trim();
  return switch (message.type) {
    MessageType.text => body.isEmpty ? 'Message' : plainTextFromMarkdown(body),
    MessageType.system => body.isEmpty ? 'Message' : body,
    MessageType.image => 'Image',
    MessageType.file => 'File',
    MessageType.voice => 'Voice message',
    MessageType.poll => pollPreviewText(body),
  };
}
