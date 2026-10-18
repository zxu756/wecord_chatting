import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/features/notifications/notification_settings.dart';
import 'package:wecord/features/notifications/notification_settings_repository.dart';

/// The message previews switch moved from the device to the server
/// (user_notification_settings.show_previews).
void main() {
  late InMemoryNotificationPreferencesStore store;
  late InMemoryNotificationSettingsRepository server;
  String? user;

  NotificationPreferencesRepository repository() =>
      NotificationPreferencesRepository.withStore(
        store,
        settings: server,
        currentUserId: () => user,
      );

  setUp(() {
    store = InMemoryNotificationPreferencesStore();
    server = InMemoryNotificationSettingsRepository();
    user = 'user-1';
  });

  test('the first run moves the device value to the server', () async {
    await store.save(
      const NotificationPreferences(enabled: true, showPreviews: false),
    );

    final preferences = await repository().load();

    expect(preferences.showPreviews, isFalse);
    expect(server.settings?.showPreviews, isFalse);
  });

  test(
    'the first run with a quiet hours row but no previews value yet',
    () async {
      // Quiet hours were saved from this app before the previews were moved.
      server.settings = const NotificationSettings(quietEnabled: true);
      await store.save(
        const NotificationPreferences(enabled: true, showPreviews: false),
      );

      final preferences = await repository().load();

      expect(preferences.showPreviews, isFalse);
      expect(server.settings?.showPreviews, isFalse);
      expect(server.settings?.quietEnabled, isTrue);
    },
  );

  test('after that the server wins, and the device keeps a copy', () async {
    server.settings = const NotificationSettings(showPreviews: false);

    final preferences = await repository().load();

    expect(preferences.showPreviews, isFalse);
    expect((await store.load())?.showPreviews, isFalse);
  });

  test('the server is asked once, not at every load', () async {
    server.settings = const NotificationSettings(showPreviews: true);
    final repo = repository();

    await repo.load();
    final saves = server.saves;
    server.settings = const NotificationSettings(showPreviews: false);
    final again = await repo.load();

    // Cached for the session: a poll every few seconds must not hit the
    // server each time.
    expect(again.showPreviews, isTrue);
    expect(server.saves, saves);
  });

  test('saving sends the switch to the server', () async {
    final repo = repository();
    await repo.load();

    await repo.save(
      const NotificationPreferences(enabled: true, showPreviews: false),
    );

    expect(server.settings?.showPreviews, isFalse);
    expect((await repo.load()).showPreviews, isFalse);
  });

  test('saving only the device switch leaves the server alone', () async {
    final repo = repository();
    await repo.load();
    final saves = server.saves;

    await repo.save(
      const NotificationPreferences(enabled: false, showPreviews: true),
    );

    expect(server.saves, saves);
    expect((await store.load())?.enabled, isFalse);
  });

  test('offline, the device value is used and nothing is lost', () async {
    await store.save(
      const NotificationPreferences(enabled: true, showPreviews: false),
    );
    server.failWith = StateError('offline');
    final repo = repository();

    expect((await repo.load()).showPreviews, isFalse);
    expect(server.settings, isNull);

    // Back online (the retry delay aside), it moves over.
    server.failWith = null;
  });

  test('a change that could not be sent is sent at the next load', () async {
    final repo = repository();
    await repo.load();
    server.failWith = StateError('offline');

    await expectLater(
      repo.save(
        const NotificationPreferences(enabled: true, showPreviews: false),
      ),
      throwsStateError,
    );
    // The device has the choice at once.
    expect((await store.load())?.showPreviews, isFalse);

    server.failWith = null;
    final preferences = await repo.load();

    expect(preferences.showPreviews, isFalse);
    expect(server.settings?.showPreviews, isFalse);
  });

  test('another person on the same device starts from the server', () async {
    server.settings = const NotificationSettings(showPreviews: false);
    final repo = repository();
    expect((await repo.load()).showPreviews, isFalse);

    user = 'user-2';
    server.settings = const NotificationSettings(showPreviews: true);

    expect((await repo.load()).showPreviews, isTrue);
  });

  test('signed out, only the device is used', () async {
    user = null;
    await store.save(
      const NotificationPreferences(enabled: true, showPreviews: false),
    );

    expect((await repository().load()).showPreviews, isFalse);
    expect(server.settings, isNull);
  });

  test('without a server it is the device switch as before', () async {
    final repo = NotificationPreferencesRepository.withStore(store);
    await repo.save(
      const NotificationPreferences(enabled: false, showPreviews: false),
    );

    final preferences = await repo.load();
    expect(preferences.enabled, isFalse);
    expect(preferences.showPreviews, isFalse);
  });
}
