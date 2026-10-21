import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/agenda/agenda_repository.dart';
import 'package:wecord/features/agenda/agenda_screen.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/care_mode/care_home_shortcuts.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chat_folders/chat_folder.dart';
import 'package:wecord/features/chat_folders/chat_folder_rules.dart';
import 'package:wecord/features/chat_folders/chat_folder_strip.dart';
import 'package:wecord/features/chat_folders/chat_folders_repository.dart';
import 'package:wecord/features/chat_folders/folded_folder_row.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/home/conversation_preview.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/features/home/home_sidebar.dart';
import 'package:wecord/features/home/phone_home.dart' show userPanelName;
import 'package:wecord/features/later/saved_messages_screen.dart';
import 'package:wecord/features/note_to_self/note_to_self.dart';
import 'package:wecord/features/qr/qr_link_handler.dart';
import 'package:wecord/features/moments/moments_screen.dart';
import 'package:wecord/features/moments/moments_widgets.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/features/settings/settings_providers.dart';
import 'package:wecord/features/stories/stories_providers.dart';
import 'package:wecord/features/stories/story_composer_screen.dart';
import 'package:wecord/features/stories/story_ring.dart';
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
    final conversations = ref.watch(listedConversationsProvider);
    final friends = ref.watch(friendsProvider).value ?? const <Profile>[];
    final onlineIds =
        ref.watch(onlineUserIdsProvider).value ?? const <String>{};
    final statuses = ref.watch(presenceStatusesProvider).value;
    PresenceStatus? presence(String? userId) =>
        presenceOf(userId, onlineUserIds: onlineIds, statuses: statuses);
    final requestCount =
        ref.watch(incomingFriendRequestsProvider).value?.length ?? 0;
    final currentUserId = ref.watch(authStateProvider).value?.id;
    // Friends' status bubbles (asked again when the friends are).
    final now = DateTime.now();
    final bubbles = {
      for (final status
          in (ref.watch(friendStatusesProvider).value ??
                  const <String, FriendStatus>{})
              .values)
        if (status.isActiveAt(now)) status.userId: status,
    };
    final friendIds = {for (final friend in friends) friend.id};
    final bubbleRoom = bubbles.keys.any(friendIds.contains)
        ? StatusBubble.room
        : 0.0;

    final directChats = [
      for (final conversation
          in conversations.value ?? const <ConversationSummary>[])
        if (conversation.isDirectMessage && !conversation.isNoteToSelf)
          conversation,
    ];
    // The note to self comes first, even before the server made it.
    final chats = withNoteToSelfFirst([
      for (final conversation
          in conversations.value ?? const <ConversationSummary>[])
        if (conversation.isNoteToSelf) conversation,
      ...directChats,
    ]);
    final sortedFriends = [
      ...friends.where((friend) => onlineIds.contains(friend.id)),
      ...friends.where((friend) => !onlineIds.contains(friend.id)),
    ];
    // The folder strip filters the list; under All, the folded folder's
    // chats show as one row.
    // Care mode's simple home: no folders and no row of small shortcuts, just
    // the chats and two big tiles (Friends, Moments).
    final simple = ref.watch(careModeProvider.select((s) => s.simplifies));
    final folders = simple
        ? const <ChatFolder>[]
        : ref.watch(chatFoldersProvider).value ?? const [];
    final selectedFolder = simple
        ? null
        : ref.watch(effectiveChatFolderSelectionProvider);
    final entries = chatListEntries(
      chats: chats,
      folders: folders,
      selected: selectedFolder,
      userId: currentUserId,
    );

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
                    // At large text sizes the title shrinks to its row instead
                    // of being cut off.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        tr('Messages'),
                        maxLines: 1,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          color: c.ink,
                        ),
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
        // The slivers stay the same whether Care mode is on or off, so the
        // list keeps its place; only what they hold changes.
        SliverToBoxAdapter(
          child: simple ? const SizedBox.shrink() : const ChatFolderStrip(),
        ),
        SliverToBoxAdapter(
          child: simple
              ? CareHomeShortcuts(requestCount: requestCount)
              : SizedBox(
                  // 58 tile + the label, which grows with the text size, and room
                  // for the status bubbles when a friend has one.
                  height:
                      86 +
                      bubbleRoom +
                      MediaQuery.textScalerOf(
                        context,
                      ).scale(12 * 1.3).clamp(16, 80),
                  child: ListView.separated(
                    key: const ValueKey('phone-friends-row'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    itemCount: sortedFriends.length + 5,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      // The shortcuts sit lower by the room the bubbles take.
                      Widget lowered(Widget tile) => bubbleRoom == 0
                          ? tile
                          : Padding(
                              padding: EdgeInsets.only(top: bubbleRoom),
                              child: tile,
                            );
                      if (index == 0) {
                        return lowered(
                          _AddFriendTile(requestCount: requestCount),
                        );
                      }
                      if (index == 1) {
                        return lowered(const _SavedTile());
                      }
                      if (index == 2) {
                        return lowered(const _AgendaTile());
                      }
                      if (index == 3) {
                        return lowered(const _MomentsTile());
                      }
                      if (index == 4) {
                        return lowered(const _DailyTile());
                      }
                      final friend = sortedFriends[index - 5];
                      return _FriendTile(
                        friend: friend,
                        presence: presence(friend.id),
                        bubble: bubbles[friend.id],
                        bubbleRoom: bubbleRoom,
                      );
                    },
                  ),
                ),
        ),
        SliverPadding(
          key: const ValueKey('phone-messages-chats'),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          sliver: SliverList.separated(
            itemCount: entries.length,
            separatorBuilder: (context, index) => const SizedBox(height: 2),
            itemBuilder: (context, index) => switch (entries[index]) {
              ConversationEntry(:final conversation) => PhoneConversationRow(
                conversation: conversation,
                currentUserId: currentUserId,
                presence: presence(conversation.directUserId),
              ),
              final FoldedEntry folded => FoldedFolderRow(
                entry: folded,
                currentUserId: currentUserId,
                onOpen: () => ref
                    .read(chatFolderSelectionProvider.notifier)
                    .select(folded.folder.id),
              ),
            },
          ),
        ),
        if (conversations.isLoading && directChats.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (directChats.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Text(
                tr('No conversations yet'),
                style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
              ),
            ),
          )
        else if (entries.isEmpty)
          SliverToBoxAdapter(
            child: ChatFolderEmptyNote(
              selected: selectedFolder,
              folders: folders,
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
          SettingsRow(
            key: const ValueKey('phone-new-scan'),
            icon: Icons.qr_code_scanner_rounded,
            tone: SettingsTone.warning,
            title: tr('Scan'),
            showChevron: false,
            onTap: () => Navigator.of(sheetContext).pop(_NewChoice.scan),
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
    case _NewChoice.scan:
      await openQrScanner(context, ref);
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

enum _NewChoice { message, group, scan }

/// Opens the direct message with [friend], starting one if needed.
Future<void> openDirectMessage(
  BuildContext context,
  WidgetRef ref,
  Profile friend,
) async {
  final existing = ref
      .read(conversationsProvider)
      .value
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
    this.onLongPress,
    this.tooltip,
    this.semanticLabel,
    this.width = 62,
    super.key,
  });

  final String label;
  final Widget leading;
  final VoidCallback onPressed;

  /// A second way in (a friend with a daily: the chat).
  final VoidCallback? onLongPress;
  final String? tooltip;
  final String? semanticLabel;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onPressed,
      onLongPress: onLongPress,
      tooltip: tooltip,
      semanticLabel: semanticLabel ?? tooltip ?? label,
      excludeSemantics: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) => SizedBox(
        width: width,
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

/// "Saved", second in the friends row: the messages kept for later, where
/// desktop has its Saved entry beside Friends and Notifications.
class _SavedTile extends StatelessWidget {
  const _SavedTile();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return _QuickFriendTile(
      key: const ValueKey('phone-home-saved'),
      label: tr('Saved'),
      onPressed: () => openPage(context, SavedMessagesScreen.path),
      leading: Container(
        width: 58,
        height: 58,
        decoration: ShapeDecoration(
          color: c.raised,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Icon(Icons.bookmark_border_rounded, size: 22, color: c.muted),
      ),
    );
  }
}

/// "Agenda", third in the friends row: events, tasks, reminders and scheduled
/// messages from every chat, with a red badge for what is overdue.
class _AgendaTile extends ConsumerWidget {
  const _AgendaTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final overdue = ref.watch(agendaOverdueCountProvider);
    Widget icon = Container(
      width: 58,
      height: 58,
      decoration: ShapeDecoration(
        color: c.raised,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Icon(Icons.event_note_outlined, size: 22, color: c.muted),
    );
    if (overdue > 0) {
      icon = Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(
            right: -5,
            top: -5,
            child: CountBadge(
              key: const ValueKey('phone-agenda-badge'),
              count: overdue,
              size: 18,
              tone: BadgeTone.mention,
              ringColor: c.panel,
            ),
          ),
        ],
      );
    }
    return _QuickFriendTile(
      key: const ValueKey('phone-home-agenda'),
      label: tr('Agenda'),
      tooltip: overdue > 0
          ? tr('Agenda · {count} overdue', {'count': overdue})
          : null,
      onPressed: () => openPage(context, AgendaScreen.path),
      leading: icon,
    );
  }
}

