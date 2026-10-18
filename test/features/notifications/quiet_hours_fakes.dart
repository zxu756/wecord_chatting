import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/notifications/notification_settings.dart';
import 'package:wecord/features/notifications/notification_settings_controller.dart';
import 'package:wecord/features/notifications/notification_settings_repository.dart';

/// Overrides for the screens of quiet hours: an in-memory server, the clock
/// and the device's time zone.
List<Override> quietHoursOverrides({
  InMemoryNotificationSettingsRepository? repository,
  DateTime? now,
  String? zone = 'Asia/Shanghai',
}) {
  return [
    notificationSettingsRepositoryProvider.overrideWithValue(
      repository ?? InMemoryNotificationSettingsRepository(),
    ),
    if (now != null) quietHoursNowProvider.overrideWithValue(() => now),
    deviceTimeZoneProvider.overrideWithValue(() => zone),
  ];
}

/// A person with quiet hours on from 22:00 to 07:00 on weekdays, who lets
/// calls through and chose one important contact.
InMemoryNotificationSettingsRepository quietHoursServer({
  bool enabled = true,
  Set<String> contacts = const {'user-3'},
}) {
  return InMemoryNotificationSettingsRepository(
    NotificationSettings(
      timezone: 'Asia/Shanghai',
      quietEnabled: enabled,
      quietDays: const {1, 2, 3, 4, 5},
      allowMentions: false,
      vipUserIds: contacts,
    ),
  );
}
