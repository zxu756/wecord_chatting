import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';

void main() {
  test('notification preferences default to enabled with previews', () async {
    final store = InMemoryNotificationPreferencesStore();
    final repository = NotificationPreferencesRepository.withStore(store);

    final preferences = await repository.load();

    expect(preferences.enabled, isTrue);
    expect(preferences.showPreviews, isTrue);
  });

  test('notification preferences persist updates', () async {
    final store = InMemoryNotificationPreferencesStore();
    final repository = NotificationPreferencesRepository.withStore(store);

    await repository.save(
      const NotificationPreferences(enabled: false, showPreviews: false),
    );

    final preferences = await repository.load();
    expect(preferences.enabled, isFalse);
    expect(preferences.showPreviews, isFalse);
  });
}
