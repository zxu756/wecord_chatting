import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/later/reminders_repository.dart';
import 'package:wecord/features/later/when_sheet.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/message.dart';

import '../chats/chat_thread_screen_test.dart' as thread_test;
import '../file_preview/file_preview_fakes.dart';
import '../../mobile/phone_test_support.dart';
import 'later_fakes.dart';

MessageReminder _reminder(
  String id, {
  required DateTime at,
  String body = 'Bring the tripod',
  bool available = true,
  String conversationId = 'dm-1',
  String? messageId = 'm1',
}) {
  return MessageReminder(
    id: id,
    conversationId: conversationId,
    messageId: messageId,
    remindAt: at.toUtc(),
    senderId: available ? 'user-2' : null,
    senderName: available ? 'Bart the Bold' : '',
    body: available ? body : '',
    available: available,
  );
}

void main() {
  group('model', () {
    test('parses a server row', () {
      final reminder = MessageReminder.fromJson({
        'reminder_id': 'r1',
        'message_id': 'm1',
        'conversation_id': 'c1',
        'remind_at': '2026-10-17T20:00:00+00:00',
        'fired': true,
        'sender_id': 'u2',
        'sender_display_name': 'Bob',
        'sender_avatar_url': 'avatars/u2/a.png',
        'webhook_name': null,
        'body': 'Bring the tripod',
        'type': 'text',
        'message_created_at': '2026-10-17T10:00:00+00:00',
        'available': true,
      });
      expect(reminder.remindAt, DateTime.utc(2026, 10, 17, 20));
      expect(reminder.senderName, 'Bob');
      expect(reminder.body, 'Bring the tripod');
      expect(reminder.isFired(DateTime.utc(2026, 10, 17, 20, 0, 1)), isTrue);
      expect(reminder.isFired(DateTime.utc(2026, 10, 17, 19, 59)), isFalse);
    });

    test('a message that is gone has no text', () {
      final reminder = MessageReminder.fromJson({
        'reminder_id': 'r1',
        'message_id': null,
        'conversation_id': 'c1',
        'remind_at': '2026-10-17T20:00:00+00:00',
        'fired': true,
        'sender_id': null,
        'sender_display_name': null,
        'sender_avatar_url': null,
        'webhook_name': null,
        'body': null,
        'type': null,
        'message_created_at': null,
        'available': false,
      });
      expect(reminder.available, isFalse);
      expect(reminder.messageId, isNull);
      expect(reminder.body, isEmpty);
    });

    test('webhook messages show the webhook', () {
      final reminder = MessageReminder.fromJson({
        'reminder_id': 'r1',
        'message_id': 'm1',
        'conversation_id': 'c1',
        'remind_at': '2026-10-17T20:00:00+00:00',
        'fired': false,
        'sender_id': 'u2',
        'sender_display_name': 'Bob',
        'sender_avatar_url': 'avatars/u2/a.png',
        'webhook_name': 'Deploys',
        'body': 'Shipped',
        'type': 'text',
        'message_created_at': '2026-10-17T10:00:00+00:00',
        'available': true,
      });
      expect(reminder.senderName, 'Deploys');
      expect(reminder.senderAvatarUrl, isNull);
    });

    test('notification payloads round trip', () {
      final payload = reminderNotificationPayload('c1', 'm1');
      expect(payload, 'message:c1:m1');
      expect(parseReminderNotificationPayload(payload), (
        conversationId: 'c1',
        messageId: 'm1',
      ));
      expect(reminderNotificationPayload('c1', null), 'c1');
      expect(parseReminderNotificationPayload('c1'), isNull);
      expect(parseReminderNotificationPayload('circle-event:a:b'), isNull);
    });
  });

  group('providers', () {
    test(
      'fired reminders are those whose time has come, newest first',
      () async {
        final now = DateTime.utc(2026, 10, 17, 12);
        final container = ProviderContainer(
          overrides: [
            remindersRepositoryProvider.overrideWithValue(
              FakeRemindersRepository([
                _reminder('old', at: now.subtract(const Duration(hours: 3))),
                _reminder('new', at: now.subtract(const Duration(minutes: 5))),
                _reminder('later', at: now.add(const Duration(hours: 2))),
              ]),
            ),
          ],
        );
        addTearDown(container.dispose);
        await withClock(Clock.fixed(now), () async {
          container.listen(firedRemindersProvider, (_, _) {});
          await container.read(remindersProvider.future);
          final fired = container.read(firedRemindersProvider);
          expect(fired.map((reminder) => reminder.id), ['new', 'old']);
        });
      },
    );
  });

  group('remind me', () {
    Widget app(
      thread_test.FakeChatsRepository chats,
      FakeRemindersRepository reminders,
    ) {
      return ProviderScope(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(chats),
          remindersRepositoryProvider.overrideWithValue(reminders),
          onlineUserIdsProvider.overrideWith(
            (ref) => const Stream<Set<String>>.empty(),
          ),
          settingsRepositoryProvider.overrideWithValue(
            thread_test.FakeSettingsRepository(),
          ),
          ...filePreviewOverrides(),
          authRepositoryProvider.overrideWithValue(
            thread_test.FakeAuthRepository()
              ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
          ),
        ],
        child: const MaterialApp(
          home: ChatThreadScreen(
            conversationId: 'conversation-1',
            title: 'Ada Lovelace',
          ),
        ),
      );
    }

    thread_test.FakeChatsRepository chatWith(String body) {
      return thread_test.FakeChatsRepository()
        ..messages = [
          ChatMessage(
            id: 'message-1',
            conversationId: 'conversation-1',
            senderId: 'user-2',
            type: MessageType.text,
            body: body,
            createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          ),
        ];
    }

    testWidgets('the message menu sets a reminder', (tester) async {
      final reminders = FakeRemindersRepository();
      await tester.pumpWidget(app(chatWith('Bring the tripod'), reminders));
      await tester.pump();

      await tester.longPress(find.text('Bring the tripod'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-remind')));
      await tester.pumpAndSettle();

      // The sheet names the message and offers the picks.
      expect(find.text('Remind me'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(WhenSheet),
          matching: find.text('Bring the tripod'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('when-inTwentyMinutes')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('when-inOneHour')), findsOneWidget);
      expect(find.byKey(const ValueKey('when-inThreeHours')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('when-tomorrowMorning')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('when-custom')), findsOneWidget);

      final before = DateTime.now();
      await tester.tap(find.byKey(const ValueKey('when-inThreeHours')));
      await tester.pumpAndSettle();

      final call = reminders.setCalls.single;
      expect(call.messageId, 'message-1');
      final lead = call.at.difference(before);
      expect(lead, greaterThan(const Duration(hours: 2, minutes: 58)));
      expect(lead, lessThan(const Duration(hours: 3, minutes: 1)));
      expect(find.textContaining('Reminder set for'), findsOneWidget);
    });

    testWidgets('a failed save says so', (tester) async {
      final reminders = FakeRemindersRepository()
        ..failSetWith = StateError('offline');
      await tester.pumpWidget(app(chatWith('Bring the tripod'), reminders));
      await tester.pump();

      await tester.longPress(find.text('Bring the tripod'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-remind')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('when-inOneHour')));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not set the reminder. Try again.'),
        findsOneWidget,
      );
    });
  });

  group('notifications', () {
    Future<PhoneWorld> openInbox(
      WidgetTester tester,
      FakeRemindersRepository reminders,
    ) async {
      final world = PhoneWorld()
        ..extraOverrides = [
          remindersRepositoryProvider.overrideWithValue(reminders),
        ];
      await world.open(tester, '/notifications');
      await settle(tester);
      return world;
    }

    testWidgets('a due reminder is a card with Jump and Dismiss', (
      tester,
    ) async {
      final reminders = FakeRemindersRepository([
        _reminder(
          'r1',
          at: DateTime.now().subtract(const Duration(minutes: 3)),
        ),
        _reminder('r2', at: DateTime.now().add(const Duration(hours: 4))),
      ]);
      await openInbox(tester, reminders);

      expect(find.byKey(const ValueKey('reminder-r1')), findsOneWidget);
      expect(find.text('Bring the tripod'), findsOneWidget);
      // The upcoming one is on the Reminders filter only.
      expect(find.byKey(const ValueKey('reminder-r2')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('inbox-filter-reminders')));
      await settle(tester);
      expect(find.byKey(const ValueKey('reminder-r1')), findsOneWidget);
      expect(find.byKey(const ValueKey('reminder-r2')), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Cancel reminder'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('reminder-dismiss-r1')));
      await settle(tester);
      expect(reminders.dismissed, ['r1']);
      expect(find.byKey(const ValueKey('reminder-r1')), findsNothing);
    });

    testWidgets('a reminder about a deleted message says so', (tester) async {
      final reminders = FakeRemindersRepository([
        _reminder(
          'r1',
          at: DateTime.now().subtract(const Duration(minutes: 3)),
          available: false,
          messageId: null,
        ),
      ]);
      await openInbox(tester, reminders);

      expect(find.text('Message unavailable'), findsOneWidget);
      expect(find.byKey(const ValueKey('reminder-dismiss-r1')), findsOneWidget);
    });

    testWidgets('Jump opens the conversation at the message', (tester) async {
      final reminders = FakeRemindersRepository([
        _reminder(
          'r1',
          at: DateTime.now().subtract(const Duration(minutes: 3)),
        ),
      ]);
      final world = await openInbox(tester, reminders);

      await tester.tap(find.byKey(const ValueKey('reminder-jump-r1')));
      await settle(tester);

      expect(world.router.state.uri.path, '/chats/dm-1');
    });
  });
}
