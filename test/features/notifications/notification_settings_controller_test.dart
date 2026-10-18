import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/notifications/notification_settings.dart';
import 'package:wecord/features/notifications/notification_settings_controller.dart';
import 'package:wecord/features/notifications/notification_settings_repository.dart';

void main() {
  late InMemoryNotificationSettingsRepository server;
  late String? deviceZone;
  late DateTime now;
  late ProviderContainer container;

  ProviderContainer build({AuthUser? user}) {
    return ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(user ?? const AuthUser(id: 'user-1')),
        ),
        notificationSettingsRepositoryProvider.overrideWithValue(server),
        deviceTimeZoneProvider.overrideWithValue(() => deviceZone),
        quietHoursNowProvider.overrideWithValue(() => now),
      ],
    );
  }

  Future<NotificationSettings> loaded() async {
    final subscription = container.listen(
      notificationSettingsProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    return container.read(notificationSettingsProvider.future);
  }

  setUp(() {
    server = InMemoryNotificationSettingsRepository();
    deviceZone = 'Asia/Shanghai';
    now = DateTime(2026, 10, 20, 12);
    container = build();
    addTearDown(container.dispose);
  });

  test(
    'a person without a row gets the defaults, and the zone is saved',
    () async {
      container.listen(authStateProvider, (_, _) {});
      await container.read(authStateProvider.future);

      final settings = await loaded();

      expect(settings.quietEnabled, isFalse);
      expect(settings.timezone, 'Asia/Shanghai');
      expect(server.settings?.timezone, 'Asia/Shanghai');
    },
  );

  test('the zone is saved again when the device moved', () async {
    server.settings = const NotificationSettings(timezone: 'Europe/Paris');
    container.listen(authStateProvider, (_, _) {});
    await container.read(authStateProvider.future);

    final settings = await loaded();

    expect(settings.timezone, 'Asia/Shanghai');
    expect(server.settings?.timezone, 'Asia/Shanghai');
  });

  test('a zone that is already saved is not saved again', () async {
    server.settings = const NotificationSettings(timezone: 'Asia/Shanghai');
    container.listen(authStateProvider, (_, _) {});
    await container.read(authStateProvider.future);

    await loaded();

    expect(server.saves, 0);
  });

  test('a device that cannot tell its zone leaves the saved one', () async {
    deviceZone = null;
    server.settings = const NotificationSettings(timezone: 'Europe/Paris');
    container.listen(authStateProvider, (_, _) {});
    await container.read(authStateProvider.future);

    final settings = await loaded();

    expect(settings.timezone, 'Europe/Paris');
    expect(server.saves, 0);
  });

  test('saving quiet hours shows at once and reaches the server', () async {
    container.listen(authStateProvider, (_, _) {});
    await container.read(authStateProvider.future);
    await loaded();
    final controller = container.read(notificationSettingsProvider.notifier);

    await controller.saveQuietHours(
      NotificationSettings.defaults.copyWith(
        quietEnabled: true,
        quietStart: const QuietTime(23, 30),
        quietDays: {1, 2},
        allowCalls: false,
      ),
    );

    final shown = container.read(notificationSettingsProvider).value!;
    expect(shown.quietEnabled, isTrue);
    expect(shown.quietStart, const QuietTime(23, 30));
    expect(shown.quietDays, {1, 2});
    expect(shown.allowCalls, isFalse);
    // The zone and the important contacts are not overwritten.
    expect(shown.timezone, 'Asia/Shanghai');
    expect(server.settings?.quietEnabled, isTrue);
    expect(server.settings?.timezone, 'Asia/Shanghai');
  });

  test('a failed save goes back to what was saved', () async {
    container.listen(authStateProvider, (_, _) {});
    await container.read(authStateProvider.future);
    await loaded();
    final controller = container.read(notificationSettingsProvider.notifier);
    server.failWith = StateError('offline');

    await expectLater(
      controller.saveQuietHours(
        NotificationSettings.defaults.copyWith(quietEnabled: true),
      ),
      throwsStateError,
    );

    expect(
      container.read(notificationSettingsProvider).value!.quietEnabled,
      isFalse,
    );
  });

  test('important contacts are added and removed one at a time', () async {
    container.listen(authStateProvider, (_, _) {});
    await container.read(authStateProvider.future);
    await loaded();
    final controller = container.read(notificationSettingsProvider.notifier);

    await controller.setImportantContact('cy', important: true);
    await controller.setImportantContact('dee', important: true);
    await controller.setImportantContact('cy', important: false);

    expect(container.read(notificationSettingsProvider).value!.vipUserIds, {
      'dee',
    });
    expect(server.settings?.vipUserIds, {'dee'});
  });

  test('choosing the whole list changes only the difference', () async {
    server.settings = const NotificationSettings(vipUserIds: {'a', 'b'});
    container.listen(authStateProvider, (_, _) {});
    await container.read(authStateProvider.future);
    await loaded();
    final controller = container.read(notificationSettingsProvider.notifier);

    await controller.setImportantContacts({'b', 'c'});

    expect(server.settings?.vipUserIds, {'b', 'c'});
  });

  test('a failed change of a contact is taken back', () async {
    container.listen(authStateProvider, (_, _) {});
    await container.read(authStateProvider.future);
    await loaded();
    final controller = container.read(notificationSettingsProvider.notifier);
    server.failWith = StateError('offline');

    await expectLater(
      controller.setImportantContact('cy', important: true),
      throwsStateError,
    );

    expect(
      container.read(notificationSettingsProvider).value!.vipUserIds,
      isEmpty,
    );
  });

  group('quietHoursActiveProvider', () {
    Future<bool> active() async {
      container.listen(authStateProvider, (_, _) {});
      await container.read(authStateProvider.future);
      await loaded();
      final subscription = container.listen(
        quietHoursActiveProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      return container.read(quietHoursActiveProvider);
    }

    test('is off while quiet hours are off', () async {
      server.settings = const NotificationSettings();
      expect(await active(), isFalse);
    });

    test('is on inside the window, across midnight too', () async {
      server.settings = const NotificationSettings(quietEnabled: true);
      now = DateTime(2026, 10, 20, 23, 30);
      expect(await active(), isTrue);
    });

    test('is off outside the window', () async {
      server.settings = const NotificationSettings(quietEnabled: true);
      now = DateTime(2026, 10, 20, 12);
      expect(await active(), isFalse);
    });

    test('follows a switch made on the settings page', () async {
      server.settings = const NotificationSettings();
      now = DateTime(2026, 10, 20, 23, 30);
      expect(await active(), isFalse);

      await container
          .read(notificationSettingsProvider.notifier)
          .saveQuietHours(
            NotificationSettings.defaults.copyWith(quietEnabled: true),
          );

      expect(container.read(quietHoursActiveProvider), isTrue);
    });
  });
}
