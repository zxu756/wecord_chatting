import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/profile.dart';

final currentProfileProvider = FutureProvider.autoDispose<Profile>((ref) {
  return ref.watch(settingsRepositoryProvider).currentProfile();
});

final blockedUsersProvider = FutureProvider.autoDispose<List<Profile>>((ref) {
  return ref.watch(settingsRepositoryProvider).listBlockedUsers();
});

final currentNotificationPreferencesProvider =
    FutureProvider.autoDispose<NotificationPreferences>((ref) {
      return ref.watch(notificationPreferencesRepositoryProvider).load();
    });

final currentNotificationPermissionStatusProvider =
    FutureProvider.autoDispose<NotificationPermissionStatus>((ref) {
      return ref.watch(localNotificationServiceProvider).permissionStatus();
    });
