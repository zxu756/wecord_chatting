import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/later/reminders_repository.dart';
import 'package:wecord/features/notifications/notification_settings.dart';
import 'package:wecord/shared/models/message.dart';

import '../later/later_fakes.dart';
import 'notification_coordinator_test.dart';

/// The notifications the app itself shows (a browser tab or window that is
/// open) follow quiet hours too, like the pushes the server holds back.
void main() {
  // 23:30 on the clock of the device: inside a 22:00-07:00 window.
  final night = DateTime(2026, 10, 20, 23, 30);
  final noon = DateTime(2026, 10, 20, 12);

  const quiet = NotificationSettings(quietEnabled: true, vipUserIds: {'cy'});

  Future<NotificationCoordinatorHarness> started({
    NotificationSettings? settings = quiet,
    DateTime? now,
    Set<String> starred = const {},
  }) async {
    final harness = NotificationCoordinatorHarness(
      now: () => now ?? night,
      quietSettings: () => settings,
      starredFriendIds: () async => starred,
    );
    harness.seed([harness.summary(id: 'c1')]);
    await harness.start();
    return harness;
  }

  test('an ordinary message is held back in quiet hours', () async {
    final harness = await started();

    await harness.emit([
      harness.summary(id: 'c1', unreadCount: 1, body: 'hello'),
    ]);

    expect(harness.notifications, isEmpty);
  });

  test('outside the window it notifies as usual', () async {
    final harness = await started(now: noon);

    await harness.emit([
      harness.summary(id: 'c1', unreadCount: 1, body: 'hello'),
    ]);

    expect(harness.notifications.single.body, 'hello');
  });

  test('with quiet hours off it notifies as usual', () async {
    final harness = await started(settings: const NotificationSettings());

    await harness.emit([
      harness.summary(id: 'c1', unreadCount: 1, body: 'hello'),
    ]);

    expect(harness.notifications.single.body, 'hello');
  });

  test('an @mention of the person breaks through', () async {
    final harness = await started();

    await harness.emit([
      harness.summary(
        id: 'c1',
        unreadCount: 1,
        body: '@Me look',
        mentionedUserIds: {'current-user'},
      ),
    ]);

    expect(harness.notifications.single.body, '@Me look');
  });

  test('an @mention is held back when the person turned that off', () async {
    final harness = await started(
      settings: quiet.copyWith(allowMentions: false),
    );

    await harness.emit([
      harness.summary(
        id: 'c1',
        unreadCount: 1,
        mentionedUserIds: {'current-user'},
      ),
    ]);

    expect(harness.notifications, isEmpty);
  });

  test('an important contact breaks through', () async {
    final harness = await started();

    await harness.emit([
      harness.summary(
        id: 'c1',
        unreadCount: 1,
        body: 'from Cy',
        lastMessageSenderId: 'cy',
      ),
    ]);

    expect(harness.notifications.single.body, 'from Cy');
  });

  test('a starred friend breaks through, if allowed', () async {
    final harness = await started(starred: {'bob'});
    await harness.emit([
      harness.summary(
        id: 'c1',
        unreadCount: 1,
        body: 'from Bob',
        lastMessageSenderId: 'bob',
      ),
    ]);
    expect(harness.notifications.single.body, 'from Bob');

    final off = await started(
      settings: quiet.copyWith(allowStarred: false),
      starred: {'bob'},
    );
    await off.emit([
      off.summary(
        id: 'c1',
        unreadCount: 1,
        body: 'from Bob',
        lastMessageSenderId: 'bob',
      ),
    ]);
    expect(off.notifications, isEmpty);
  });

  test('a stranger is held back though others are starred', () async {
    final harness = await started(starred: {'bob'});

    await harness.emit([
      harness.summary(id: 'c1', unreadCount: 1, lastMessageSenderId: 'dee'),
    ]);

    expect(harness.notifications, isEmpty);
  });

  test(
    'held back is not postponed: nothing shows when the window ends',
    () async {
      var now = night;
      final harness = NotificationCoordinatorHarness(
        now: () => now,
        quietSettings: () => quiet,
      );
      harness.seed([harness.summary(id: 'c1')]);
      await harness.start();
      await harness.emit([
        harness.summary(id: 'c1', unreadCount: 1, body: 'late'),
      ]);

      now = noon;
      await harness.poll([
        harness.summary(id: 'c1', unreadCount: 1, body: 'late'),
      ]);

      expect(harness.notifications, isEmpty);
    },
  );

  test('message reminders are held back too', () async {
    final harness = NotificationCoordinatorHarness(
      now: () => night,
      quietSettings: () => quiet,
      remindersRepository: FakeRemindersRepository()
        ..due = [
          const LocalReminder(
            id: 'r1',
            conversationId: 'c1',
            messageId: 'm1',
            senderName: 'Bob',
            body: 'tripod',
            type: MessageType.text,
          ),
        ],
    );
    harness.seed([]);

    await harness.start();

    expect(harness.notifications, isEmpty);
  });
}