/// "Moments", fourth in the friends row: friends' posts, with the latest
/// poster's avatar on its corner when something is new.
class _MomentsTile extends StatelessWidget {
  const _MomentsTile();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return _QuickFriendTile(
      key: const ValueKey('phone-home-moments'),
      label: tr('Moments'),
      onPressed: () => openPage(context, MomentsScreen.path),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: ShapeDecoration(
              color: c.raised,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Icon(
              Icons.auto_awesome_motion_outlined,
              size: 22,
              color: c.muted,
            ),
          ),
          Positioned(
            right: -6,
            top: -6,
            child: MomentsUnseenAvatar(ringColor: c.panel, size: 24),
          ),
        ],
      ),
    );
  }
}

/// "Daily", fifth in the friends row: your own dailies (a tap watches them,
/// with who viewed) or, when there are none, a way to post one.
class _DailyTile extends ConsumerWidget {
  const _DailyTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final userId = ref.watch(storiesUserIdProvider);
    final mine = userId == null
        ? null
        : ref.watch(storyTrayEntryProvider(userId));
    final profile = ref.watch(currentProfileProvider).value;
    final Widget leading = mine == null
        ? Container(
            width: 58,
            height: 58,
            decoration: ShapeDecoration(
              color: c.raised,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Icon(Icons.add_a_photo_outlined, size: 22, color: c.muted),
          )
        : Stack(
            clipBehavior: Clip.none,
            children: [
              StoryRing(
                entry: mine,
                child: ResolvedAvatar(
                  name: userPanelName(profile),
                  avatarUrl: profile?.avatarUrl,
                  size: 58,
                ),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.panel, width: 2),
                  ),
                  child: Icon(Icons.add_rounded, size: 14, color: c.onAccent),
                ),
              ),
            ],
          );
    return _QuickFriendTile(
      key: const ValueKey('phone-home-daily'),
      label: trIn('Stories', 'Daily'),
      tooltip: mine == null ? tr('Post a daily') : tr('Your daily'),
      semanticLabel: mine == null
          ? tr('Daily. Post a daily.')
          : tr('Daily. Watch your daily. Hold to post another.'),
      onPressed: mine == null
          ? () => unawaited(openStoryComposer(context, ref))
          : () => openStoriesOf(context, ref, mine.authorId),
      onLongPress: mine == null
          ? null
          : () => unawaited(openStoryComposer(context, ref)),
      leading: leading,
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
              tone: BadgeTone.mention,
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
  const _FriendTile({
    required this.friend,
    required this.presence,
    this.bubble,
    this.bubbleRoom = 0,
  });

  final Profile friend;
  final PresenceStatus? presence;

  /// Their status, shown as a bubble over the avatar.
  final FriendStatus? bubble;

  /// The room the row keeps above its tiles for bubbles (0: none shown).
  final double bubbleRoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A friend with a daily up: a ring on the avatar (the accent color while
    // there is something new), and a tap watches it. The chat is one long
    // press away (and in the list below).
    final daily = ref.watch(storyTrayEntryProvider(friend.id));
    final avatar = ResolvedAvatar(
      name: friend.displayLabel,
      avatarUrl: friend.avatarUrl,
      size: 58,
      showPresence: true,
      presence: presence,
    );
    final tile = _QuickFriendTile(
      key: ValueKey('phone-friend-${friend.id}'),
      label: friend.displayLabel,
      tooltip: friend.displayLabel,
      semanticLabel: daily == null
          ? null
          : daily.hasUnseen
          ? tr('{name}: new daily. Opens the daily.', {
              'name': friend.displayLabel,
            })
          : tr('{name}: daily. Opens the daily.', {
              'name': friend.displayLabel,
            }),
      // A tile with a bubble is wider, so the bubble has room to read.
      width: bubble == null ? 62 : 78,
      onPressed: daily == null
          ? () => openDirectMessage(context, ref, friend)
          : () => openStoriesOf(context, ref, friend.id),
      onLongPress: daily == null
          ? null
          : () => openDirectMessage(context, ref, friend),
      leading: daily == null ? avatar : StoryRing(entry: daily, child: avatar),
    );
    if (bubbleRoom == 0) {
      return tile;
    }
    final status = bubble;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: bubbleRoom,
          width: status == null ? 62 : 78,
          child: status == null
              ? null
              : Align(
                  alignment: Alignment.bottomCenter,
                  child: StatusBubble(
                    status: status,
                    name: friend.displayLabel,
                    onPressed: () => replyToFriendStatus(
                      context,
                      ref,
                      friend: friend,
                      status: status,
                    ),
                  ),
                ),
        ),
        tile,
      ],
    );
  }
}

