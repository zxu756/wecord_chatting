import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/announcements/announcement_card.dart';
import 'package:wecord/features/announcements/announcement_models.dart';
import 'package:wecord/features/announcements/announcements_providers.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/events/chat_event_reminder_card.dart';
import 'package:wecord/features/chats/events/chat_events_providers.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/chats/pinned_messages_sheet.dart';
import 'package:wecord/features/chats/read_status/read_reminder_notices.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/join_requests/join_request_inbox_card.dart';
import 'package:wecord/features/circles/join_requests/join_request_models.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart';
import 'package:wecord/features/circles/mod_tools/ban_inbox_card.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_models.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/groups/group_invitations.dart';
import 'package:wecord/features/profile/birthday_card.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/inbox/digest/digest_card.dart';
import 'package:wecord/features/inbox/digest/digest_models.dart';
import 'package:wecord/features/inbox/digest/digest_repository.dart';
import 'package:wecord/features/profile/profile_insights_blocks.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/features/inbox/inbox_repository.dart';
import 'package:wecord/features/later/later_cards.dart';
import 'package:wecord/features/later/reminders_repository.dart';
import 'package:wecord/features/later/saved_messages_screen.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/moments/moment_notification_card.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/features/notes/note_comment_notifications.dart';
import 'package:wecord/features/notes/notes2_models.dart';
import 'package:wecord/features/privacy/security_alerts.dart';
import 'package:wecord/features/urgent/urgent_inbox.dart';
import 'package:wecord/features/urgent/urgent_models.dart';
import 'package:wecord/features/urgent/urgent_repository.dart';
import 'package:wecord/features/workspace/task_notification_card.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

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
      ref.watch(inboxProvider).value?.where((item) => item.isUnread).length ??
      0;
  final requests = ref.watch(incomingFriendRequestsProvider).value?.length ?? 0;
  final reminders = ref.watch(firedRemindersProvider).length;
  final tasks =
      ref
          .watch(taskNotificationsProvider)
          .value
          ?.where((notification) => notification.isUnread)
          .length ??
      0;
  final events =
      ref
          .watch(chatEventRemindersProvider)
          .value
          ?.where((reminder) => reminder.isUnread)
          .length ??
      0;
  final moments = ref.watch(momentNotificationsUnreadProvider);
  final invitations = ref.watch(groupInvitationsProvider).value?.length ?? 0;
  final security = ref.watch(securityAlertsOpenCountProvider);
  final joinAnswers = ref.watch(joinRequestAnswersUnseenProvider);
  final readReminders =
      ref.watch(readReminderNoticesProvider).value?.length ?? 0;
  final official = ref.watch(announcementsUnreadProvider);
  final digests = ref.watch(aiDigestsUnreadProvider);
  final noteComments = ref.watch(noteCommentNotificationsUnreadProvider);
  // Urgent messages and announcements waiting for a confirmation (A7).
  final toConfirm = ref.watch(pendingConfirmationCountProvider);
  return unread +
      requests +
      reminders +
      tasks +
      events +
      moments +
      invitations +
      security +
      joinAnswers +
      readReminders +
      official +
      digests +
      noteComments +
      toConfirm;
});

/// Which notifications the inbox shows.
enum InboxFilter {
  all,
  mentions,
  replies,
  reminders,
  tasks,
  moments,
  friends,
  security,

  /// Answers to requests to join circles, and requests still waiting.
  circles,

  /// Notices from the WeCord team, and its answers to feedback (K6, K7).
  official,

  /// The daily digest of the chats the person follows.
  digest,

  /// Urgent messages and group announcements waiting for a confirmation.
  confirm,
}

