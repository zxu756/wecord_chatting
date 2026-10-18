import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/friend_tags/friend_profile_extras.dart';
import 'package:wecord/features/home/phone_home.dart';
import 'package:wecord/features/notifications/important_contact_row.dart';
import 'package:wecord/features/notifications/notification_settings.dart';
import 'package:wecord/features/notifications/notification_settings_repository.dart';
import 'package:wecord/features/notifications/quiet_hours_screen.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';
import 'quiet_hours_fakes.dart';

void main() {
  late InMemoryNotificationSettingsRepository server;
  late PhoneWorld world;

  Future<void> openScreen(
    WidgetTester tester, {
    NotificationSettings? settings,
    DateTime? now,
  }) async {
    usePhoneViewport(tester, notchedPhone);
    server = InMemoryNotificationSettingsRepository(settings);
    world = PhoneWorld()
      ..extraOverrides = quietHoursOverrides(repository: server, now: now);
    await pumpStandalone(tester, world, const QuietHoursScreen());
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    final list = find.byKey(const ValueKey('settings-page-list'));
    if (list.evaluate().isNotEmpty) {
      await tester.dragUntilVisible(finder, list, const Offset(0, -150));
    }
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  bool switchValue(WidgetTester tester, String key) {
    return tester
        .widget<WeCordSwitch>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(WeCordSwitch),
          ),
        )
        .value;
  }

  testWidgets('starts switched off, with the rest waiting', (tester) async {
    await openScreen(tester);

    expect(find.text('Quiet hours'), findsWidgets);
    expect(find.text('10:00 PM'), findsOneWidget);
    expect(find.text('7:00 AM'), findsOneWidget);
    // The next morning, since the window goes past midnight.
    expect(find.text('The next morning'), findsOneWidget);
    // Nothing can be changed until it is switched on.
    await tapKey(tester, 'quiet-hours-days');
    await tapKey(tester, 'quiet-hours-starred');
    expect(server.settings?.quietEnabled, isNot(true));
    expect(server.settings?.allowStarred, isNot(false));
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('the switch saves quiet hours on the server', (tester) async {
    await openScreen(tester);

    await tapKey(tester, 'quiet-hours-switch');

    expect(server.settings?.quietEnabled, isTrue);
    // The zone of the device is saved with it.
    expect(server.settings?.timezone, 'Asia/Shanghai');
  });

  testWidgets('shows what is saved', (tester) async {
    await openScreen(
      tester,
      settings: const NotificationSettings(
        quietEnabled: true,
        quietDays: {1, 2, 3},
        quietStart: QuietTime(23, 30),
        quietEnd: QuietTime(6, 15),
        allowCalls: false,
        vipUserIds: {'user-2', 'user-3'},
      ),
    );

    expect(find.text('11:30 PM'), findsOneWidget);
    expect(find.text('6:15 AM'), findsOneWidget);
    expect(find.text('2 people'), findsOneWidget);
    expect(switchValue(tester, 'quiet-hours-calls'), isFalse);
    expect(switchValue(tester, 'quiet-hours-starred'), isTrue);
  });

  testWidgets('picks the weekdays, and keeps at least one', (tester) async {
    await openScreen(
      tester,
      settings: const NotificationSettings(quietEnabled: true),
    );
    expect(find.text('Every day'), findsOneWidget);

    await tapKey(tester, 'quiet-hours-days');
    await tapKey(tester, 'quiet-day-6');
    await tapKey(tester, 'quiet-day-7');
    await tapKey(tester, 'quiet-days-done');

    expect(server.settings?.quietDays, {1, 2, 3, 4, 5});
    expect(find.text('Weekdays'), findsOneWidget);

    // The Done button waits while no day is chosen.
    await tapKey(tester, 'quiet-hours-days');
    for (final day in [1, 2, 3, 4, 5]) {
      await tapKey(tester, 'quiet-day-$day');
    }
    await tester.tap(find.byKey(const ValueKey('quiet-days-done')));
    await settle(tester);
    expect(find.byKey(const ValueKey('quiet-days-done')), findsOneWidget);
    expect(server.settings?.quietDays, {1, 2, 3, 4, 5});

    await tapKey(tester, 'quiet-day-3');
    await tapKey(tester, 'quiet-day-7');
    await tapKey(tester, 'quiet-days-done');
    expect(server.settings?.quietDays, {3, 7});
    expect(find.text('Wed, Sun'), findsOneWidget);
  });

  testWidgets('weekends are named as such', (tester) async {
    await openScreen(
      tester,
      settings: const NotificationSettings(
        quietEnabled: true,
        quietDays: {6, 7},
      ),
    );

    expect(find.text('Weekends'), findsOneWidget);
  });

  testWidgets('the days can be read by a screen reader', (tester) async {
    await openScreen(
      tester,
      settings: const NotificationSettings(quietEnabled: true),
    );
    final handle = tester.ensureSemantics();

    await tapKey(tester, 'quiet-hours-days');

    expect(find.bySemanticsLabel(RegExp('Monday')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Sunday')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the exceptions follow their switches', (tester) async {
    await openScreen(
      tester,
      settings: const NotificationSettings(quietEnabled: true),
    );

    await tapKey(tester, 'quiet-hours-starred');
    await tapKey(tester, 'quiet-hours-mentions');
    await tapKey(tester, 'quiet-hours-calls');

    expect(server.settings?.allowStarred, isFalse);
    expect(server.settings?.allowMentions, isFalse);
    expect(server.settings?.allowCalls, isFalse);
  });

  testWidgets('the time picker opens, and cancelling changes nothing', (
    tester,
  ) async {
    await openScreen(
      tester,
      settings: const NotificationSettings(quietEnabled: true),
    );

    await tapKey(tester, 'quiet-hours-start');
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Quiet hours start'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(find.byType(Dialog), findsNothing);
    expect(server.settings?.quietStart, const QuietTime(22, 0));
  });

  testWidgets('confirming the time picker saves the time', (tester) async {
    await openScreen(
      tester,
      settings: const NotificationSettings(quietEnabled: true),
    );

    await tapKey(tester, 'quiet-hours-end');
    await tester.tap(find.text('OK'));
    await settle(tester);

    expect(server.settings?.quietEnd, const QuietTime(7, 0));
  });

  testWidgets('chooses important contacts from friends', (tester) async {
    await openScreen(
      tester,
      settings: const NotificationSettings(
        quietEnabled: true,
        vipUserIds: {'user-3'},
      ),
    );
    expect(find.text('1 person'), findsOneWidget);

    await tapKey(tester, 'quiet-hours-contacts');
    await tester.tap(find.byKey(const ValueKey('quiet-contact-user-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quiet-contact-user-3')));
    await tester.pump();
    await tapKey(tester, 'quiet-contacts-done');

    expect(server.settings?.vipUserIds, {'user-2'});
    expect(find.text('1 person'), findsOneWidget);
  });

  testWidgets('a failed save says so and goes back', (tester) async {
    await openScreen(tester);
    await tester.pump();
    server.failWith = StateError('offline');

    await tapKey(tester, 'quiet-hours-switch');

    expect(find.text('Could not save. Try again.'), findsOneWidget);
    expect(switchValue(tester, 'quiet-hours-switch'), isFalse);
  });

  testWidgets('the Notifications settings lead here', (tester) async {
    server = quietHoursServer();
    world = PhoneWorld()
      ..extraOverrides = quietHoursOverrides(repository: server);
    await world.open(tester, '/me');
    final tile = find.byKey(const ValueKey('quiet-hours-tile'));
    await tester.dragUntilVisible(
      tile,
      find.byKey(const ValueKey('settings-page-list')),
      const Offset(0, -200),
    );
    await settle(tester);

    expect(find.text('10:00 PM – 7:00 AM'), findsOneWidget);
    await tester.tap(tile);
    await settle(tester);

    expect(find.byKey(const ValueKey('quiet-hours-screen')), findsOneWidget);
    await world.close(tester);
  });

  group('important contact on a friend profile', () {
    testWidgets('switches the friend on and off', (tester) async {
      server = InMemoryNotificationSettingsRepository();
      world = PhoneWorld()
        ..extraOverrides = quietHoursOverrides(repository: server);
      await pumpStandalone(
        tester,
        world,
        Scaffold(body: ImportantContactRow(friend: bart)),
      );
      expect(find.text('Important contact'), findsOneWidget);
      expect(find.text('Notify me even in quiet hours.'), findsOneWidget);

      await tapKey(tester, 'profile-important');
      expect(server.settings?.vipUserIds, {bart.id});

      await tapKey(tester, 'profile-important');
      expect(server.settings?.vipUserIds, isEmpty);
    });

    testWidgets('is part of what only you see about a friend', (tester) async {
      server = quietHoursServer(contacts: {bart.id});
      world = PhoneWorld()
        ..extraOverrides = quietHoursOverrides(repository: server);
      await pumpStandalone(
        tester,
        world,
        Scaffold(body: FriendProfileExtras(friend: bart)),
      );

      expect(switchValue(tester, 'profile-important'), isTrue);
    });
  });

  group('the moon on the bell', () {
    testWidgets('shows during quiet hours', (tester) async {
      world = PhoneWorld()
        ..extraOverrides = quietHoursOverrides(
          repository: quietHoursServer(),
          // Tuesday 23:30.
          now: DateTime(2026, 10, 20, 23, 30),
        );
      await world.open(tester, '/home');

      expect(find.byType(PhoneUserPanel), findsOneWidget);
      expect(find.byKey(const ValueKey('quiet-hours-moon')), findsOneWidget);
      expect(find.bySemanticsLabel('Quiet hours are on'), findsAny);
      await world.close(tester);
    });

    testWidgets('is gone outside the window', (tester) async {
      world = PhoneWorld()
        ..extraOverrides = quietHoursOverrides(
          repository: quietHoursServer(),
          now: DateTime(2026, 10, 20, 12),
        );
      await world.open(tester, '/home');

      expect(find.byKey(const ValueKey('quiet-hours-moon')), findsNothing);
      await world.close(tester);
    });

    testWidgets('is gone when quiet hours are off', (tester) async {
      world = PhoneWorld()
        ..extraOverrides = quietHoursOverrides(
          repository: quietHoursServer(enabled: false),
          now: DateTime(2026, 10, 20, 23, 30),
        );
      await world.open(tester, '/home');

      expect(find.byKey(const ValueKey('quiet-hours-moon')), findsNothing);
      await world.close(tester);
    });

    testWidgets('shows next to Notifications in the desktop sidebar', (
      tester,
    ) async {
      usePhoneViewport(
        tester,
        const PhoneViewport(
          name: 'desktop',
          size: Size(1280, 800),
          devicePixelRatio: 1,
        ),
      );
      world = PhoneWorld()
        ..extraOverrides = quietHoursOverrides(
          repository: quietHoursServer(),
          now: DateTime(2026, 10, 20, 23, 30),
        );
      await world.open(tester, '/home');

      expect(find.byKey(const ValueKey('quiet-hours-moon')), findsOneWidget);
      await world.close(tester);
    });
  });
}
