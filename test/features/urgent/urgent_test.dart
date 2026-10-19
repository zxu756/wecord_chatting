import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_builtin.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_registrations.dart';
import 'package:wecord/features/urgent/announcement_ack.dart';
import 'package:wecord/features/urgent/urgent_banner.dart';
import 'package:wecord/features/urgent/urgent_message_action.dart';
import 'package:wecord/features/urgent/urgent_models.dart';
import 'package:wecord/features/urgent/urgent_repository.dart';
import 'package:wecord/features/urgent/urgent_settings_screen.dart';
import 'package:wecord/features/urgent/urgent_sheet.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'urgent_fakes.dart';

final _stamp = DateTime(2026, 10, 24, 8);

GroupMember _member(String id, String name, {String role = 'member'}) =>
    GroupMember(
      profile: Profile(
        id: id,
        username: id,
        displayName: name,
        bio: '',
        createdAt: _stamp,
        updatedAt: _stamp,
      ),
      role: role,
    );

final _members = [
  _member('me', 'Me', role: 'owner'),
  _member('bo', 'Bo'),
  _member('cy', 'Cy'),
  _member('di', 'Di'),
];

ChatMessage _message({
  String id = 'm1',
  String sender = 'me',
  MessageType type = MessageType.text,
  DateTime? recalledAt,
  MessageReviewState? reviewState,
}) => ChatMessage(
  id: id,
  conversationId: 'c1',
  senderId: sender,
  type: type,
  body: 'The meeting moved to 3 pm',
  createdAt: _stamp,
  recalledAt: recalledAt,
  reviewState: reviewState,
);

Widget _host(
  Widget child,
  FakeUrgentRepository repository, {
  List<Override> overrides = const [],
  bool dark = false,
  bool scroll = true,
}) {
  return ProviderScope(
    retry: noProviderRetry,
    overrides: [
      urgentOverride(repository),
      conversationMembersProvider.overrideWith((ref, id) async => _members),
      ...overrides,
    ],
    child: MaterialApp(
      theme: dark ? WeCordTheme.dark() : WeCordTheme.light(),
      home: scroll
          ? Scaffold(body: SingleChildScrollView(child: child))
          : child,
    ),
  );
}

