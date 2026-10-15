import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/home/conversation_preview.dart';
import 'package:wecord/features/home/home_sidebar.dart';
import 'package:wecord/features/home/phone_home.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/models/profile.dart';

/// The phone home's panel: the "Messages" title, search, Add Friends and
/// new message buttons, a row of friends (online first) and the direct and
/// group chats with their latest message.
class PhoneMessagesPanel extends ConsumerWidget {
  const PhoneMessagesPanel({this.bottomInset = 0, super.key});

  /// Space below the list for the floating user panel.
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final conversations = ref.watch(conversationsProvider);
    final friends = ref.watch(friendsProvider).valueOrNull ?? const <Profile>[];
    final onlineIds =
        ref.watch(onlineUserIdsProvider).valueOrNull ?? const <String>{};
    final statuses = ref.watch(presenceStatusesProvider).valueOrNull;
    PresenceStatus? presence(String? userId) =>
        presenceOf(userId, onlineUserIds: onlineIds, statuses: statuses);
    final requestCount =
        ref.watch(incomingFriendRequestsProvider).valueOrNull?.length ?? 0;
    final currentUserId = ref.watch(authStateProvider).valueOrNull?.id;

    final chats = [
      for (final conversation
          in conversations.valueOrNull ?? const <ConversationSummary>[])
        if (conversation.isDirectMessage) conversation,
    ];
    final sortedFriends = [
      ...friends.where((friend) => onlineIds.contains(friend.id)),
      ...friends.where((friend) => !onlineIds.contains(friend.id)),
    ];

    return CustomScrollView(
      key: const ValueKey('phone-messages-list'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              tr('Messages'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                _RoundButton(
                  key: const ValueKey('phone-home-search'),
                  tooltip: tr('Search'),
                  icon: Icons.search,
                  onPressed: () =>
                      openPage(context, GlobalMessageSearchScreen.path),
                ),
                const SizedBox(width: 8),
                Expanded(child: _AddFriendsButton(requestCount: requestCount)),
                const SizedBox(width: 8),
                _RoundButton(
                  key: const ValueKey('phone-home-new'),
                  tooltip: tr('New message'),
                  icon: Icons.add,
                  accent: true,
                  onPressed: () => _showNewMenu(context, ref),
                ),
              ],
            ),
          ),
        ),
        if (sortedFriends.isNotEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 80,
              child: ListView.separated(
                key: const ValueKey('phone-friends-row'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                itemCount: sortedFriends.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final friend = sortedFriends[index];
                  return _FriendTile(
                    friend: friend,
                    presence: presence(friend.id),
                  );
                },
              ),
            ),
          ),
        if (conversations.isLoading && chats.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (chats.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Text(
                tr('No conversations yet'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(top: 4),
            sliver: SliverList.builder(
              itemCount: chats.length,
              itemBuilder: (context, index) => PhoneConversationRow(
                conversation: chats[index],
                currentUserId: currentUserId,
                presence: presence(chats[index].directUserId),
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: bottomInset + 8)),
      ],
    );
  }

  Future<void> _showNewMenu(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<_NewChoice>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('phone-new-message'),
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(tr('New message')),
              onTap: () => Navigator.of(sheetContext).pop(_NewChoice.message),
            ),
            ListTile(
              key: const ValueKey('phone-new-group'),
              leading: const Icon(Icons.group_add_outlined),
              title: Text(tr('New group')),
              onTap: () => Navigator.of(sheetContext).pop(_NewChoice.group),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) {
      return;
    }
    switch (choice) {
      case _NewChoice.message:
        await _pickFriendToMessage(context, ref);
      case _NewChoice.group:
        await createGroupChat(context, ref);
      case null:
        break;
    }
  }

  Future<void> _pickFriendToMessage(BuildContext context, WidgetRef ref) async {
    final friends = await ref.read(friendsProvider.future);
    if (!context.mounted) {
      return;
    }
    final friend = await showModalBottomSheet<Profile>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _FriendPickerSheet(friends: friends),
    );
    if (friend != null && context.mounted) {
      await openDirectMessage(context, ref, friend);
    }
  }
}

enum _NewChoice { message, group }

/// Opens the direct message with [friend], starting one if needed.
Future<void> openDirectMessage(
  BuildContext context,
  WidgetRef ref,
  Profile friend,
) async {
  final existing = ref
      .read(conversationsProvider)
      .valueOrNull
      ?.where(
        (conversation) =>
            conversation.type == ConversationType.direct &&
            conversation.directUserId == friend.id,
      )
      .firstOrNull;
  if (existing != null) {
    openConversation(context, existing);
    return;
  }
  try {
    final conversationId = await ref
        .read(chatsRepositoryProvider)
        .getOrCreateDirectConversation(friend.id);
    ref.invalidate(conversationsProvider);
    if (!context.mounted) {
      return;
    }
    openPage(
      context,
      '${ChatsScreen.path}/$conversationId',
      extra: ChatThreadRouteExtra(
        title: friend.displayLabel,
        type: ConversationType.direct,
        avatarUrl: friend.avatarUrl,
      ),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Unable to start chat: {error}', {'error': error})),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.accent = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: accent
            ? colors.primary
            : PhoneHomeColors.raised(colors),
        foregroundColor: accent ? colors.onPrimary : colors.onSurface,
        fixedSize: const Size.square(44),
        minimumSize: const Size.square(44),
      ),
      icon: Icon(icon),
    );
  }
}

class _AddFriendsButton extends StatelessWidget {
  const _AddFriendsButton({required this.requestCount});