/// Mentions of and replies to the current user and reminders that came
/// due, with pending friend requests on top. Chips narrow it to mentions,
/// replies, reminders, requests (and group invitations) or security alerts.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  static const path = '/notifications';

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  var _filter = InboxFilter.all;

  Future<void> _refresh() async {
    ref
      ..invalidate(incomingFriendRequestsProvider)
      ..invalidate(remindersProvider)
      ..invalidate(chatEventRemindersProvider)
      ..invalidate(momentNotificationsProvider)
      ..invalidate(groupInvitationsProvider)
      ..invalidate(securityAlertsProvider)
      ..invalidate(myJoinRequestsProvider)
      ..invalidate(readReminderNoticesProvider)
      ..invalidate(announcementsProvider)
      ..invalidate(aiDigestsProvider)
      ..invalidate(birthdaysTodayProvider)
      ..invalidate(noteCommentNotificationsProvider)
      ..invalidate(pendingUrgentsProvider(null))
      ..invalidate(pendingAnnouncementAcksProvider)
      ..invalidate(inboxProvider);
    await ref.read(inboxProvider.future);
    ref.invalidate(taskNotificationsProvider);
  }

  Future<void> _dismissReadReminder(ReadReminderNotice notice) async {
    try {
      await ref.read(readReminderNoticesRepositoryProvider).markRead([
        notice.id,
      ]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Something went wrong. Try again.'))),
        );
      }
    }
    ref.invalidate(readReminderNoticesProvider);
  }

  Future<void> _markDigestRead(AiDigest digest) async {
    if (!digest.isUnread) {
      return;
    }
    try {
      await ref.read(digestRepositoryProvider).markRead([digest.id]);
    } catch (_) {
      // Still unread: it shows again on the next refresh.
    }
    ref.invalidate(aiDigestsProvider);
  }

  Future<void> _dismissReminder(MessageReminder reminder) async {
    try {
      await ref.read(remindersRepositoryProvider).dismiss(reminder.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Something went wrong. Try again.'))),
        );
      }
    }
    ref.invalidate(remindersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final inbox = ref.watch(inboxProvider);
    final requests =
        ref.watch(incomingFriendRequestsProvider).value ??
        const <IncomingFriendRequest>[];
    final conversations = {
      for (final conversation
          in ref.watch(conversationsProvider).value ??
              const <ConversationSummary>[])
        conversation.id: conversation,
    };
    final circles = {
      for (final circle
          in ref.watch(circleSummariesProvider).value ??
              const <CircleSummary>[])
        circle.id: circle,
    };
    final invitations =
        ref.watch(groupInvitationsProvider).value ?? const <GroupInvitation>[];
    final securityAlerts =
        ref.watch(securityAlertsProvider).value ?? const <LoginAlert>[];
    final openSecurityAlerts = ref.watch(securityAlertsOpenCountProvider);
    final joinRequests =
        ref.watch(myJoinRequestsProvider).value ?? const <MyJoinRequest>[];
    final unseenJoinAnswers = ref.watch(joinRequestAnswersUnseenProvider);
    final circleBans =
        ref.watch(myCircleBansProvider).value ?? const <MyCircleBan>[];
    final announcements =
        ref.watch(announcementsProvider).value ?? const <Announcement>[];
    final unreadOfficial = ref.watch(announcementsUnreadProvider);
    final showOfficial =
        _filter == InboxFilter.all || _filter == InboxFilter.official;
    // Friends whose birthday is today, under the Friends chip.
    final birthdays =
        _filter == InboxFilter.all || _filter == InboxFilter.friends
        ? ref.watch(birthdaysTodayProvider).value ?? const <BirthdayFriend>[]
        : const <BirthdayFriend>[];
    final items = inbox.value ?? const <InboxItem>[];
    final firedReminders = ref.watch(firedRemindersProvider);
    final upcomingReminders = [
      for (final reminder
          in ref.watch(remindersProvider).value ?? const <MessageReminder>[])
        if (!firedReminders.contains(reminder)) reminder,
    ];
    final taskNotifications =
        ref.watch(taskNotificationsProvider).value ??
        const <TaskNotification>[];
    final unreadTasks = taskNotifications
        .where((notification) => notification.isUnread)
        .length;
    // Mentions of me in comments on notes, and replies to my comments.
    final allNoteComments =
        ref.watch(noteCommentNotificationsProvider).value ??
        const <NoteCommentNotification>[];
    final noteCommentCards = [
      for (final notification in allNoteComments)
        if (switch (_filter) {
          InboxFilter.all => true,
          InboxFilter.mentions => !notification.isReply,
          InboxFilter.replies => notification.isReply,
          _ => false,
        })
          notification,
    ];
    final unreadMentions =
        items
            .where((item) => item.isUnread && item.reason != InboxReason.reply)
            .length +
        allNoteComments
            .where(
              (notification) => notification.isUnread && !notification.isReply,
            )
            .length;
    final unreadReplies =
        items
            .where((item) => item.isUnread && item.reason == InboxReason.reply)
            .length +
        allNoteComments
            .where(
              (notification) => notification.isUnread && notification.isReply,
            )
            .length;

    final showRequests =
        _filter == InboxFilter.all || _filter == InboxFilter.friends;
    final showFiredReminders =
        _filter == InboxFilter.all || _filter == InboxFilter.reminders;
    final eventReminders = showFiredReminders
        ? ref.watch(chatEventRemindersProvider).value ??
              const <ChatEventReminder>[]
        : const <ChatEventReminder>[];
    final readReminders =
        ref.watch(readReminderNoticesProvider).value ??
        const <ReadReminderNotice>[];
    final visibleItems = switch (_filter) {
      InboxFilter.all => items,
      InboxFilter.mentions =>
        items.where((item) => item.reason != InboxReason.reply).toList(),
      InboxFilter.replies =>
        items.where((item) => item.reason == InboxReason.reply).toList(),
      InboxFilter.reminders ||
      InboxFilter.tasks ||
      InboxFilter.moments ||
      InboxFilter.friends ||
      InboxFilter.security ||
      InboxFilter.circles ||
      InboxFilter.official ||
      InboxFilter.digest ||
      InboxFilter.confirm => const <InboxItem>[],
    };
    final showTasks =
        _filter == InboxFilter.all || _filter == InboxFilter.tasks;
    final showSecurity =
        _filter == InboxFilter.all || _filter == InboxFilter.security;
    final showJoinRequests =
        _filter == InboxFilter.all || _filter == InboxFilter.circles;
    final digests = _filter == InboxFilter.all || _filter == InboxFilter.digest
        ? ref.watch(aiDigestsProvider).value ?? const <AiDigest>[]
        : const <AiDigest>[];
    final unreadDigests = ref.watch(aiDigestsUnreadProvider);
    // Urgent messages and announcements to confirm: on top, under All and
    // their own chip.
    final showConfirm =
        _filter == InboxFilter.all || _filter == InboxFilter.confirm;
    final pendingUrgents = showConfirm
        ? ref.watch(pendingUrgentsProvider(null)).value ??
              const <PendingUrgent>[]
        : const <PendingUrgent>[];
    final pendingAnnouncements = showConfirm
        ? ref.watch(pendingAnnouncementAcksProvider).value ??
              const <PendingAnnouncementAck>[]
        : const <PendingAnnouncementAck>[];
    final toConfirm = ref.watch(pendingConfirmationCountProvider);
    final momentNotifications =
        _filter == InboxFilter.all || _filter == InboxFilter.moments
        ? ref.watch(momentNotificationsProvider).value ??
              const <MomentNotification>[]
        : const <MomentNotification>[];
    final unreadMoments = ref.watch(momentNotificationsUnreadProvider);
    Widget reminderCard(MessageReminder reminder, {required bool upcoming}) {
      final conversation = conversations[reminder.conversationId];
      return ReminderCard(
        id: reminder.id,
        senderName: reminder.available ? reminder.senderName : '',
        senderAvatarUrl: reminder.available ? reminder.senderAvatarUrl : null,
        preview: laterPreview(
          conversationId: reminder.conversationId,
          body: reminder.body,
          type: reminder.type,
        ),
        available: reminder.available,
        at: reminder.remindAt,
        upcoming: upcoming,
        place: conversationPlaceLabel(conversation, circles),
        onJump: () => openMessage(
          context,
          ref,
          conversationId: reminder.conversationId,
          messageId: reminder.messageId,
          conversation: conversation,
        ),
        onDismiss: () => unawaited(_dismissReminder(reminder)),
      );
    }

    Widget chip(InboxFilter filter, String label, [int? count]) {
      return WeCordChip(
        key: ValueKey('inbox-filter-${filter.name}'),
        label: label,
        count: count,
        onPaper: true,
        selected: _filter == filter,
        onPressed: () => setState(() => _filter = filter),
      );
    }

    final Widget body = inbox.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              tr('Could not load notifications.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dangerText),
            ),
          ),
        ],
      ),
      data: (_) {
        final cards = <Widget>[
          // Notices from the team first: maintenance, changes to the terms.
          if (showOfficial)
            for (final notice in announcements)
              AnnouncementCard(announcement: notice),
          for (final urgent in pendingUrgents)
            UrgentInboxCard(
              urgent: urgent,
              place: conversationPlaceLabel(
                conversations[urgent.conversationId],
                circles,
              ),
              onOpen: () => openMessage(
                context,
                ref,
                conversationId: urgent.conversationId,
                messageId: urgent.messageId,
                conversation: conversations[urgent.conversationId],
              ),
            ),
          for (final pending in pendingAnnouncements)
            AnnouncementAckCard(
              pending: pending,
              onOpen: () {
                final conversation = conversations[pending.conversationId];
                if (conversation != null) {
                  openConversation(context, conversation);
                } else {
                  openPage(
                    context,
                    '${ChatsScreen.path}/${pending.conversationId}',
                  );
                }
              },
            ),
          if (showSecurity)
            for (final alert in securityAlerts) SecurityAlertCard(alert: alert),
          if (showJoinRequests)
            for (final request in joinRequests)
              JoinRequestInboxCard(request: request),
          if (showJoinRequests)
            for (final ban in circleBans) BanInboxCard(ban: ban),
          for (final digest in digests)
            AiDigestCard(
              digest: digest,
              onOpenChat: (conversationId) {
                unawaited(_markDigestRead(digest));
                openMessage(
                  context,
                  ref,
                  conversationId: conversationId,
                  conversation: conversations[conversationId],
                );
              },
              onMarkRead: () => unawaited(_markDigestRead(digest)),
            ),
          if (showRequests && invitations.isNotEmpty)
            Column(
              key: const ValueKey('inbox-group-invitations'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, invitation) in invitations.indexed) ...[
                  if (index > 0) const SizedBox(height: 10),
                  GroupInvitationCard(invitation: invitation),
                ],
              ],
            ),
          if (showRequests && requests.isNotEmpty)
            Column(
              key: const ValueKey('inbox-friend-requests'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, request) in requests.indexed) ...[
                  if (index > 0) const SizedBox(height: 10),
                  _FriendRequestCard(request: request),
                ],
              ],
            ),
          for (final friend in birthdays) BirthdayCard(friend: friend),
          for (final reminder in eventReminders)
            ChatEventReminderCard(
              reminder: reminder,
              onPressed: () {
                unawaited(
                  ref
                      .read(chatEventsRepositoryProvider)
                      .markRemindersRead([reminder.id])
                      .then((_) => ref.invalidate(chatEventRemindersProvider))
                      .catchError((Object _) {}),
                );
                final conversation = conversations[reminder.conversationId];
                if (conversation != null) {
                  openConversation(context, conversation);
                } else {
                  openPage(
                    context,
                    '${ChatsScreen.path}/${reminder.conversationId}',
                  );
                }
              },
            ),
          // Mentions, replies, due reminders and task notices, newest first.
          for (final entry in [
            for (final item in visibleItems) (item.createdAt, item),
            if (showFiredReminders)
              for (final reminder in firedReminders)
                (reminder.remindAt, reminder),
            if (showFiredReminders)
              for (final notice in readReminders) (notice.createdAt, notice),
            if (showTasks)
              for (final notification in taskNotifications)
                (notification.createdAt, notification),
            for (final notification in momentNotifications)
              (notification.createdAt, notification),
            for (final notification in noteCommentCards)
              (notification.createdAt, notification),
          ]..sort((a, b) => b.$1.compareTo(a.$1)))
            switch (entry.$2) {
              final InboxItem item => _InboxCard(
                item: item,
                conversation: conversations[item.conversationId],
                circles: circles,
              ),
              final MessageReminder reminder => reminderCard(
                reminder,
                upcoming: false,
              ),
              final ReadReminderNotice notice => ReadReminderCard(
                notice: notice,
                place: conversationPlaceLabel(
                  conversations[notice.conversationId],
                  circles,
                ),
                onOpen: () {
                  unawaited(_dismissReadReminder(notice));
                  openMessage(
                    context,
                    ref,
                    conversationId: notice.conversationId,
                    messageId: notice.messageId,
                    conversation: conversations[notice.conversationId],
                  );
                },
                onDismiss: () => unawaited(_dismissReadReminder(notice)),
              ),
              final TaskNotification notification => TaskNotificationCard(
                notification: notification,
                conversationName: conversationPlaceLabel(
                  conversations[notification.conversationId],
                  circles,
                ),
              ),
              final MomentNotification notification => MomentNotificationCard(
                notification: notification,
              ),
              final NoteCommentNotification notification =>
                NoteCommentNotificationCard(
                  notification: notification,
                  conversationName: conversationPlaceLabel(
                    conversations[notification.conversationId],
                    circles,
                  ),
                ),
              _ => const SizedBox.shrink(),
            },
          if (_filter == InboxFilter.reminders &&
              upcomingReminders.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: Semantics(
                header: true,
                child: Text(
                  tr('Upcoming'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.subtle,
                  ),
                ),
              ),
            ),
            for (final reminder in upcomingReminders)
              reminderCard(reminder, upcoming: true),
          ],
        ];
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            if (cards.isEmpty)
              _EmptyInbox(filter: _filter)
            else
              for (final (index, card) in cards.indexed) ...[
                if (index > 0) const SizedBox(height: 10),
                card,
              ],
          ],
        );
      },
    );

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(
                  title: tr('Notifications'),
                  actions: [
                    WeCordIconButton(
                      key: const ValueKey('inbox-saved-button'),
                      icon: Icons.bookmark_border_rounded,
                      tooltip: tr('Saved'),
                      variant: WeCordButtonVariant.onPaper,
                      onPressed: () =>
                          openPage(context, SavedMessagesScreen.path),
                    ),
                    const SizedBox(width: 8),
                    WeCordIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: tr('Refresh'),
                      variant: WeCordButtonVariant.onPaper,
                      onPressed: _refresh,
                    ),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      chip(InboxFilter.all, tr('All')),
                      const SizedBox(width: 6),
                      chip(
                        InboxFilter.mentions,
                        tr('Mentions'),
                        unreadMentions,
                      ),
                      const SizedBox(width: 6),
                      chip(InboxFilter.replies, tr('Replies'), unreadReplies),
                      const SizedBox(width: 6),
                      chip(
                        InboxFilter.reminders,
                        tr('Reminders'),
                        firedReminders.length + readReminders.length,
                      ),
                      chip(InboxFilter.tasks, tr('Tasks'), unreadTasks),
                      const SizedBox(width: 6),
                      chip(InboxFilter.moments, tr('Moments'), unreadMoments),
                      const SizedBox(width: 6),
                      chip(
                        InboxFilter.friends,
                        tr('Friends'),
                        requests.length + invitations.length,
                      ),
                      const SizedBox(width: 6),
                      chip(
                        InboxFilter.security,
                        tr('Security'),
                        openSecurityAlerts,
                      ),
                      const SizedBox(width: 6),
                      chip(
                        InboxFilter.circles,
                        tr('Circles'),
                        unseenJoinAnswers,
                      ),
                      const SizedBox(width: 6),
                      chip(
                        InboxFilter.official,
                        tr('Official'),
                        unreadOfficial,
                      ),
                      chip(InboxFilter.digest, tr('Digest'), unreadDigests),
                      const SizedBox(width: 6),
                      chip(InboxFilter.confirm, tr('To confirm'), toConfirm),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(onRefresh: _refresh, child: body),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A white card on the paper page.
class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.onPressed,
    this.highlighted = false,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;

  /// Unread: an accent edge.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WeCordRadii.xl),
    );
    return WeCordPressable(
      onPressed: onPressed,
      shape: shape,
      pressedScale: 0.98,
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.all(14),
          decoration: ShapeDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.025), c.panel)
                : c.panel,
            shape: shape.copyWith(
              side: highlighted
                  ? BorderSide(color: c.accent, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// The small round badge on an inbox avatar: @ for mentions, a reply arrow
/// for replies, a person for friend requests.
class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({required this.color, this.icon, this.label});

  final Color color;
  final IconData? icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: c.panel, width: 2.5),
      ),
      child: icon != null
          ? Icon(icon, size: 11, color: Colors.white)
          : Text(
              label ?? '',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1,
              ),
            ),
    );
  }
}

