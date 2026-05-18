import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabledKey = 'wecord.notifications.enabled';
const _showPreviewsKey = 'wecord.notifications.show_previews';

final notificationPreferencesRepositoryProvider =
    Provider<NotificationPreferencesRepository>((ref) {
      return NotificationPreferencesRepository.withStore(
        SharedPreferencesNotificationPreferencesStore(),
      );
    });

class NotificationPreferences {
  const NotificationPreferences({
    required this.enabled,
    required this.showPreviews,
  });

  static const defaults = NotificationPreferences(
    enabled: true,
    showPreviews: true,
  );

  final bool enabled;
  final bool showPreviews;

  NotificationPreferences copyWith({bool? enabled, bool? showPreviews}) {
    return NotificationPreferences(
      enabled: enabled ?? this.enabled,
      showPreviews: showPreviews ?? this.showPreviews,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NotificationPreferences &&
        other.enabled == enabled &&
        other.showPreviews == showPreviews;
  }

  @override
  int get hashCode => Object.hash(enabled, showPreviews);
}

abstract interface class NotificationPreferencesStore {
  Future<NotificationPreferences?> load();

  Future<void> save(NotificationPreferences preferences);
}

class NotificationPreferencesRepository {
  const NotificationPreferencesRepository.withStore(this._store);

  final NotificationPreferencesStore _store;

  Future<NotificationPreferences> load() async {
    return await _store.load() ?? NotificationPreferences.defaults;
  }

  Future<void> save(NotificationPreferences preferences) {
    return _store.save(preferences);
  }
}

class SharedPreferencesNotificationPreferencesStore
    implements NotificationPreferencesStore {
  const SharedPreferencesNotificationPreferencesStore();

  @override
  Future<NotificationPreferences?> load() async {
    final preferences = await SharedPreferences.getInstance();
    return NotificationPreferences(
      enabled: preferences.getBool(_enabledKey) ?? true,
      showPreviews: preferences.getBool(_showPreviewsKey) ?? true,
    );
  }

  @override
  Future<void> save(NotificationPreferences preferences) async {
    final sharedPreferences = await SharedPreferences.getInstance();
    await sharedPreferences.setBool(_enabledKey, preferences.enabled);
    await sharedPreferences.setBool(_showPreviewsKey, preferences.showPreviews);
  }
}

class InMemoryNotificationPreferencesStore
    implements NotificationPreferencesStore {
  InMemoryNotificationPreferencesStore([NotificationPreferences? preferences])
    : _preferences = preferences;

  NotificationPreferences? _preferences;

  @override
  Future<NotificationPreferences?> load() async => _preferences;

  @override
  Future<void> save(NotificationPreferences preferences) async {
    _preferences = preferences;
  }
}
