// Urgent messages (the red banner, the "Urgent" sheet, the Notifications
// cards, the settings page) and group announcements that ask for a
// confirmation (the count under the announcement, the owner's list), plus the
// repeat choice for scheduled messages, for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/later/schedule_repeat.dart';
import 'package:wecord/features/later/scheduled_messages_repository.dart';
import 'package:wecord/features/later/scheduled_messages_sheet.dart';
import 'package:wecord/features/urgent/urgent_models.dart';
import 'package:wecord/features/urgent/urgent_settings_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/later/later_fakes.dart';
import '../features/urgent/urgent_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

const _announcementState = AnnouncementAckState(
  requiresAck: true,
  total: 30,
  acked: 12,
  iAcked: false,
  canManage: false,
);

/// The group "Weekend Hiking": the user's message as the newest, an urgent one
/// from Bart waiting, and the announcement asking for a confirmation.
FakeUrgentRepository urgentWorld(
  PhoneWorld world, {
  bool waiting = true,
  AnnouncementAckState announcement = AnnouncementAckState.none,
  bool manage = false,
  bool announcementCard = false,
  List<UrgentRecipient> before = const [],
  int quotaUsed = 0,
}) {
  world.chats.messages = [
    phoneMessage(
      'g0',
      bart,
      'Who is bringing the stove on Saturday?',
      minutesAgo: 50,
      conversationId: 'group-1',
    ),
    phoneMessage(
      'g1',
      me,
      'Meet at the north lot at 7:30. Bring layers and water, please.',
      minutesAgo: 20,
      conversationId: 'group-1',
    ),
  ];
  final repository = FakeUrgentRepository(
    waiting: [
      if (waiting)
        pendingUrgent(
          'g0',
          conversationId: 'group-1',
          senderId: bart.id,
          senderName: bart.displayName,
          body: 'The trailhead moved: meet at the south gate at 7:15.',
        ),
    ],
    before: before,
    quotaUsed: quotaUsed,
    announcement: announcement,
    members: manage
        ? [
            AnnouncementAckMember(
              userId: me.id,
              name: me.displayName,
              ackedAt: DateTime.now(),
            ),
            AnnouncementAckMember(
              userId: bart.id,
              name: bart.displayName,
              ackedAt: DateTime.now(),
            ),
            AnnouncementAckMember(userId: grace.id, name: grace.displayName),
            AnnouncementAckMember(userId: linus.id, name: linus.displayName),
          ]
        : const [],
    announcements: [
      if (announcementCard)
        const PendingAnnouncementAck(
          conversationId: 'group-1',
          title: 'Weekend Hiking',
          announcement: 'Bring your own water. The huts are closed this month.',
          askedByName: 'Bart',
        ),
    ],
    muted: const [MutedUrgentSender(senderId: 'user-3', name: 'Grace Hopper')],
  );
  world.extraOverrides = [urgentOverride(repository)];
  return repository;
}

Future<void> _openGroup(
  WidgetTester tester,
  PhoneWorld world, {
  bool waiting = true,
  AnnouncementAckState announcement = AnnouncementAckState.none,
  bool manage = false,
  bool openDetails = false,
}) async {
  urgentWorld(
    world,
    waiting: waiting,
    announcement: announcement,
    manage: manage,
  );
  await world.open(
    tester,
    '${ChatsScreen.path}/group-1',
    extra: ChatThreadRouteExtra(
      title: groupDetail.title,
      type: ConversationType.group,
    ),
  );
  if (openDetails) {
    await tester.tap(find.byKey(const ValueKey('announcement-ack-details')));
    await settle(tester);
  }
}

Future<void> _openSheet(
  WidgetTester tester,
  PhoneWorld world, {
  bool alreadyUrgent = false,
  int quotaUsed = 0,
}) async {
  urgentWorld(
    world,
    waiting: false,
    quotaUsed: quotaUsed,
    before: [
      if (alreadyUrgent) ...[
        UrgentRecipient(
          userId: bart.id,
          name: bart.displayName,
          urgentAt: DateTime.now(),
          ackedAt: DateTime.now(),
        ),
        UrgentRecipient(
          userId: grace.id,
          name: grace.displayName,
          urgentAt: DateTime.now(),
        ),
      ],
    ],
  );
  await world.open(
    tester,
    '${ChatsScreen.path}/group-1',
    extra: ChatThreadRouteExtra(
      title: groupDetail.title,
      type: ConversationType.group,
    ),
  );
  await tester.longPress(find.textContaining('Meet at the north lot'));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('message-action-urgent')));
  await settle(tester);
}

