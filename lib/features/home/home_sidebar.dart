import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/notifications/quiet_hours_indicator.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chat_folders/chat_folder_rules.dart';
import 'package:wecord/features/chat_folders/chat_folder_strip.dart';
import 'package:wecord/features/chat_folders/chat_folders_repository.dart';
import 'package:wecord/features/chat_folders/folded_folder_row.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/groups/group_creation_sheet.dart';
import 'package:wecord/features/home/conversation_preview.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/features/home/phone_messages_panel.dart';
import 'package:wecord/features/home/user_panel.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/later/reminders_repository.dart';
import 'package:wecord/features/later/saved_messages_screen.dart';
import 'package:wecord/features/note_to_self/note_to_self.dart';
import 'package:wecord/features/moments/moments_screen.dart';
import 'package:wecord/features/moments/moments_widgets.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/shell/keyboard_shortcuts.dart';
import 'package:wecord/features/shell/quick_switcher.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What Home shows beside its sidebar.
enum HomeSection { friends, inbox, saved, moments, conversation }

/// Home's sidebar on wide layouts: the "Messages" title with a compose
/// button, a search field that jumps anywhere (⌘K), Friends and
/// Notifications, and the direct and group chats. The voice panel sits at
/// the bottom during a call, above the floating user panel the shell lays
/// across the rail and this sidebar.
class HomeSidebar extends ConsumerWidget {
  const HomeSidebar({
    this.section,
    this.selectedConversationId,
    this.onOpenVoice,
    this.width = defaultWidth,
    super.key,
  });

  static const defaultWidth = WeCordSizes.sidebarDefault;

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
    final c = context.tokens.colors;
    final wide = isWideLayout(MediaQuery.sizeOf(context).width);
    final requestCount =
        ref.watch(incomingFriendRequestsProvider).value?.length ?? 0;
    final unreadInbox =
        (ref
                .watch(inboxProvider)
                .value
                ?.where((item) => item.isUnread)
                .length ??
            0) +
        ref.watch(firedRemindersProvider).length;
    final conversations = ref.watch(conversationsProvider);
    final onlineUserIds =
        ref.watch(onlineUserIdsProvider).value ?? const <String>{};
    final presenceStatuses = ref.watch(presenceStatusesProvider).value;
    final currentUserId = ref.watch(authStateProvider).value?.id;