/// Opens the chat with [friend] with "Replying to your status: ..." ready
/// in the composer, when nothing is written there yet.
Future<void> replyToFriendStatus(
  BuildContext context,
  WidgetRef ref, {
  required Profile friend,
  required FriendStatus status,
}) {
  final quote = tr('Replying to your status: "{status}"', {
    'status': status.fullLabel,
  });
  return openChatWithDraft(context, ref, friend: friend, text: '$quote\n');
}

/// Opens the chat with [friend] with [text] ready in the composer (not sent),
/// when nothing is written there yet.
Future<void> openChatWithDraft(
  BuildContext context,
  WidgetRef ref, {
  required Profile friend,
  required String text,
}) async {
  try {
    final existing = ref
        .read(conversationsProvider)
        .value
        ?.where(
          (conversation) =>
              conversation.type == ConversationType.direct &&
              conversation.directUserId == friend.id,
        )
        .firstOrNull;
    final conversationId =
        existing?.id ??
        await ref
            .read(chatsRepositoryProvider)
            .getOrCreateDirectConversation(friend.id);
    final drafts = ref.read(composerDraftsProvider.notifier);
    if (drafts.draftFor(conversationId)?.hasText != true) {
      drafts.set(conversationId, ComposerDraft(text: text));
    }
  } on Object {
    // The chat still opens, just without the text.
  }
  if (context.mounted) {
    await openDirectMessage(context, ref, friend);
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
    final title = conversation.isNoteToSelf
        ? noteToSelfTitle()
        : conversation.title?.trim().isNotEmpty == true
        ? conversation.title!
        : tr('Conversation');
    final unreadCount = conversation.unreadCount;
    final unread = unreadCount > 0 || conversation.isMarkedUnread;
    final emphasized = unread && !conversation.isMuted;
    final group = conversation.type == ConversationType.group;
    final ConversationPreview? preview =
        conversationPreview(conversation, currentUserId: currentUserId) ??
        (conversation.isNoteToSelf
            ? (icon: null, text: noteToSelfHint())
            : group && conversation.memberCount > 0
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
    // A locked chat shows nothing of what was typed in it (G2).
    final draft = conversation.isLocked
        ? null
        : ref.watch(
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
      excludeFromSemantics: true,
      child: WeCordPressable(
        key: ValueKey('home-dm-${conversation.id}'),
        semanticLabel: conversationRowLabel(
          conversation,
          title: title,
          presence: presence,
          preview: preview?.text,
          draft: hasDraft ? draft.text : null,
        ),
        excludeSemantics: true,
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
                if (conversation.isNoteToSelf)
                  const NoteToSelfAvatar()
                else
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
        ref.watch(onlineUserIdsProvider).value ?? const <String>{};
    final statuses = ref.watch(presenceStatusesProvider).value;
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