Future<void> _openInbox(WidgetTester tester, PhoneWorld world) async {
  urgentWorld(world, announcementCard: true);
  await world.open(tester, '/notifications');
  final chip = find.byKey(const ValueKey('inbox-filter-confirm'));
  await tester.ensureVisible(chip);
  await settle(tester);
  await tester.tap(chip);
  await settle(tester);
}

Future<void> _openSettings(WidgetTester tester, PhoneWorld world) async {
  urgentWorld(world, waiting: false);
  await pumpStandalone(tester, world, const UrgentSettingsScreen());
}

Future<void> _openScheduled(
  WidgetTester tester,
  PhoneWorld world, {
  bool repeatSheet = false,
}) async {
  world.extraOverrides = [
    scheduledMessagesRepositoryProvider.overrideWithValue(
      FakeScheduledMessagesRepository(FakeScheduledRepeats.list()),
    ),
  ];
  await pumpStandalone(
    tester,
    world,
    const Scaffold(body: ScheduledMessagesSheet(conversationId: 'group-1')),
  );
  if (repeatSheet) {
    await tester.tap(find.byKey(const ValueKey('scheduled-edit-weekly')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('scheduled-edit-repeat')));
    await settle(tester);
  }
}

/// Scheduled messages that repeat, for the list.
abstract final class FakeScheduledRepeats {
  static List<ScheduledMessage> list() => [
    ScheduledMessage(
      id: 'weekly',
      conversationId: 'group-1',
      body: 'Weekly report is due today. Please send yours by noon.',
      sendAt: DateTime.now().add(const Duration(days: 2)).toUtc(),
      repeat: const ScheduleRepeat(
        kind: RepeatKind.weekly,
        day: 1,
        hour: 9,
        minute: 0,
      ),
    ),
    ScheduledMessage(
      id: 'weekdays',
      conversationId: 'group-1',
      body: 'Stand-up in five minutes.',
      sendAt: DateTime.now().add(const Duration(days: 1)).toUtc(),
      repeat: ScheduleRepeat(
        kind: RepeatKind.weekdays,
        hour: 9,
        minute: 30,
        until: DateTime(2027, 3, 31),
      ),
    ),
    ScheduledMessage(
      id: 'once',
      conversationId: 'group-1',
      body: 'Happy birthday!',
      sendAt: DateTime.now().add(const Duration(days: 3)).toUtc(),
    ),
  ];
}

final urgentA11yScreens = <A11yScreen>[
  A11yScreen('urgent-banner', _openGroup),
  A11yScreen(
    'urgent-banner-and-announcement',
    (tester, world) =>
        _openGroup(tester, world, announcement: _announcementState),
  ),
  A11yScreen(
    'announcement-confirmed-count',
    (tester, world) => _openGroup(
      tester,
      world,
      waiting: false,
      announcement: _announcementState,
    ),
  ),
  A11yScreen(
    'announcement-ack-sheet',
    (tester, world) => _openGroup(
      tester,
      world,
      waiting: false,
      manage: true,
      announcement: const AnnouncementAckState(
        requiresAck: true,
        total: 4,
        acked: 2,
        iAcked: true,
        canManage: true,
      ),
      openDetails: true,
    ),
  ),
  A11yScreen('urgent-sheet', _openSheet),
  A11yScreen(
    'urgent-sheet-already-urgent',
    (tester, world) => _openSheet(tester, world, alreadyUrgent: true),
  ),
  A11yScreen(
    'urgent-sheet-quota-used',
    (tester, world) => _openSheet(tester, world, quotaUsed: 5),
  ),
  A11yScreen('notifications-to-confirm', _openInbox),
  A11yScreen('settings-urgent-messages', _openSettings),
  A11yScreen('scheduled-messages-repeating', _openScheduled),
  A11yScreen(
    'scheduled-repeat-sheet',
    (tester, world) => _openScheduled(tester, world, repeatSheet: true),
  ),
  A11yScreen(
    'urgent-banner-desktop',
    _openGroup,
    viewport: desktopViewport,
    desktop: true,
  ),
];