    final directMessages = [
      for (final conversation
          in conversations.value ?? const <ConversationSummary>[])
        if (conversation.isDirectMessage && !conversation.isNoteToSelf)
          conversation,
    ];
    // The note to self comes first, even before the server made it.
    final listed = withNoteToSelfFirst([
      for (final conversation
          in conversations.value ?? const <ConversationSummary>[])
        if (conversation.isNoteToSelf) conversation,
      ...directMessages,
    ]);
    // The folder strip filters the list; under All, the folded folder's
    // chats show as one row.
    final folders = ref.watch(chatFoldersProvider).value ?? const [];
    final selectedFolder = ref.watch(effectiveChatFolderSelectionProvider);
    final entries = chatListEntries(
      chats: listed,
      folders: folders,
      selected: selectedFolder,
      userId: currentUserId,
    );

    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        tr('Messages'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                  WeCordIconButton(
                    key: const ValueKey('home-new'),
                    icon: Icons.add_rounded,
                    tooltip: tr('New message'),
                    variant: WeCordButtonVariant.accent,
                    size: 32,
                    iconSize: 19,
                    onPressed: () => showNewConversationMenu(context, ref),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _SidebarSearchField(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                children: [
                  SidebarNavRow(
                    key: const ValueKey('home-friends'),
                    icon: Icons.people_alt_outlined,
                    label: tr('Friends'),
                    selected: section == HomeSection.friends,
                    onTap: () => openPage(context, ContactsScreen.path),
                    badgeCount: requestCount,
                  ),
                  if (wide)
                    SidebarNavRow(
                      key: const ValueKey('home-inbox'),
                      icon: Icons.notifications_none_rounded,
                      label: tr('Notifications'),
                      selected: section == HomeSection.inbox,
                      onTap: () => openPage(context, InboxScreen.path),
                      badgeCount: unreadInbox,
                      trailing: const QuietHoursMoon(size: 18),
                    ),
                  if (wide)
                    SidebarNavRow(
                      key: const ValueKey('home-saved'),
                      icon: Icons.bookmark_border_rounded,
                      label: tr('Saved'),
                      selected: section == HomeSection.saved,
                      onTap: () => openPage(context, SavedMessagesScreen.path),
                    ),
                  if (wide)
                    SidebarNavRow(
                      key: const ValueKey('home-moments'),
                      icon: Icons.auto_awesome_motion_outlined,
                      label: tr('Moments'),
                      selected: section == HomeSection.moments,
                      onTap: () => openPage(context, MomentsScreen.path),
                      trailing: MomentsUnseenAvatar(ringColor: c.sidebar),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 2, 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('Direct messages'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: c.subtle,
                            ),
                          ),
                        ),
                        WeCordIconButton(
                          icon: Icons.add_rounded,
                          tooltip: tr('New group'),
                          variant: WeCordButtonVariant.ghost,
                          size: 26,
                          iconSize: 17,
                          onPressed: () => createGroupChat(context, ref),
                        ),
                      ],
                    ),
                  ),
                  const ChatFolderStrip(
                    padding: EdgeInsets.fromLTRB(4, 2, 4, 6),
                  ),
                  for (final entry in entries)
                    switch (entry) {
                      ConversationEntry(:final conversation) =>
                        _DirectMessageRow(
                          conversation: conversation,
                          currentUserId: currentUserId,
                          selected:
                              section == HomeSection.conversation &&
                              conversation.id == selectedConversationId,
                          presence: presenceOf(
                            conversation.directUserId,
                            onlineUserIds: onlineUserIds,
                            statuses: presenceStatuses,
                          ),
                        ),
                      final FoldedEntry folded => FoldedFolderRow(
                        entry: folded,
                        dense: true,
                        currentUserId: currentUserId,
                        onOpen: () => ref
                            .read(chatFolderSelectionProvider.notifier)
                            .select(folded.folder.id),
                      ),
                    },
                  if (conversations.isLoading && directMessages.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (directMessages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                      child: Text(
                        tr('No conversations yet'),
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  else if (entries.isEmpty)
                    ChatFolderEmptyNote(
                      selected: selectedFolder,
                      folders: folders,
                    ),
                ],
              ),
            ),
            if (wide) ...[
              if (ref.watch(voiceSessionProvider.select((s) => s != null)))
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(WeCordRadii.lg),
                    child: VoiceConnectedPanel(onOpen: onOpenVoice),
                  ),
                ),
              const SizedBox(height: UserPanel.reservedHeight),
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
  final result = await showWeCordSheet<GroupCreationResult>(
    context,
    builder: (context, _) => GroupCreationSheet(friends: friends),
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

/// The raised search field at the top of the sidebar; opens the quick
/// switcher, whose shortcut it shows.
class _SidebarSearchField extends StatelessWidget {
  const _SidebarSearchField();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final hint = usesCommandKey ? '⌘K' : 'Ctrl K';
    return WeCordPressable(
      key: const ValueKey('home-search'),
      onPressed: () => showQuickSwitcher(context),
      pressedScale: 0.99,
      semanticLabel: tr('Find or start a conversation'),
      excludeSemantics: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: tokens.isDark ? c.raised : c.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hovered ? c.track : c.line),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 17, color: c.subtle),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Find or start a conversation'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c.subtle),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(WeCordRadii.xs),
                  border: Border.all(color: c.line),
                ),
                child: Text(
                  hint,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: c.subtle,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The look of a desktop sidebar row: white with a hairline shadow when
/// [selected], a raised tint on hover, nothing at rest.
BoxDecoration sidebarRowDecoration(
  WeCordTokens tokens, {
  required bool selected,
  required bool hovered,
}) {
  final c = tokens.colors;
  return BoxDecoration(
    color: selected
        ? (tokens.isDark ? c.raised : c.panel)
        : hovered
        ? c.raised
        : c.raised.withValues(alpha: 0),
    borderRadius: BorderRadius.circular(12),
    boxShadow: selected ? tokens.shadows.hairline : null,
  );
}

/// A desktop sidebar entry with an icon (Friends, Notifications) and a red
/// count.
class SidebarNavRow extends StatelessWidget {
  const SidebarNavRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.badgeCount = 0,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final int badgeCount;

  /// Shown at the end of the row (Moments: the latest poster's avatar).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: WeCordPressable(
        onPressed: onTap,
        selected: selected,
        pressedScale: 0.98,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        builder: (context, states) => AnimatedContainer(
          duration: WeCordMotion.quick,
          curve: WeCordMotion.standard,
          // A minimum, so large text grows the row instead of clipping.
          constraints: BoxConstraints(minHeight: context.density.rowHeight(40)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: sidebarRowDecoration(
            tokens,
            selected: selected,
            hovered: states.contains(WidgetState.hovered),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: selected ? c.ink : c.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
              if (badgeCount > 0)
                CountBadge(
                  count: badgeCount,
                  size: 18,
                  tone: BadgeTone.mention,
                ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectMessageRow extends ConsumerWidget {
  const _DirectMessageRow({
    required this.conversation,
    required this.currentUserId,
    required this.selected,
    required this.presence,
  });

  final ConversationSummary conversation;
  final String? currentUserId;
  final bool selected;

  /// The other person's status; null while they're offline.
  final PresenceStatus? presence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final density = context.density;
    final title = conversation.isNoteToSelf
        ? noteToSelfTitle()
        : conversation.title?.trim().isNotEmpty == true
        ? conversation.title!
        : tr('Conversation');
    final unread = conversation.unreadCount > 0 || conversation.isMarkedUnread;
    final emphasized = selected || (unread && !conversation.isMuted);
    final group = conversation.type == ConversationType.group;
    // The open conversation's draft is right there in its composer.
    final draft = selected
        ? null
        : ref.watch(
            composerDraftsProvider.select((drafts) => drafts[conversation.id]),
          );
    final status = activeCustomStatus(conversation.directCustomStatus);
    final preview =
        conversationPreview(conversation, currentUserId: currentUserId) ??
        (conversation.isNoteToSelf
            ? (icon: null, text: noteToSelfHint())
            : group
            ? (
                icon: null,
                text: tr('{count} members', {
                  'count': conversation.memberCount,
                }),
              )
            : status == null
            ? null
            : (icon: null, text: status.label));
    final lastMessageAt = conversation.lastMessageAt;
    final subtitleStyle = TextStyle(
      fontSize: 12.5,
      height: 1.35,
      color: unread && !conversation.isMuted && !selected ? c.ink : c.muted,
      fontWeight: unread && !conversation.isMuted && !selected
          ? FontWeight.w600
          : FontWeight.w400,
    );

    return GestureDetector(
      key: ValueKey('home-dm-${conversation.id}'),
      onSecondaryTap: () => showConversationActions(context, ref, conversation),
      excludeFromSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 0.5),
        child: WeCordPressable(
          semanticLabel: conversationRowLabel(
            conversation,
            title: title,
            presence: presence,
            preview: preview?.text,
          ),
          excludeSemantics: true,
          onPressed: () => openConversation(context, conversation),
          onLongPress: () =>
              showConversationActions(context, ref, conversation),
          selected: selected,
          pressedScale: 0.98,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          builder: (context, states) {
            final hovered = states.contains(WidgetState.hovered);
            final ring = selected
                ? (tokens.isDark ? c.raised : c.panel)
                : hovered
                ? c.raised
                : c.sidebar;
            return AnimatedContainer(
              duration: WeCordMotion.quick,
              curve: WeCordMotion.standard,
              constraints: BoxConstraints(minHeight: density.minRowHeight),
              padding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: density.space(7),
              ),
              decoration: sidebarRowDecoration(
                tokens,
                selected: selected,
                hovered: hovered,
              ),
              child: Row(
                children: [
                  if (conversation.isNoteToSelf)
                    NoteToSelfAvatar(size: density.avatar(36))
                  else
                    ResolvedAvatar(
                      name: title,
                      avatarUrl: conversation.avatarUrl,
                      size: density.avatar(36),
                      squircle: group,
                      showPresence:
                          conversation.type == ConversationType.direct,
                      presence: presence,
                      ringColor: ring,
                    ),
                  const SizedBox(width: 10),
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
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.3,
                                  color: c.ink,
                                  fontWeight: emphasized
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                            if (conversation.isMuted) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.notifications_off_outlined,
                                size: 13,
                                color: c.subtle,
                              ),
                            ],
                            if (lastMessageAt != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                compactAge(lastMessageAt),
                                style: TextStyle(fontSize: 11, color: c.muted),
                              ),
                            ],
                          ],
                        ),
                        if (draft != null && draft.hasText)
                          ConversationDraftPreview(
                            draft: draft,
                            style: subtitleStyle,
                          )
                        else if (preview != null || unread)
                          Row(
                            children: [
                              if (preview?.icon case final icon?) ...[
                                Icon(
                                  icon,
                                  size: 13,
                                  color: subtitleStyle.color,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  preview?.text ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: subtitleStyle,
                                ),
                              ),
                              if (conversation.unreadCount > 0 &&
                                  !conversation.isMuted) ...[
                                const SizedBox(width: 4),
                                CountBadge(
                                  count: conversation.unreadCount,
                                  size: 17,
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
