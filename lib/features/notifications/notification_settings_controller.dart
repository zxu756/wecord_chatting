import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/notifications/device_time_zone.dart';
import 'package:wecord/features/notifications/notification_settings.dart';
import 'package:wecord/features/notifications/notification_settings_repository.dart';

/// Where the app asks for this device's IANA time zone (a test can answer
/// for it).
final deviceTimeZoneProvider = Provider<String? Function()>(
  (ref) => deviceTimeZone,
);

/// Where quiet hours ask what time it is on the clock (a test can set it).
final quietHoursNowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The person's notification settings from the server: quiet hours, the
/// important contacts and the message previews switch. Reloaded for whoever
/// signs in. The device reports its time zone once the settings are loaded
/// (and again when it changes), so the server knows when quiet hours are.
class NotificationSettingsController
    extends AsyncNotifier<NotificationSettings> {
  @override
  Future<NotificationSettings> build() async {
    // The settings belong to the signed-in person.
    final userId = ref.watch(authStateProvider.select((s) => s.value?.id));
    if (userId == null) {
      return NotificationSettings.defaults;
    }
    final repository = ref.watch(notificationSettingsRepositoryProvider);
    var settings = await repository.load() ?? NotificationSettings.defaults;

    final zone = ref.read(deviceTimeZoneProvider)();
    if (looksLikeTimeZone(zone) && zone != settings.timezone) {
      try {
        await repository.saveTimeZone(zone!);
        settings = settings.copyWith(timezone: zone);
      } catch (_) {
        // Reported again the next time the app starts.
      }
    }
    return settings;
  }

  NotificationSettings get _current =>
      state.value ?? NotificationSettings.defaults;

  /// Saves the quiet hours part of [next] (switch, window, weekdays and
  /// exceptions). The screen shows it at once; when saving fails it goes
  /// back to what was saved and the error is thrown.
  Future<void> saveQuietHours(NotificationSettings next) async {
    final before = _current;
    final shown = before.copyWith(
      quietEnabled: next.quietEnabled,
      quietDays: next.quietDays,
      quietStart: next.quietStart,
      quietEnd: next.quietEnd,
      allowStarred: next.allowStarred,
      allowMentions: next.allowMentions,
      allowCalls: next.allowCalls,
    );
    state = AsyncData(shown);
    try {
      await ref
          .read(notificationSettingsRepositoryProvider)
          .saveQuietHours(shown);
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  /// Marks [friendId] as an important contact (heard in quiet hours) or not.
  Future<void> setImportantContact(
    String friendId, {
    required bool important,
  }) async {
    final before = _current;
    final vips = {...before.vipUserIds};
    important ? vips.add(friendId) : vips.remove(friendId);
    state = AsyncData(before.copyWith(vipUserIds: vips));
    try {
      await ref
          .read(notificationSettingsRepositoryProvider)
          .setImportantContact(friendId, important: important);
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  /// Makes the important contacts exactly [friendIds].
  Future<void> setImportantContacts(Set<String> friendIds) async {
    final current = _current.vipUserIds;
    for (final id in friendIds.difference(current)) {
      await setImportantContact(id, important: true);
    }
    for (final id in current.difference(friendIds)) {
      await setImportantContact(id, important: false);
    }
  }
}

final notificationSettingsProvider =
    AsyncNotifierProvider<NotificationSettingsController, NotificationSettings>(
      NotificationSettingsController.new,
    );

/// Whether it is quiet hours now for this person, with the moon in the user
/// panel in mind. Wakes up when the window opens or closes; no timer at all
/// while quiet hours are off.
final quietHoursActiveProvider = Provider.autoDispose<bool>((ref) {
  final settings = ref.watch(notificationSettingsProvider).value;
  if (settings == null || !settings.quietEnabled) {
    return false;
  }
  final now = ref.watch(quietHoursNowProvider)();
  final wake = settings.nextBoundaryAfter(now).difference(now).inMilliseconds;
  final timer = Timer(Duration(milliseconds: wake + 1000), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return settings.isQuietAt(now);
});
