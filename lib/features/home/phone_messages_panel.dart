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
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/features/home/home_sidebar.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The phone home's panel: the large "Messages" title with search and an
/// accent compose button, a row of friends (Add friend first, then online
/// friends first) and the direct and group chats with their latest
/// message.
class PhoneMessagesPanel extends ConsumerWidget {
  const PhoneMessagesPanel({this.bottomInset = 0, super.key});

  /// Space below the list for the floating user panel.
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = context.tokens.colors;
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
            padding: const EdgeInsets.fromLTRB(16, 18, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      tr('Messages'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        color: c.ink,
                      ),
                    ),
                  ),
                ),
                WeCordIconButton(
                  key: const ValueKey('phone-home-search'),
                  icon: Icons.search_rounded,
                  tooltip: tr('Search'),
                  iconSize: 21,
                  onPressed: () =>
                      openPage(context, GlobalMessageSearchScreen.path),
                ),
                WeCordIconButton(
                  key: const ValueKey('phone-home-new'),
                  icon: Icons.add_rounded,
                  tooltip: tr('New message'),
                  variant: WeCordButtonVariant.accent,
                  iconSize: 22,
                  onPressed: () => showNewConversationMenu(context, ref),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 102,
            child: ListView.separated(
              key: const ValueKey('phone-friends-row'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              itemCount: sortedFriends.length + 1,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _AddFriendTile(requestCount: requestCount);
                }
                final friend = sortedFriends[index - 1];
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
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Text(
                tr('No conversations yet'),
                style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            sliver: SliverList.separated(
              itemCount: chats.length,
              separatorBuilder: (context, index) => const SizedBox(height: 2),
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
}

/// Asks whether to start a direct message or a group, then starts it.
Future<void> showNewConversationMenu(
  BuildContext context,
  WidgetRef ref,
) async {
  final choice = await showWeCordSheet<_NewChoice>(
    context,
    builder: (sheetContext, _) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: SettingsGroup(
        color: sheetContext.tokens.colors.well,
        children: [
          SettingsRow(
            key: const ValueKey('phone-new-message'),
            icon: Icons.chat_bubble_outline_rounded,
            tone: SettingsTone.accent,
            title: tr('New message'),
            showChevron: false,
            onTap: () => Navigator.of(sheetContext).pop(_NewChoice.message),
          ),
          SettingsRow(
            key: const ValueKey('phone-new-group'),
            icon: Icons.group_add_outlined,
            tone: SettingsTone.success,
            title: tr('New group'),
            showChevron: false,
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
  final friend = await showWeCordSheet<Profile>(
    context,
    title: tr('New message'),
    builder: (sheetContext, _) => _FriendPickerSheet(friends: friends),
  );
  if (friend != null && context.mounted) {
    await openDirectMessage(context, ref, friend);
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

/// A 62 wide tile in the friends row: [leading] (58) over a short label.
class _QuickFriendTile extends StatelessWidget {
  const _QuickFriendTile({
    required this.label,
    required this.leading,
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  final String label;
  final Widget leading;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip ?? label,
      excludeSemantics: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) => SizedBox(
        width: 62,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: c.ink, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Add friend", first in the friends row: opens Friends, with a badge for
/// pending requests.
class _AddFriendTile extends StatelessWidget {
  const _AddFriendTile({required this.requestCount});

  final int requestCount;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    Widget tile = Container(
      width: 58,
      height: 58,
      decoration: ShapeDecoration(
        color: c.raised,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Icon(Icons.person_add_alt_outlined, size: 22, color: c.muted),
    );
    if (requestCount > 0) {
      tile = Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          Positioned(
            right: -5,
            top: -5,
            child: CountBadge(
              key: const ValueKey('phone-friend-requests-badge'),
              count: requestCount,
              size: 18,
              ringColor: c.panel,
            ),
          ),
        ],
      );
    }
    return _QuickFriendTile(
      key: const ValueKey('phone-home-add-friends'),
      label: tr('Add friend'),
      tooltip: requestCount > 0
          ? tr('Add friend · {count} requests', {'count': requestCount})
          : null,
      onPressed: () => openPage(context, ContactsScreen.path),
      leading: tile,
    );
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile({required this.friend, required this.presence});

  final Profile friend;
  final PresenceStatus? presence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _QuickFriendTile(
      key: ValueKey('phone-friend-${friend.id}'),
      label: friend.displayLabel,
      tooltip: friend.displayLabel,
      onPressed: () => openDirectMessage(context, ref, friend),
      leading: ResolvedAvatar(
        name: friend.displayLabel,
        avatarUrl: friend.avatarUrl,
        size: 58,
        showPresence: true,
        presence: presence,
      ),
    );
  }
}

/// "Draft  half written" in conversation lists, the label in red-orange.
class ConversationDraftPreview extends StatelessWidget {
  const ConversationDraftPreview({required this.draft, this.style, super.key});

  final ComposerDraft draft;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final text = draft.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return Text.rich(
      key: const ValueKey('conversation-draft'),
      TextSpan(
        children: [
          TextSpan(
            text: tr('Draft'),
            style: TextStyle(color: c.dangerText, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: ' $text'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// A direct or group chat on the phone home: avatar (a circle with
/// presence for people, a squircle for groups), name, the latest message
/// (with an icon for media and calls) and how long ago it was, and unread,
/// muted and pinned markers. Unread rows are tinted. Long press (or right
/// click) for actions.
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
    final c = context.tokens.colors;
    final title = conversation.title?.trim().isNotEmpty == true
        ? conversation.title!
        : tr('Conversation');
    final unreadCount = conversation.unreadCount;
    final unread = unreadCount > 0 || conversation.isMarkedUnread;
    final emphasized = unread && !conversation.isMuted;
    final group = conversation.type == ConversationType.group;
    final ConversationPreview? preview =
        conversationPreview(conversation, currentUserId: currentUserId) ??
        (group && conversation.memberCount > 0
            ? (
                icon: null,
                text: tr('{count} members', {
                  'count': conversation.memberCount,
                }),
              )
            : switch (activeCustomStatus(
                conversation.directCustomStatus,
              )?.label) {
                final String status => (icon: null, text: status),
                null => null,
              });
    final lastMessageAt = conversation.lastMessageAt;
    final draft = ref.watch(
      composerDraftsProvider.select((drafts) => drafts[conversation.id]),
    );
    final hasDraft = draft != null && draft.hasText;
    final previewStyle = TextStyle(
      fontSize: 14,
      height: 1.35,
      color: emphasized ? c.ink : c.muted,
      fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
    );

    return GestureDetector(
      onSecondaryTap: () => showConversationActions(context, ref, conversation),
      child: WeCordPressable(
        key: ValueKey('home-dm-${conversation.id}'),
        onPressed: () => openConversation(context, conversation),
        onLongPress: () => showConversationActions(context, ref, conversation),
        pressedScale: 0.98,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        builder: (context, states) {
          final hovered =
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed);
          final background = emphasized
              ? c.accentSoft
              : hovered
              ? c.raised
              : c.panel;
          return AnimatedContainer(
            duration: WeCordMotion.quick,
            curve: WeCordMotion.standard,
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: context.density.space(9),
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Row(
              children: [
                ResolvedAvatar(
                  name: title,
                  avatarUrl: conversation.avatarUrl,
                  squircle: group,
                  showPresence: conversation.type == ConversationType.direct,
                  presence: presence,
                  ringColor: background,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.3,
                                color: c.ink,
                                fontWeight: emphasized
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (conversation.pinnedAt != null) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.push_pin, size: 14, color: c.subtle),
                          ],
                          if (conversation.isMuted) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.notifications_off_outlined,
                              size: 14,
                              color: c.subtle,
                            ),
                          ],
                          if (lastMessageAt != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              compactAge(lastMessageAt),
                              key: ValueKey('home-dm-age-${conversation.id}'),
                              style: TextStyle(
                                fontSize: 12,
                                color: emphasized ? c.accentText : c.muted,
                                fontWeight: emphasized
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (preview != null || unread || hasDraft)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Row(
                            children: [
                              Expanded(
                                child: hasDraft
                                    ? ConversationDraftPreview(
                                        draft: draft,
                                        style: previewStyle,
                                      )
                                    : _PreviewLine(
                                        preview: preview,
                                        style: previewStyle,
                                      ),
                              ),
                              if (unreadCount > 0) ...[
                                const SizedBox(width: 6),
                                CountBadge(
                                  count: unreadCount,
                                  tone: conversation.isMuted
                                      ? BadgeTone.quiet
                                      : BadgeTone.unread,
                                ),
                              ] else if (unread) ...[
                                const SizedBox(width: 6),
                                CountBadge.dot(
                                  tone: conversation.isMuted
                                      ? BadgeTone.quiet
                                      : BadgeTone.unread,
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The preview text, after a small icon for media and calls.
class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.preview, required this.style});

  final ConversationPreview? preview;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final preview = this.preview;
    final text = Text(
      preview?.text ?? '',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final icon = preview?.icon;
    if (icon == null) {
      return text;
    }
    return Row(
      children: [
        Icon(icon, size: 15, color: style.color),
        const SizedBox(width: 5),
        Flexible(child: text),
      ],
    );
  }
}

class _FriendPickerSheet extends ConsumerWidget {
  const _FriendPickerSheet({required this.friends});

  final List<Profile> friends;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final onlineIds =
        ref.watch(onlineUserIdsProvider).valueOrNull ?? const <String>{};
    final statuses = ref.watch(presenceStatusesProvider).valueOrNull;
    final sorted = [...friends]
      ..sort(
        (a, b) => a.displayLabel.toLowerCase().compareTo(
          b.displayLabel.toLowerCase(),
        ),
      );
    if (sorted.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Text(
          tr('Add friends to start a conversation.'),
          style: TextStyle(fontSize: 15, color: c.muted),
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      children: [
        for (final friend in sorted)
          WeCordPressable(
            key: ValueKey('phone-pick-friend-${friend.id}'),
            onPressed: () => Navigator.of(context).pop(friend),
            pressedScale: 0.98,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            builder: (context, states) {
              final hovered = states.contains(WidgetState.hovered);
              final background = hovered ? c.raised : c.panel;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(WeCordRadii.lg),
                ),
                child: Row(
                  children: [
                    ResolvedAvatar(
                      name: friend.displayLabel,
                      avatarUrl: friend.avatarUrl,
                      size: 42,
                      showPresence: true,
                      ringColor: background,
                      presence: presenceOf(
                        friend.id,
                        onlineUserIds: onlineIds,
                        statuses: statuses,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            friend.displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            '@${friend.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
