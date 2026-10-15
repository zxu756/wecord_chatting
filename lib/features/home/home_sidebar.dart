import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/circles/circle_channel_sidebar.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/groups/group_creation_sheet.dart';
import 'package:wecord/features/home/user_panel.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/presence_status.dart';

/// What Home shows beside its sidebar.
enum HomeSection { friends, inbox, conversation }

/// Home's sidebar: search, Friends, Notifications (wide layouts, where there
/// is no tab for them) and the direct message list. On wide layouts the
/// voice panel and the user panel sit at the bottom.
class HomeSidebar extends ConsumerWidget {
  const HomeSidebar({
    this.section,
    this.selectedConversationId,
    this.onOpenVoice,
    this.width = defaultWidth,
    super.key,
  });

  static const defaultWidth = CircleChannelSidebar.defaultWidth;

  /// The selected entry; null on phones, where entries open full screen.
  final HomeSection? section;

  /// The direct message open beside the sidebar.
  final String? selectedConversationId;

  /// Opens the voice channel of the current call from the voice panel.
  final ValueChanged<VoiceSession>? onOpenVoice;

  /// Fixed width, or null to fill the available space.
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final wide = isWideLayout(MediaQuery.sizeOf(context).width);
    final requestCount =
        ref.watch(incomingFriendRequestsProvider).valueOrNull?.length ?? 0;
    final unreadInbox =
        ref
            .watch(inboxProvider)
            .valueOrNull
            ?.where((item) => item.isUnread)
            .length ??
        0;
    final conversations = ref.watch(conversationsProvider);
    final onlineUserIds =
        ref.watch(onlineUserIdsProvider).valueOrNull ?? const <String>{};
    final presenceStatuses = ref.watch(presenceStatusesProvider).valueOrNull;

    final directMessages = [
      for (final conversation
          in conversations.valueOrNull ?? const <ConversationSummary>[])
        if (conversation.isDirectMessage) conversation,
    ];

    return Material(
      color: colorScheme.surfaceContainerLow,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: kToolbarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Material(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    key: const ValueKey('home-search'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () =>
                        openPage(context, GlobalMessageSearchScreen.path),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr('Find or start a conversation'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.search,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                children: [
                  CircleChannelRow(
                    key: const ValueKey('home-friends'),
                    icon: Icons.people_alt_outlined,
                    label: tr('Friends'),
                    selected: section == HomeSection.friends,
                    onTap: () => openPage(context, ContactsScreen.path),
                    trailing: requestCount > 0
                        ? _CountBadge(count: requestCount)
                        : null,
                  ),
                  if (wide)
                    CircleChannelRow(
                      key: const ValueKey('home-inbox'),
                      icon: Icons.notifications_none,
                      label: tr('Notifications'),
                      selected: section == HomeSection.inbox,
                      onTap: () => openPage(context, InboxScreen.path),
                      trailing: unreadInbox > 0
                          ? _CountBadge(count: unreadInbox)
                          : null,
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 0, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('DIRECT MESSAGES'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: tr('New group'),
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          onPressed: () => createGroupChat(context, ref),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                  if (conversations.isLoading && directMessages.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (directMessages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                      child: Text(
                        tr('No conversations yet'),
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  else
                    for (final conversation in directMessages)
                      _DirectMessageRow(
                        conversation: conversation,
                        selected:
                            section == HomeSection.conversation &&
                            conversation.id == selectedConversationId,
                        presence: presenceOf(
                          conversation.directUserId,
                          onlineUserIds: onlineUserIds,
                          statuses: presenceStatuses,
                        ),
                      ),
                ],
              ),
            ),
            if (wide) ...[
              if (ref.watch(voiceSessionProvider) != null) ...[
                const Divider(height: 1),
                VoiceConnectedPanel(onOpen: onOpenVoice),
              ],
              const Divider(height: 1),
              const UserPanel(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Picks friends for a new group chat and opens it.
Future<void> createGroupChat(BuildContext context, WidgetRef ref) async {
  final friends = await ref.read(friendsProvider.future);
  if (!context.mounted) {
    return;
  }
  if (friends.length < 2) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Add at least two friends to start a group.'))),
    );
    return;
  }
  final result = await showModalBottomSheet<GroupCreationResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => GroupCreationSheet(friends: friends),
  );
  if (result == null || !context.mounted) {
    return;
  }
  ref.invalidate(conversationsProvider);
  openPage(
    context,
    '${ChatsScreen.path}/${result.conversationId}',
    extra: ChatThreadRouteExtra(
      title: result.title,
      type: ConversationType.group,
    ),
  );
}

class _DirectMessageRow extends ConsumerWidget {
  const _DirectMessageRow({
    required this.conversation,
    required this.selected,
    required this.presence,
  });

  final ConversationSummary conversation;
  final bool selected;

  /// The other person's status; null while they're offline.
  final PresenceStatus? presence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = conversation.title?.trim().isNotEmpty == true
        ? conversation.title!
        : tr('Conversation');
    final unread = conversation.unreadCount > 0 || conversation.isMarkedUnread;
    final emphasized = selected || (unread && !conversation.isMuted);
    final foreground = emphasized
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;
    final status = activeCustomStatus(conversation.directCustomStatus);
    // The open conversation's draft is right there in its composer.
    final draft = selected
        ? null
        : ref.watch(
            composerDraftsProvider.select((drafts) => drafts[conversation.id]),
          );
    final subtitle = conversation.type == ConversationType.group
        ? tr('{count} members', {'count': conversation.memberCount})
        : status?.label;

    return Padding(
      key: ValueKey('home-dm-${conversation.id}'),
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? colorScheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => openConversation(context, conversation),
          onLongPress: () =>
              showConversationActions(context, ref, conversation),
          onSecondaryTap: () =>
              showConversationActions(context, ref, conversation),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    FallbackAvatar(
                      title: title,
                      avatarUrl: conversation.avatarUrl,
                      radius: 16,
                    ),
                    if (conversation.type == ConversationType.direct)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: PresenceIndicator(
                          status: presence,
                          borderColor: colorScheme.surfaceContainerLow,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: emphasized
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (draft != null && draft.hasText)
                        DraftPreviewText(
                          draft: draft,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      else if (subtitle != null)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (conversation.isMuted)
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                if (conversation.unreadCount > 0 && !conversation.isMuted)
                  _CountBadge(count: conversation.unreadCount),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4),
      child: Badge(label: Text(count > 99 ? '99+' : '$count')),
    );
  }
}
