import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart'
    show chatConversationSummaryProvider;
import 'package:wecord/features/chats/read_status/read_receipts_setting.dart';
import 'package:wecord/features/chats/read_status/read_reminder_notices.dart';
import 'package:wecord/features/chats/read_status/read_status_chat.dart';
import 'package:wecord/features/chats/read_status/read_status_models.dart';
import 'package:wecord/features/chats/read_status/read_status_repository.dart';
import 'package:wecord/features/chats/read_status/read_status_sheet.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer_builtin.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer_registrations.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_builtin.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_registrations.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/wecord_switch.dart';

import 'read_status_fakes.dart';

final _sent = DateTime(2026, 10, 22, 9, 0);

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
  body: 'Please read this',
  createdAt: _sent,
  recalledAt: recalledAt,
  reviewState: reviewState,
);

class _SignedIn implements AuthRepository {
  @override
  AuthUser? get currentUser => const AuthUser(id: 'me');

  @override
  Stream<AuthUser?> authStateChanges() =>
      Stream.value(const AuthUser(id: 'me'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConversationSummary _summary(ConversationType type, {bool note = false}) =>
    ConversationSummary(
      id: 'c1',
      type: type,
      unreadCount: 0,
      title: 'Study group',
      isNoteToSelf: note,
    );

Widget _host(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    retry: noProviderRetry,
    overrides: [
      authRepositoryProvider.overrideWithValue(_SignedIn()),
      ...overrides,
    ],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Scaffold(body: child),
    ),
  );
}

/// A button that opens the sheet for [message].
Widget _opener(ChatMessage message) => Builder(
  builder: (context) => TextButton(
    onPressed: () => showReadStatusSheet(context, message),
    child: const Text('open'),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

FakeReadStatusRepository _list() => FakeReadStatusRepository({
  'm1': [
    member('u1', 'Ada Lovelace', ReadState.read),
    member('u2', 'Grace Hopper', ReadState.read),
    member('u3', 'Alan Turing', ReadState.unread),
    member('u4', 'Linus', ReadState.unknown),
  ],
});

Future<BuildContext> _context(
  WidgetTester tester, {
  List<Override> overrides = const [],
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
      overrides: overrides,
    ),
  );
  return captured;
}

MessageActionContext _actionContext(
  BuildContext context,
  ChatMessage message, {
  bool isCurrentUser = true,
}) => MessageActionContext(
  context: context,
  message: message,
  isCurrentUser: isCurrentUser,
  canCompose: true,
  canPin: false,
  canStartThread: false,
  canModerate: false,
  isSaved: false,
  circleId: null,
  previewUrl: null,
  onReply: (_) {},
  onEdit: (_) {},
  onForward: (_) {},
  onDelete: (_) async {},
  onPreviewImage: (_) async {},
  onTogglePin: (_) async {},
  onRemoveEmbed: (_) async {},
);

BubbleFooterContext _footerContext(
  BuildContext context,
  ChatMessage message, {
  bool isCurrentUser = true,
  bool cards = false,
  int groupReadCount = 3,
}) => BubbleFooterContext(
  context: context,
  message: message,
  isCurrentUser: isCurrentUser,
  cards: cards,
  desktop: false,
  textColor: Colors.black,
  previewUrl: null,
  showReadReceipt: false,
  groupReadCount: groupReadCount,
  onToggleReaction: (_, _) async {},
  onShowReactors: (_, _) {},
);

Override _group(ConversationType type, {bool note = false}) =>
    chatConversationSummaryProvider(
      'c1',
    ).overrideWith((ref) async => _summary(type, note: note));

void main() {
  group('models', () {
    test('a row of get_message_read_status', () {
      final row = MemberReadStatus.fromJson({
        'user_id': 'u1',
        'username': 'ada',
        'display_name': '  Ada  ',
        'avatar_url': null,
        'status': 'unread',
      });
      expect(row.name, 'Ada');
      expect(row.state, ReadState.unread);
      expect(
        MemberReadStatus.fromJson({
          'user_id': 'u2',
          'username': 'grace',
          'display_name': '',
          'status': 'read',
        }).name,
        'grace',
      );
    });

    test('anything unexpected counts as unknown, never as read', () {
      expect(ReadState.fromWire('read'), ReadState.read);
      expect(ReadState.fromWire('unread'), ReadState.unread);
      expect(ReadState.fromWire('unknown'), ReadState.unknown);
      expect(ReadState.fromWire(null), ReadState.unknown);
      expect(ReadState.fromWire('whatever'), ReadState.unknown);
    });

    test('the list splits by state and keeps the order', () {
      final list = ReadList([
        member('1', 'A', ReadState.read),
        member('2', 'B', ReadState.unread),
        member('3', 'C', ReadState.read),
        member('4', 'D', ReadState.unknown),
      ]);
      expect([for (final m in list.read) m.name], ['A', 'C']);
      expect([for (final m in list.unread) m.name], ['B']);
      expect([for (final m in list.unknown) m.name], ['D']);
    });

    test('server errors become problems', () {
      ReadStatusProblem of(String message, [String? code]) =>
          readStatusProblemOf(PostgrestException(message: message, code: code));
      expect(of('read_receipts_off', 'P0001'), ReadStatusProblem.receiptsOff);
      expect(
        of('already_reminded', 'P0001'),
        ReadStatusProblem.alreadyReminded,
      );
      expect(of('nobody_to_remind', 'P0001'), ReadStatusProblem.nobodyToRemind);
      expect(of('rate_limited', '53400'), ReadStatusProblem.rateLimited);
      expect(
        of('Read status is not available', '22023'),
        ReadStatusProblem.unavailable,
      );
      expect(of('Only the sender', '42501'), ReadStatusProblem.unavailable);
      expect(of('Message not found', 'P0002'), ReadStatusProblem.unavailable);
      expect(of('boom', '08006'), ReadStatusProblem.other);
    });
  });

  group('the read list sheet', () {
    testWidgets('wide: Read and Unread side by side, unknown below', (
      tester,
    ) async {
      final repository = _list();
      await tester.pumpWidget(
        _host(_opener(_message()), overrides: [readStatusOverride(repository)]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Message info'), findsOneWidget);
      expect(find.text('Read · 2'), findsOneWidget);
      expect(find.text('Unread · 1'), findsOneWidget);
      expect(find.text('Unknown · 1'), findsOneWidget);
      expect(find.text('They turned off read receipts.'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Alan Turing'), findsOneWidget);
      expect(find.text('Linus'), findsOneWidget);
      // Read people carry the double check; unread and unknown do not.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('read-status-read')),
          matching: find.byIcon(Icons.done_all_rounded),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('read-status-unread')),
          matching: find.byIcon(Icons.done_all_rounded),
        ),
        findsNothing,
      );
      expect(repository.reads, ['m1']);
    });

    testWidgets('on a phone a switch moves between Read and Unread', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _host(_opener(_message()), overrides: [readStatusOverride(_list())]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Read 2'), findsOneWidget);
      expect(find.text('Unread 1'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Alan Turing'), findsNothing);

      await tester.tap(find.text('Unread 1'));
      await tester.pumpAndSettle();
      expect(find.text('Alan Turing'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsNothing);
      // The people we cannot tell about stay on the page.
      expect(find.text('Linus'), findsOneWidget);
    });

    testWidgets('"Remind unread" works once', (tester) async {
      final repository = _list();
      await tester.pumpWidget(
        _host(_opener(_message()), overrides: [readStatusOverride(repository)]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Remind unread'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('read-status-remind')));
      await tester.pumpAndSettle();

      expect(repository.reminds, ['m1']);
      expect(find.text('Reminder sent'), findsWidgets);
      expect(find.text('Remind unread'), findsNothing);
      expect(
        find.text('You can remind once for each message.'),
        findsOneWidget,
      );
      // The button is spent: tapping it again sends nothing.
      await tester.tap(
        find.byKey(const ValueKey('read-status-remind')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(repository.reminds, ['m1']);
    });

    testWidgets('a message that was already reminded about is spent', (
      tester,
    ) async {
      final repository = _list()..reminded.add('m1');
      await tester.pumpWidget(
        _host(_opener(_message()), overrides: [readStatusOverride(repository)]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Reminder sent'), findsOneWidget);
      expect(find.text('Remind unread'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('read-status-remind')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(repository.reminds, isEmpty);
    });

    testWidgets('the server saying "already" spends the button', (
      tester,
    ) async {
      final repository = _list()
        ..remindError = const ReadStatusException(
          ReadStatusProblem.alreadyReminded,
        );
      await tester.pumpWidget(
        _host(_opener(_message()), overrides: [readStatusOverride(repository)]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('read-status-remind')));
      await tester.pumpAndSettle();
      expect(
        find.text('You already reminded about this message.'),
        findsOneWidget,
      );
      expect(find.text('Remind unread'), findsNothing);
    });

    testWidgets('with nobody unread there is nothing to remind', (
      tester,
    ) async {
      final repository = FakeReadStatusRepository({
        'm1': [member('u1', 'Ada Lovelace', ReadState.read)],
      });
      await tester.pumpWidget(
        _host(_opener(_message()), overrides: [readStatusOverride(repository)]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Everyone has read this.'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('read-status-remind')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(repository.reminds, isEmpty);
    });

    testWidgets('a failure to remind says so and can be tried again', (
      tester,
    ) async {
      final repository = _list()..remindError = StateError('offline');
      await tester.pumpWidget(
        _host(_opener(_message()), overrides: [readStatusOverride(repository)]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('read-status-remind')));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not send the reminder. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Remind unread'), findsOneWidget);
    });

    testWidgets('with read receipts off it explains where to turn them on', (
      tester,
    ) async {
      final repository = FakeReadStatusRepository()
        ..listError = const ReadStatusException(ReadStatusProblem.receiptsOff);
      await tester.pumpWidget(
        _host(_opener(_message()), overrides: [readStatusOverride(repository)]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Read receipts are off.'), findsOneWidget);
      expect(find.byKey(const ValueKey('read-status-remind')), findsNothing);
      expect(find.byKey(const ValueKey('read-status-retry')), findsNothing);
    });

    testWidgets('a message without a list says so', (tester) async {
      final repository = FakeReadStatusRepository()
        ..listError = const ReadStatusException(ReadStatusProblem.unavailable);
      await tester.pumpWidget(
        _host(_opener(_message()), overrides: [readStatusOverride(repository)]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.text('There is no read list for this message.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('read-status-retry')), findsNothing);
    });

    testWidgets('a failure to load can be retried', (tester) async {
      final repository = FakeReadStatusRepository({
        'm1': [member('u1', 'Ada Lovelace', ReadState.read)],
      })..listError = const ReadStatusException(ReadStatusProblem.other);
      await tester.pumpWidget(
        _host(_opener(_message()), overrides: [readStatusOverride(repository)]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load who has read this.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('read-status-retry')));
      await tester.pumpAndSettle();
      expect(find.text('Ada Lovelace'), findsOneWidget);
    });

    testWidgets('speaks in Chinese', (tester) async {
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      await tester.pumpWidget(
        _host(_opener(_message()), overrides: [readStatusOverride(_list())]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('消息信息'), findsOneWidget);
      expect(find.text('提醒未读的人'), findsOneWidget);
      expect(find.text('未知 · 1'), findsOneWidget);
    });
  });

  group('the "N read" footer', () {
    testWidgets('is a bubble footer entry after the direct chat\'s "Read"', (
      tester,
    ) async {
      final registry = BubbleFooterRegistry([
        ...builtInBubbleFooterEntries,
        ...bubbleFooterExtensions,
      ]);
      expect(
        registry.ids.indexOf('read-status'),
        greaterThan(registry.ids.indexOf('read-receipt')),
      );
      expect(registry.ids.where((id) => id == 'read-status'), hasLength(1));
    });

    testWidgets('applies only to the user\'s own, live messages', (
      tester,
    ) async {
      final context = await _context(tester);
      final registry = BubbleFooterRegistry([readStatusFooterEntry]);
      bool shows(
        ChatMessage message, {
        bool own = true,
        bool cards = false,
        int count = 3,
      }) => registry
          .below(
            _footerContext(
              context,
              message,
              isCurrentUser: own,
              cards: cards,
              groupReadCount: count,
            ),
          )
          .isNotEmpty;
      expect(shows(_message()), isTrue);
      expect(shows(_message(), count: 0), isFalse);
      expect(shows(_message(), own: false), isFalse);
      expect(shows(_message(recalledAt: _sent)), isFalse);
      expect(shows(_message(type: MessageType.system)), isFalse);
      expect(shows(_message(reviewState: _checking)), isFalse);
      expect(shows(_message(), cards: true), isFalse);
    });

    testWidgets('shows the count and opens the list on a tap', (tester) async {
      final repository = _list();
      await tester.pumpWidget(
        _host(
          GroupReadCount(message: _message(), count: 3),
          overrides: [readStatusOverride(repository)],
        ),
      );
      expect(find.text('3 read'), findsOneWidget);
      expect(find.text('Read'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('group-read-count')));
      await tester.pumpAndSettle();
      expect(find.text('Message info'), findsOneWidget);
      expect(find.text('Alan Turing'), findsOneWidget);
    });

    testWidgets('is plain text for a screen reader, like "Read" was', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(GroupReadCount(message: _message(), count: 2)),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('2 read'));
      expect(node.flagsCollection.isButton, isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });
  });

  group('which conversations have a read list', () {
    Future<bool> isGroup(ConversationType type, {bool note = false}) async {
      final container = ProviderContainer(
        overrides: [_group(type, note: note)],
      );
      addTearDown(container.dispose);
      container.listen(chatConversationSummaryProvider('c1'), (_, _) {});
      await container.read(chatConversationSummaryProvider('c1').future);
      return container.read(isGroupConversationProvider('c1'));
    }

    test('only a group', () async {
      expect(await isGroup(ConversationType.group), isTrue);
      expect(await isGroup(ConversationType.direct), isFalse);
      expect(await isGroup(ConversationType.channel), isFalse);
      expect(await isGroup(ConversationType.thread), isFalse);
      expect(await isGroup(ConversationType.direct, note: true), isFalse);
    });

    test('not before the conversation is known', () {
      final container = ProviderContainer(
        overrides: [
          chatConversationSummaryProvider(
            'c1',
          ).overrideWith((ref) => Future<ConversationSummary?>.value()),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(isGroupConversationProvider('c1')), isFalse);
    });
  });

  group('"Message info" in the message menu', () {
    testWidgets('sits between Edit history and Create task', (tester) async {
      final ids = MessageActionRegistry([
        ...builtInMessageActions,
        ...messageActionExtensions,
      ]).ids;
      final at = ids.indexOf('message-info');
      expect(at, greaterThan(ids.indexOf('edit-history')));
      expect(at, lessThan(ids.indexOf('create-task')));
    });

    Future<List<String>> labels(
      WidgetTester tester,
      ChatMessage message, {
      ConversationType type = ConversationType.group,
      bool own = true,
      bool note = false,
      bool pending = false,
    }) async {
      final context = await _context(
        tester,
        overrides: [_group(type, note: note)],
      );
      final container = ProviderScope.containerOf(context);
      // The chat page keeps the summary alive while it is open.
      container.listen(chatConversationSummaryProvider('c1'), (_, _) {});
      await container.read(chatConversationSummaryProvider('c1').future);
      final actions = messageInfoAction.build(
        _actionContext(context, message, isCurrentUser: own),
      );
      return [for (final action in actions) action.label];
    }

    testWidgets('is offered for the user\'s own message in a group', (
      tester,
    ) async {
      expect(await labels(tester, _message()), ['Message info']);
    });

    testWidgets('not for someone else\'s message', (tester) async {
      expect(
        await labels(tester, _message(sender: 'ada'), own: false),
        isEmpty,
      );
    });

    testWidgets('not in a direct chat, a channel or the note to self', (
      tester,
    ) async {
      expect(
        await labels(tester, _message(), type: ConversationType.direct),
        isEmpty,
      );
      expect(
        await labels(tester, _message(), type: ConversationType.channel),
        isEmpty,
      );
      expect(
        await labels(
          tester,
          _message(),
          type: ConversationType.direct,
          note: true,
        ),
        isEmpty,
      );
    });

    testWidgets('not for a deleted, system or held message', (tester) async {
      expect(await labels(tester, _message(recalledAt: _sent)), isEmpty);
      expect(await labels(tester, _message(type: MessageType.system)), isEmpty);
      expect(await labels(tester, _message(reviewState: _checking)), isEmpty);
    });

    testWidgets('not while the message is still being sent', (tester) async {
      expect(await labels(tester, _message(id: 'outbox:abc')), isEmpty);
    });
  });

  group('the read receipts switch', () {
    testWidgets('shows the saved choice and saves a change', (tester) async {
      final repository = FakeReadReceiptsRepository();
      await tester.pumpWidget(
        _host(
          const ReadReceiptsRow(),
          overrides: [readReceiptsOverride(repository)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Send read receipts'), findsOneWidget);
      expect(
        tester.widget<WeCordSwitch>(find.byType(WeCordSwitch)).value,
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('read-receipts-row')));
      await tester.pumpAndSettle();
      expect(repository.saved, [false]);
      expect(
        tester.widget<WeCordSwitch>(find.byType(WeCordSwitch)).value,
        isFalse,
      );
    });

    testWidgets('shows "off" for someone who turned it off', (tester) async {
      await tester.pumpWidget(
        _host(
          const ReadReceiptsRow(),
          overrides: [
            readReceiptsOverride(FakeReadReceiptsRepository(enabled: false)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<WeCordSwitch>(find.byType(WeCordSwitch)).value,
        isFalse,
      );
    });

    testWidgets('a failed save puts the switch back and says so', (
      tester,
    ) async {
      final repository = FakeReadReceiptsRepository()
        ..saveError = StateError('offline');
      await tester.pumpWidget(
        _host(
          const ReadReceiptsRow(),
          overrides: [readReceiptsOverride(repository)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('read-receipts-row')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<WeCordSwitch>(find.byType(WeCordSwitch)).value,
        isTrue,
      );
      expect(
        find.text('Could not save privacy settings. Try again.'),
        findsOneWidget,
      );
    });
  });

  group('the Reminder card', () {
    final notice = ReadReminderNotice.fromJson({
      'notice_id': 'n1',
      'message_id': 'm1',
      'conversation_id': 'c1',
      'sender_display_name': 'Ada',
      'sender_avatar_url': null,
      'body': 'Bring your passport',
      'type': 'text',
      'created_at': DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toUtc()
          .toIso8601String(),
    });

    testWidgets('names who asked and what, and jumps or dismisses', (
      tester,
    ) async {
      var opened = 0;
      var dismissed = 0;
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            child: ReadReminderCard(
              notice: notice,
              place: 'Study group',
              onOpen: () => opened += 1,
              onDismiss: () => dismissed += 1,
            ),
          ),
        ),
      );
      expect(find.textContaining('asked you to read this'), findsOneWidget);
      expect(find.text('Study group'), findsOneWidget);
      expect(find.text('Bring your passport'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('read-reminder-open-n1')));
      await tester.tap(find.byKey(const ValueKey('read-reminder-dismiss-n1')));
      expect(opened, 1);
      expect(dismissed, 1);
    });

    test(
      'the provider lists what the repository has, none on failure',
      () async {
        final repository = FakeReadReminderNoticesRepository([notice]);
        final container = ProviderContainer(
          overrides: [
            readReminderNoticesRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);
        expect(
          (await container.read(readReminderNoticesProvider.future)).single.id,
          'n1',
        );
        await repository.markRead(['n1']);
        container.invalidate(readReminderNoticesProvider);
        expect(
          await container.read(readReminderNoticesProvider.future),
          isEmpty,
        );
      },
    );
  });
}

const _checking = MessageReviewState.checking;
