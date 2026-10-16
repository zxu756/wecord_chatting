import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/later/scheduled_messages_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/push/push_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';

import '../chats/chat_thread_screen_test.dart' as thread_test;
import '../file_preview/file_preview_fakes.dart';
import 'later_fakes.dart';

void main() {
  Widget app(
    thread_test.FakeChatsRepository chats,
    FakeScheduledMessagesRepository scheduled,
  ) {
    return ProviderScope(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(chats),
        scheduledMessagesRepositoryProvider.overrideWithValue(scheduled),
        pushRepositoryProvider.overrideWithValue(RecordingPushRepository()),
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

  Future<void> scheduleFor(WidgetTester tester, Future<void> Function() open) async {
    await tester.enterText(find.byType(TextField), 'Happy birthday!');
    await tester.pump();
    await open();
    await tester.pumpAndSettle();
    expect(find.text('Schedule message'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('when-tomorrowMorning')));
    await tester.pumpAndSettle();
  }

  testWidgets('long-pressing send schedules the message', (tester) async {
    final chats = thread_test.FakeChatsRepository();
    final scheduled = FakeScheduledMessagesRepository();
    await tester.pumpWidget(app(chats, scheduled));
    await tester.pump();

    await scheduleFor(
      tester,
      () => tester.longPress(
        find.byKey(const ValueKey('composer-send-button')),
      ),
    );

    // Queued for tomorrow at 9, not sent.
    final created = scheduled.created.single;
    expect(created.conversationId, 'conversation-1');
    expect(created.body, 'Happy birthday!');
    expect(created.sendAt.hour, 9);
    expect(chats.sentMessages, isEmpty);
    // The composer is empty again and the banner counts it.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text('1 scheduled message'), findsOneWidget);
    expect(find.textContaining('Scheduled for Tomorrow'), findsOneWidget);
  });

  testWidgets('right-clicking send schedules the message', (tester) async {
    final chats = thread_test.FakeChatsRepository();
    final scheduled = FakeScheduledMessagesRepository();
    await tester.pumpWidget(app(chats, scheduled));
    await tester.pump();

    await scheduleFor(
      tester,
      () => tester.tap(
        find.byKey(const ValueKey('composer-send-button')),
        buttons: kSecondaryButton,
      ),
    );

    expect(scheduled.created.single.body, 'Happy birthday!');
    expect(chats.sentMessages, isEmpty);
  });

  testWidgets('the attach menu offers it too, for keyboards', (tester) async {
    final chats = thread_test.FakeChatsRepository();
    final scheduled = FakeScheduledMessagesRepository();
    await tester.pumpWidget(app(chats, scheduled));
    await tester.pump();

    await scheduleFor(tester, () async {
      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-schedule-entry')));
    });

    expect(scheduled.created.single.body, 'Happy birthday!');
  });

  testWidgets('a plain tap still sends', (tester) async {
    final chats = thread_test.FakeChatsRepository();
    final scheduled = FakeScheduledMessagesRepository();
    await tester.pumpWidget(app(chats, scheduled));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Right now');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(scheduled.created, isEmpty);
    expect(chats.sentMessages.map((m) => m.body), contains("Right now"));
  });

  testWidgets('an empty composer has nothing to schedule', (tester) async {
    final chats = thread_test.FakeChatsRepository();
    final scheduled = FakeScheduledMessagesRepository();
    await tester.pumpWidget(app(chats, scheduled));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-schedule-entry')));
    await tester.pumpAndSettle();

    expect(find.text('Write a message to schedule.'), findsOneWidget);
    expect(find.byKey(const ValueKey('when-custom')), findsNothing);
    expect(scheduled.created, isEmpty);
  });

  testWidgets('the banner opens the list', (tester) async {
    final chats = thread_test.FakeChatsRepository();
    final scheduled = FakeScheduledMessagesRepository([
      ScheduledMessage(
        id: 'a',
        conversationId: 'conversation-1',
        body: 'Queued earlier',
        sendAt: DateTime.now().add(const Duration(days: 1)).toUtc(),
      ),
    ]);
    await tester.pumpWidget(app(chats, scheduled));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('scheduled-banner')));
    await tester.pumpAndSettle();

    expect(find.text('Scheduled messages'), findsOneWidget);
    expect(find.text('Queued earlier'), findsOneWidget);
  });
}