class _FriendRequestCard extends ConsumerStatefulWidget {
  const _FriendRequestCard({required this.request});

  final IncomingFriendRequest request;

  @override
  ConsumerState<_FriendRequestCard> createState() => _FriendRequestCardState();
}

class _FriendRequestCardState extends ConsumerState<_FriendRequestCard> {
  var _busy = false;

  Future<void> _answer({required bool accept}) async {
    setState(() => _busy = true);
    final repository = ref.read(contactsRepositoryProvider);
    try {
      if (accept) {
        await repository.acceptFriendRequest(widget.request.request.id);
        ref.invalidate(friendsProvider);
      } else {
        await repository.rejectFriendRequest(widget.request.request.id);
      }
      ref.invalidate(incomingFriendRequestsProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Something went wrong. Try again.'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final requester = widget.request.requester;
    return _Card(
      key: ValueKey('inbox-request-${widget.request.request.id}'),
      onPressed: () => openPage(context, ContactsScreen.path),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(
            name: requester.displayLabel,
            avatarUrl: requester.avatarUrl,
            badge: _AvatarBadge(
              color: c.warning,
              icon: Icons.person_add_alt_1_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: requester.displayLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(text: tr('wants to be your friend')),
                    ],
                  ),
                  style: TextStyle(fontSize: 14.5, height: 1.4, color: c.ink),
                ),
                Text(
                  '@${requester.username}',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                MutualCountLine(userId: requester.id),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    // Wide windows keep the two pills at phone size.
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: _requestButtons(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestButtons() {
    return Row(
      children: [
        Expanded(
          child: WeCordButton(
            key: const ValueKey('inbox-request-accept'),
            label: tr('Accept'),
            size: WeCordButtonSize.small,
            expand: true,
            onPressed: _busy ? null : () => _answer(accept: true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: WeCordButton(
            key: const ValueKey('inbox-request-ignore'),
            label: tr('Ignore'),
            size: WeCordButtonSize.small,
            variant: WeCordButtonVariant.secondary,
            expand: true,
            onPressed: _busy ? null : () => _answer(accept: false),
          ),
        ),
      ],
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.item,
    required this.conversation,
    required this.circles,
  });

  final InboxItem item;
  final ConversationSummary? conversation;
  final Map<String, CircleSummary> circles;

  void _open(BuildContext context) {
    final conversation = this.conversation;
    if (conversation != null) {
      openConversation(context, conversation);
    } else {
      openPage(context, '${ChatsScreen.path}/${item.conversationId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final place = _placeLabel();
    final isReply = item.reason == InboxReason.reply;
    final reason = switch (item.reason) {
      InboxReason.mention => tr('Mentioned you'),
      InboxReason.mentionAll => tr('Mentioned everyone'),
      InboxReason.mentionRole => tr('Mentioned your role'),
      InboxReason.mentionHere => tr('Mentioned @here'),
      InboxReason.reply => tr('Replied to you'),
    };
    final time = Text(
      _formatInboxTime(item.createdAt.toLocal(), DateTime.now()),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: c.muted,
      ),
    );

    return _Card(
      key: ValueKey('inbox-item-${item.messageId}'),
      highlighted: item.isUnread,
      onPressed: () => _open(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(
            name: item.senderName,
            avatarUrl: item.senderAvatarUrl,
            badge: isReply
                ? _AvatarBadge(color: c.success, icon: Icons.reply_rounded)
                : _AvatarBadge(color: c.accent, label: '@'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      // The name gives way first; the reason keeps up to
                      // two thirds of the line.
                      child: LayoutBuilder(
                        builder: (context, constraints) => Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.senderName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: c.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth * 2 / 3,
                              ),
                              child: Text(
                                reason,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14.5, color: c.ink),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (item.isUnread)
                      Container(
                        key: const ValueKey('inbox-unread-dot'),
                        margin: const EdgeInsets.only(left: 8),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: c.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    if (isReply) ...[const SizedBox(width: 8), time],
                  ],
                ),
                if (place != null && place.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      place,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ),
                const SizedBox(height: 8),
                if (isReply)
                  Text(
                    inboxPreviewText(item),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: c.well,
                      borderRadius: BorderRadius.circular(WeCordRadii.md),
                    ),
                    child: Text(
                      inboxPreviewText(item),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: c.ink,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      WeCordButton(
                        key: ValueKey('inbox-jump-${item.messageId}'),
                        label: tr('Jump'),
                        size: WeCordButtonSize.small,
                        variant: WeCordButtonVariant.secondary,
                        onPressed: () => _open(context),
                      ),
                      const Spacer(),
                      time,
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "#channel · Circle", the thread or group title, or nothing for a
  /// direct message (the sender says it all).
  String? _placeLabel() => conversationPlaceLabel(conversation, circles);
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
  const _EmptyInbox({required this.filter});

  final InboxFilter filter;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      child: Column(
        children: [
          const SettingsIconTile(
            icon: Icons.notifications_none_rounded,
            size: 56,
          ),
          const SizedBox(height: 14),
          Text(
            filter == InboxFilter.friends
                ? tr('No incoming requests.')
                : tr('Nothing here yet'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: c.ink,
            ),
          ),
          if (filter != InboxFilter.friends) ...[
            const SizedBox(height: 6),
            Text(
              filter == InboxFilter.tasks
                  ? tr(
                      'Tasks assigned to you, and their due dates, show up here.',
                    )
                  : filter == InboxFilter.moments
                  ? tr('Likes and comments on your Moments show up here.')
                  : filter == InboxFilter.security
                  ? tr(
                      'Sign-ins to your account from a new device show up here.',
                    )
                  : filter == InboxFilter.circles
                  ? tr('Answers to your requests to join circles show up here.')
                  : filter == InboxFilter.official
                  ? tr(
                      'Notices from the WeCord team, and its answers to your '
                      'feedback, show up here.',
                    )
                  : filter == InboxFilter.digest
                  ? tr(
                      'Your daily digest shows up here. Set it up in Settings, under AI.',
                    )
                  : filter == InboxFilter.confirm
                  ? tr(
                      'Urgent messages and announcements that ask you to confirm show up here.',
                    )
                  : tr(
                      'Mentions and replies from the last 30 days show up here.',
                    ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
