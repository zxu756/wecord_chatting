import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/chats/pinned_messages_sheet.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/inbox/inbox_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

final inboxProvider = FutureProvider.autoDispose<List<InboxItem>>((ref) {
  // New messages (and reads) show up in the conversation list first.
  ref.listen(conversationsProvider, (previous, next) {
    if (previous != null && previous.hasValue && next is AsyncData) {
      ref.invalidateSelf();
    }
  });
  return ref.watch(inboxRepositoryProvider).listInbox();
});

/// Unread mentions and replies plus pending friend requests, for the
/// Notifications badge.
final inboxBadgeCountProvider = Provider.autoDispose<int>((ref) {
  final unread =
      ref
          .watch(inboxProvider)
          .valueOrNull
          ?.where((item) => item.isUnread)
          .length ??
      0;
  final requests =
      ref.watch(incomingFriendRequestsProvider).valueOrNull?.length ?? 0;
  return unread + requests;
});

/// Mentions of and replies to the current user, with pending friend
/// requests on top.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  static const path = '/notifications';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    final requestCount =
        ref.watch(incomingFriendRequestsProvider).valueOrNull?.length ?? 0;
    final conversations = {
      for (final conversation
          in ref.watch(conversationsProvider).valueOrNull ??
              const <ConversationSummary>[])
        conversation.id: conversation,
    };
    final circles = {
      for (final circle
          in ref.watch(circleSummariesProvider).valueOrNull ??
              const <CircleSummary>[])
        circle.id: circle,
    };

    Future<void> refresh() async {
      ref
        ..invalidate(incomingFriendRequestsProvider)
        ..invalidate(inboxProvider);
      await ref.read(inboxProvider.future);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: inbox.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load notifications.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
          data: (items) => ListView(
            children: [
              if (requestCount > 0)
                ListTile(
                  key: const ValueKey('inbox-friend-requests'),
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_add_alt_1_outlined),
                  ),
                  title: const Text('Friend requests'),
                  subtitle: Text(
                    requestCount == 1
                        ? '1 pending request'
                        : '$requestCount pending requests',
                  ),
                  trailing: Badge(label: Text('$requestCount')),
                  onTap: () => openPage(context, ContactsScreen.path),
                ),
              if (items.isEmpty && requestCount == 0)
                const _EmptyInbox()
              else
                for (final item in items)
                  _InboxTile(
                    item: item,
                    conversation: conversations[item.conversationId],
                    circles: circles,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({
    required this.item,
    required this.conversation,
    required this.circles,
  });

  final InboxItem item;
  final ConversationSummary? conversation;
  final Map<String, CircleSummary> circles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final place = _placeLabel();
    final reason = switch (item.reason) {
      InboxReason.mention => 'Mentioned you',
      InboxReason.mentionAll => 'Mentioned everyone',
      InboxReason.reply => 'Replied to you',
    };

    return ListTile(
      key: ValueKey('inbox-item-${item.messageId}'),
      leading: FallbackAvatar(
        title: item.senderName,
        avatarUrl: item.senderAvatarUrl,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              item.senderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: item.isUnread
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : null,
            ),
          ),
          if (place != null)
            Flexible(
              child: Text(
                '  ·  $place',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reason,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          Text(
            inboxPreviewText(item),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatInboxTime(item.createdAt.toLocal(), DateTime.now()),
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
          if (item.isUnread) ...[
            const SizedBox(height: 6),
            const Badge(key: ValueKey('inbox-unread-dot')),
          ],
        ],
      ),
      onTap: () {
        final conversation = this.conversation;
        if (conversation != null) {
          openConversation(context, conversation);
        } else {
          openPage(context, '${ChatsScreen.path}/${item.conversationId}');
        }
      },
    );
  }

  /// "#channel · Circle", the thread or group title, or nothing for a
  /// direct message (the sender says it all).
  String? _placeLabel() {
    final conversation = this.conversation;
    if (conversation == null) {
      return null;
    }
    final title = conversation.title?.trim();
    final circleName = circles[conversation.circleId]?.name;
    return switch (conversation.type) {
      ConversationType.direct => null,
      ConversationType.group => title,
      ConversationType.channel => [
        if (title != null && title.isNotEmpty) '#$title',
        ?circleName,
      ].join(' · '),
      ConversationType.thread => [
        if (title != null && title.isNotEmpty) title,
        ?circleName,
      ].join(' · '),
    };
  }
}

/// The message as one line of text, as in the pinned message list.
String inboxPreviewText(InboxItem item) {
  return pinnedMessagePreview(
    ChatMessage(
      id: item.messageId,
      conversationId: item.conversationId,
      senderId: item.senderId,
      type: item.type,
      body: item.body,
      createdAt: item.createdAt,
    ),
  );
}

String _formatInboxTime(DateTime value, DateTime now) {
  final sameDay =
      value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;
  if (sameDay) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  return '${value.month}/${value.day}';
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
      child: Column(
        children: [
          Icon(
            Icons.notifications_none,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('Nothing here yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Mentions and replies from the last 30 days show up here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