MessageActionContext _actionContext(
  BuildContext context,
  ChatMessage message, {
  bool isCurrentUser = true,
  String? circleId,
}) => MessageActionContext(
  context: context,
  message: message,
  isCurrentUser: isCurrentUser,
  canCompose: true,
  canPin: false,
  canStartThread: false,
  canModerate: false,
  isSaved: false,
  circleId: circleId,
  previewUrl: null,
  onReply: (_) {},
  onEdit: (_) {},
  onForward: (_) {},
  onDelete: (_) async {},
  onPreviewImage: (_) async {},
  onTogglePin: (_) async {},
  onRemoveEmbed: (_) async {},
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the banner', () {
    Widget banner(FakeUrgentRepository repository, {List<String>? jumps}) =>
        _host(
          UrgentBanner(conversationId: 'c1', onJump: (id) => jumps?.add(id)),
          repository,
        );

    testWidgets('names who made a message urgent, and shows it', (
      tester,
    ) async {
      final repository = FakeUrgentRepository(waiting: [pendingUrgent('m1')]);
      await tester.pumpWidget(banner(repository));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('urgent-banner')), findsOneWidget);
      expect(find.text('Ada marked a message urgent'), findsOneWidget);
      expect(find.text('The meeting moved to 3 pm'), findsOneWidget);
    });

    testWidgets('is not there when nothing is waiting', (tester) async {
      await tester.pumpWidget(banner(FakeUrgentRepository()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('urgent-banner')), findsNothing);
    });

    testWidgets('only shows this conversation\'s', (tester) async {
      final repository = FakeUrgentRepository(
        waiting: [pendingUrgent('m9', conversationId: 'other')],
      );
      await tester.pumpWidget(banner(repository));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('urgent-banner')), findsNothing);
    });

    testWidgets('"Got it" confirms and the banner goes', (tester) async {
      final repository = FakeUrgentRepository(waiting: [pendingUrgent('m1')]);
      await tester.pumpWidget(banner(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('urgent-got-it')));
      await tester.pumpAndSettle();
      expect(repository.acknowledged, ['m1']);
      expect(find.byKey(const ValueKey('urgent-banner')), findsNothing);
    });

    testWidgets('says how many more wait, and shows the next after "Got it"', (
      tester,
    ) async {
      final repository = FakeUrgentRepository(
        waiting: [
          pendingUrgent('m2', body: 'Second'),
          pendingUrgent('m1', body: 'First'),
        ],
      );
      await tester.pumpWidget(banner(repository));
      await tester.pumpAndSettle();
      expect(find.text('Ada marked a message urgent · 1 more'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('urgent-got-it')));
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Ada marked a message urgent'), findsOneWidget);
    });

    testWidgets('"Jump" goes to the message', (tester) async {
      final jumps = <String>[];
      final repository = FakeUrgentRepository(waiting: [pendingUrgent('m1')]);
      await tester.pumpWidget(banner(repository, jumps: jumps));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('urgent-jump')));
      expect(jumps, ['m1']);
      expect(repository.acknowledged, isEmpty);
    });

    testWidgets('can turn off urgent messages from the sender', (tester) async {
      final repository = FakeUrgentRepository(waiting: [pendingUrgent('m1')]);
      await tester.pumpWidget(banner(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('urgent-turn-off')));
      await tester.pumpAndSettle();
      expect(repository.allowedChanges.single, (
        senderId: 'ada',
        allowed: false,
      ));
      expect(find.byKey(const ValueKey('urgent-banner')), findsNothing);
      expect(find.textContaining('Urgent messages from Ada are off'), findsOne);
    });

    testWidgets('a message that arrives while the chat is open shows up', (
      tester,
    ) async {
      final repository = FakeUrgentRepository();
      await tester.pumpWidget(banner(repository));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('urgent-banner')), findsNothing);
      repository.arrive(pendingUrgent('m7'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('urgent-banner')), findsOneWidget);
    });

    testWidgets('reads in Chinese', (tester) async {
      AppStrings.isChinese = true;
      final repository = FakeUrgentRepository(waiting: [pendingUrgent('m1')]);
      await tester.pumpWidget(banner(repository));
      await tester.pumpAndSettle();
      expect(find.text('Ada 加急了一条消息'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
      expect(find.text('不再接收 Ada 的加急'), findsOneWidget);
    });

    testWidgets('is announced as a live region and keeps its buttons in dark', (
      tester,
    ) async {
      final repository = FakeUrgentRepository(waiting: [pendingUrgent('m1')]);
      await tester.pumpWidget(
        _host(
          UrgentBanner(conversationId: 'c1', onJump: (_) {}),
          repository,
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byKey(const ValueKey('urgent-banner-title'))),
        matchesSemantics(
          label: 'Ada marked a message urgent',
          isLiveRegion: true,
        ),
      );
      handle.dispose();
    });
  });

  group('the menu entry', () {
    Future<List<String>> labels(
      WidgetTester tester,
      ChatMessage message, {
      bool own = true,
      String? circleId,
    }) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
          FakeUrgentRepository(),
        ),
      );
      return [
        for (final action in urgentMessageAction.build(
          _actionContext(
            captured,
            message,
            isCurrentUser: own,
            circleId: circleId,
          ),
        ))
          action.label,
      ];
    }

    testWidgets('is on your own messages', (tester) async {
      expect(await labels(tester, _message()), ['Urgent']);
    });

    testWidgets('not on someone else\'s, deleted, held or system ones', (
      tester,
    ) async {
      expect(
        await labels(tester, _message(sender: 'ada'), own: false),
        isEmpty,
      );
      expect(await labels(tester, _message(recalledAt: _stamp)), isEmpty);
      expect(await labels(tester, _message(type: MessageType.system)), isEmpty);
      expect(
        await labels(
          tester,
          _message(reviewState: MessageReviewState.checking),
        ),
        isEmpty,
      );
    });

    testWidgets('not in a circle channel', (tester) async {
      expect(await labels(tester, _message(), circleId: 'circle-1'), isEmpty);
    });

    test('is registered between Forward and Translate', () {
      final registry = MessageActionRegistry([
        ...builtInMessageActions,
        ...messageActionExtensions,
      ]);
      final ids = registry.ids;
      expect(ids, contains('urgent'));
      expect(ids.indexOf('urgent'), greaterThan(ids.indexOf('forward')));
      expect(ids.indexOf('urgent'), lessThan(ids.indexOf('translate')));
    });
  });

  group('the sheet', () {
    Future<void> open(
      WidgetTester tester,
      FakeUrgentRepository repository, {
      ChatMessage? message,
    }) async {
      _phone(tester);
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showUrgentSheet(context, message ?? _message()),
              child: const Text('open'),
            ),
          ),
          repository,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists the others, not you, and how many are left', (
      tester,
    ) async {
      await open(tester, FakeUrgentRepository(quotaUsed: 2));
      expect(find.byKey(const ValueKey('urgent-person-bo')), findsOneWidget);
      expect(find.byKey(const ValueKey('urgent-person-cy')), findsOneWidget);
      expect(find.byKey(const ValueKey('urgent-person-me')), findsNothing);
      expect(find.text('3 of 5 left in 24 hours'), findsOneWidget);
      // Nothing to send until somebody is picked.
      final send = find.byKey(const ValueKey('urgent-send'));
      expect(tester.widget<WeCordButton>(send).onPressed, isNull);
    });

    testWidgets('makes the message urgent for the people picked', (
      tester,
    ) async {
      final repository = FakeUrgentRepository();
      await open(tester, repository);
      await tester.tap(find.byKey(const ValueKey('urgent-person-bo')));
      await tester.tap(find.byKey(const ValueKey('urgent-person-di')));
      await tester.pump();
      expect(find.text('Make urgent for 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('urgent-send')));
      await tester.pumpAndSettle();
      expect(repository.sent.single.messageId, 'm1');
      expect(repository.sent.single.targets.toSet(), {'bo', 'di'});
      expect(find.text('Made urgent for 2 people'), findsOneWidget);
      expect(find.byKey(const ValueKey('urgent-send')), findsNothing);
    });

    testWidgets('shows who it was made urgent for before, and who confirmed', (
      tester,
    ) async {
      final repository = FakeUrgentRepository(
        before: [
          UrgentRecipient(
            userId: 'bo',
            name: 'Bo',
            urgentAt: _stamp,
            ackedAt: _stamp,
          ),
          UrgentRecipient(userId: 'cy', name: 'Cy', urgentAt: _stamp),
        ],
      );
      await open(tester, repository);
      expect(find.text('Already urgent'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      // They can not be picked again.
      expect(find.byKey(const ValueKey('urgent-person-bo')), findsNothing);
      expect(find.byKey(const ValueKey('urgent-person-di')), findsOneWidget);
    });

    testWidgets('says why when the server refuses', (tester) async {
      final repository = FakeUrgentRepository()
        ..sendError = const UrgentException(UrgentProblem.rateLimited);
      await open(tester, repository);
      await tester.tap(find.byKey(const ValueKey('urgent-person-bo')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('urgent-send')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'You can make 5 messages urgent in 24 hours. Try again later.',
        ),
        findsOneWidget,
      );
      // Still open: the person can change their mind.
      expect(find.byKey(const ValueKey('urgent-send')), findsOneWidget);
    });

    testWidgets('can not send once the 24 hour quota is used up', (
      tester,
    ) async {
      await open(tester, FakeUrgentRepository(quotaUsed: 5));
      await tester.tap(find.byKey(const ValueKey('urgent-person-bo')));
      await tester.pump();
      expect(
        find.text('You used all 5 urgent messages of the last 24 hours.'),
        findsOneWidget,
      );
      final send = find.byKey(const ValueKey('urgent-send'));
      expect(tester.widget<WeCordButton>(send).onPressed, isNull);
    });
  });

  group('announcements that ask for a confirmation', () {
    const asked = AnnouncementAckState(
      requiresAck: true,
      total: 30,
      acked: 12,
      iAcked: false,
      canManage: false,
    );

    Widget bar(FakeUrgentRepository repository) =>
        _host(const AnnouncementAckBar(conversationId: 'c1'), repository);

    testWidgets('shows nothing when no confirmation is asked', (tester) async {
      await tester.pumpWidget(bar(FakeUrgentRepository()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('announcement-ack-bar')), findsNothing);
    });

    testWidgets('shows the count and a Confirm button', (tester) async {
      final repository = FakeUrgentRepository(announcement: asked);
      await tester.pumpWidget(bar(repository));
      await tester.pumpAndSettle();
      expect(find.text('Confirmed 12/30'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('announcement-ack-details')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('announcement-ack-confirm')));
      await tester.pumpAndSettle();
      expect(repository.announcementAcks, ['c1']);
      expect(find.text('Confirmed 13/30'), findsOneWidget);
      expect(find.text('You confirmed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('announcement-ack-confirm')),
        findsNothing,
      );
    });

    testWidgets('the owner gets a way to see who confirmed', (tester) async {
      final repository = FakeUrgentRepository(
        announcement: const AnnouncementAckState(
          requiresAck: true,
          total: 3,
          acked: 1,
          iAcked: true,
          canManage: true,
        ),
        members: [
          AnnouncementAckMember(userId: 'me', name: 'Me', ackedAt: _stamp),
          const AnnouncementAckMember(userId: 'bo', name: 'Bo'),
          const AnnouncementAckMember(userId: 'cy', name: 'Cy'),
        ],
      );
      _phone(tester);
      await tester.pumpWidget(bar(repository));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('announcement-ack-confirm')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('announcement-ack-details')));
      await tester.pumpAndSettle();
      // Waiting first; Confirmed on the other tab.
      expect(find.byKey(const ValueKey('ack-member-bo')), findsOneWidget);
      expect(find.byKey(const ValueKey('ack-member-cy')), findsOneWidget);
      expect(find.byKey(const ValueKey('ack-member-me')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('ack-tab-confirmed')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ack-member-me')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('announcement-ack-remind')));
      await tester.pumpAndSettle();
      expect(repository.reminded, ['c1']);
      expect(find.text('Reminded 2 people'), findsOneWidget);
      // Once: the button is spent.
      expect(find.text('Reminder sent'), findsOneWidget);
    });

    testWidgets('the reminder waits for its limit', (tester) async {
      final repository = FakeUrgentRepository(
        announcement: AnnouncementAckState(
          requiresAck: true,
          total: 3,
          acked: 1,
          iAcked: true,
          canManage: true,
          nextReminderAt: DateTime.now().add(const Duration(hours: 5)),
        ),
        members: [const AnnouncementAckMember(userId: 'bo', name: 'Bo')],
      );
      _phone(tester);
      await tester.pumpWidget(bar(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('announcement-ack-details')));
      await tester.pumpAndSettle();
      expect(find.textContaining('You can remind again'), findsOneWidget);
      final remind = find.byKey(const ValueKey('announcement-ack-remind'));
      expect(tester.widget<WeCordButton>(remind).onPressed, isNull);
    });

    testWidgets('the switch in the group details', (tester) async {
      var value = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => AnnouncementAckToggle(
                value: value,
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Ask members to confirm'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('announcement-requires-ack')));
      await tester.pumpAndSettle();
      expect(value, isTrue);
    });
  });

  group('Settings -> Notifications -> Urgent messages', () {
    testWidgets('lists who was turned off, and allows them again', (
      tester,
    ) async {
      final repository = FakeUrgentRepository(
        muted: const [MutedUrgentSender(senderId: 'ada', name: 'Ada')],
      );
      await tester.pumpWidget(
        _host(const UrgentSettingsScreen(), repository, scroll: false),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('urgent-muted-ada')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('urgent-allow-ada')));
      await tester.pumpAndSettle();
      expect(repository.allowedChanges.single, (
        senderId: 'ada',
        allowed: true,
      ));
      expect(
        find.byKey(const ValueKey('urgent-settings-empty')),
        findsOneWidget,
      );
    });

    testWidgets('the row counts the people turned off', (tester) async {
      final repository = FakeUrgentRepository(
        muted: const [MutedUrgentSender(senderId: 'ada', name: 'Ada')],
      );
      await tester.pumpWidget(_host(const UrgentSettingsRow(), repository));
      await tester.pumpAndSettle();
      expect(find.text('1 turned off'), findsOneWidget);
    });

    testWidgets('reads in Chinese', (tester) async {
      AppStrings.isChinese = true;
      await tester.pumpWidget(
        _host(
          const UrgentSettingsScreen(),
          FakeUrgentRepository(),
          scroll: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('加急消息'), findsWidgets);
      expect(find.text('你没有关闭任何人。'), findsOneWidget);
    });
  });

  test('the badge counts urgent messages and announcements', () async {
    final repository = FakeUrgentRepository(
      waiting: [pendingUrgent('m1'), pendingUrgent('m2')],
      announcements: const [
        PendingAnnouncementAck(
          conversationId: 'c1',
          title: 'Team',
          announcement: 'Be on time',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [urgentOverride(repository)],
    );
    addTearDown(container.dispose);
    container.listen(pendingConfirmationCountProvider, (_, _) {});
    await container.read(pendingUrgentsProvider(null).future);
    await container.read(pendingAnnouncementAcksProvider.future);
    expect(container.read(pendingConfirmationCountProvider), 3);
  });

  test('refused calls are told apart', () {
    // The server's words for each problem (urgentProblemOf).
    expect(
      urgentProblemText(const UrgentException(UrgentProblem.nobodyToUrgent)),
      contains('Nobody to notify'),
    );
    expect(
      urgentProblemText(const UrgentException(UrgentProblem.unavailable)),
      'This message can not be made urgent.',
    );
  });
}