  /// Pending friend requests, shown as a badge.
  final int requestCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: PhoneHomeColors.raised(colors),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('phone-home-add-friends'),
        onTap: () => openPage(context, ContactsScreen.path),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add_alt_1, size: 20, color: colors.onSurface),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    tr('Add Friends'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (requestCount > 0) ...[
                  const SizedBox(width: 6),
                  Badge(
                    key: const ValueKey('phone-friend-requests-badge'),
                    label: Text(requestCount > 99 ? '99+' : '$requestCount'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile({required this.friend, required this.presence});

  final Profile friend;
  final PresenceStatus? presence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final background = PhoneHomeColors.raised(colors);
    return Tooltip(
      message: friend.displayLabel,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('phone-friend-${friend.id}'),
          onTap: () => openDirectMessage(context, ref, friend),
          child: SizedBox.square(
            dimension: 64,
            child: Center(
              child: PresenceAvatar(
                title: friend.displayLabel,
                avatarUrl: friend.avatarUrl,
                radius: 22,
                presence: presence,
                borderColor: background,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A direct or group chat on the phone home: avatar (with presence for
/// direct messages), name, the latest message and how long ago it was,
/// and unread, muted and pinned markers. Long press for actions.
class PhoneConversationRow extends ConsumerWidget {
  const PhoneConversationRow({
    required this.conversation,
    required this.currentUserId,
    required this.presence,
    super.key,
  });

  final ConversationSummary conversation;
  final String? currentUserId;

  /// The other person's status in a direct message; null while offline.
  final PresenceStatus? presence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = conversation.title?.trim().isNotEmpty == true
        ? conversation.title!
        : tr('Conversation');
    final unreadCount = conversation.unreadCount;
    final unread = unreadCount > 0 || conversation.isMarkedUnread;
    final emphasized = unread && !conversation.isMuted;
    final muted = colors.onSurfaceVariant;
    final preview =
        conversationPreviewText(conversation, currentUserId: currentUserId) ??
        (conversation.type == ConversationType.group &&
                conversation.memberCount > 0
            ? tr('{count} members', {'count': conversation.memberCount})
            : activeCustomStatus(conversation.directCustomStatus)?.label);
    final lastMessageAt = conversation.lastMessageAt;
    final draft = ref.watch(
      composerDraftsProvider.select((drafts) => drafts[conversation.id]),
    );
    final hasDraft = draft != null && draft.hasText;
    final previewStyle = theme.textTheme.bodyMedium?.copyWith(
      color: emphasized ? colors.onSurface : muted,
      fontWeight: emphasized ? FontWeight.w600 : null,
    );

    return InkWell(
      key: ValueKey('home-dm-${conversation.id}'),
      onTap: () => openConversation(context, conversation),
      onLongPress: () => showConversationActions(context, ref, conversation),
      onSecondaryTap: () => showConversationActions(context, ref, conversation),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            PresenceAvatar(
              title: title,
              avatarUrl: conversation.avatarUrl,
              radius: 22,
              presence: presence,
              showPresence: conversation.type == ConversationType.direct,
              borderColor: PhoneHomeColors.panel(colors),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: emphasized
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: emphasized ? colors.onSurface : null,
                          ),
                        ),
                      ),
                      if (conversation.pinnedAt != null) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.push_pin, size: 14, color: muted),
                      ],
                      if (conversation.isMuted) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 14,
                          color: muted,
                        ),
                      ],
                      if (lastMessageAt != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          compactAge(lastMessageAt),
                          key: ValueKey('home-dm-age-${conversation.id}'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: emphasized ? colors.onSurface : muted,
                            fontWeight: emphasized ? FontWeight.w700 : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (preview != null || unread || hasDraft)
                    Row(
                      children: [
                        Expanded(
                          child: hasDraft
                              ? DraftPreviewText(
                                  draft: draft,
                                  style: previewStyle,
                                )
                              : Text(
                                  preview ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: previewStyle,
                                ),
                        ),
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 6),
                          Badge(
                            backgroundColor: conversation.isMuted
                                ? colors.outline
                                : null,
                            label: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                            ),
                          ),
                        ] else if (unread) ...[
                          const SizedBox(width: 6),
                          Badge(
                            backgroundColor: conversation.isMuted
                                ? colors.outline
                                : null,
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendPickerSheet extends ConsumerWidget {
  const _FriendPickerSheet({required this.friends});

  final List<Profile> friends;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final onlineIds =
        ref.watch(onlineUserIdsProvider).valueOrNull ?? const <String>{};
    final statuses = ref.watch(presenceStatusesProvider).valueOrNull;
    final sorted = [...friends]
      ..sort(
        (a, b) => a.displayLabel.toLowerCase().compareTo(
          b.displayLabel.toLowerCase(),
        ),
      );
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(tr('New message'), style: theme.textTheme.titleMedium),
          ),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Text(tr('Add friends to start a conversation.')),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final friend in sorted)
                    ListTile(
                      key: ValueKey('phone-pick-friend-${friend.id}'),
                      leading: PresenceAvatar(
                        title: friend.displayLabel,
                        avatarUrl: friend.avatarUrl,
                        radius: 20,
                        presence: presenceOf(
                          friend.id,
                          onlineUserIds: onlineIds,
                          statuses: statuses,
                        ),
                        borderColor: theme.colorScheme.surfaceContainerLow,
                      ),
                      title: Text(
                        friend.displayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '@${friend.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(context).pop(friend),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
