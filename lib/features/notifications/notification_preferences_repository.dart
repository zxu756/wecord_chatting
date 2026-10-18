import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/notifications/notification_settings_repository.dart';

const _enabledKey = 'wecord.notifications.enabled';
const _showPreviewsKey = 'wecord.notifications.show_previews';

final notificationPreferencesRepositoryProvider =
    Provider<NotificationPreferencesRepository>((ref) {
      return NotificationPreferencesRepository.withStore(
        const SharedPreferencesNotificationPreferencesStore(),
        settings: ref.watch(notificationSettingsRepositoryProvider),
        currentUserId: () {
          try {
            return ref.read(authRepositoryProvider).currentUser?.id;
          } catch (_) {
            return null;
          }
        },
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

/// The notification preferences: whether this device shows notifications
/// (kept on the device, because it follows the device's permission) and the
/// message previews switch, which lives on the server
/// (`user_notification_settings.show_previews`) so every device and the push
/// functions agree.
///
/// The first time a person's device meets the server's copy it has no value
/// yet, and the device's own is moved there. From then on the server's wins,
/// and the device keeps a copy for when it is offline. A change that could
/// not be sent is sent again at the next load.
class NotificationPreferencesRepository {
  NotificationPreferencesRepository.withStore(
    this._store, {
    this._settings,
    this._currentUserId,
  });

  final NotificationPreferencesStore _store;
  final NotificationSettingsRepository? _settings;
  final String? Function()? _currentUserId;

  /// The person the copy below belongs to.
  String? _syncedFor;

  /// The server's previews value, once known for [_syncedFor].
  bool? _serverPreviews;

  /// A previews change the server hasn't been told yet.
  bool? _unsentPreviews;

  /// After a failure the server isn't asked again for a while: the
  /// notification coordinator loads the preferences on every poll.
  DateTime? _retryAfter;
  static const _retryDelay = Duration(minutes: 1);

  Future<NotificationPreferences> load() async {
    final local = await _store.load() ?? NotificationPreferences.defaults;
    final settings = _settings;
    final userId = _currentUserId?.call();
    if (settings == null || userId == null) {
      return local;
    }
    if (_syncedFor != userId) {
      _syncedFor = userId;
      _serverPreviews = null;
      _unsentPreviews = null;
      _retryAfter = null;
    }
    final unsent = _unsentPreviews;
    final known = _serverPreviews;
    if (unsent == null && known != null) {
      return local.copyWith(showPreviews: known);
    }
    final retryAfter = _retryAfter;
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) {
      return local;
    }
    try {
      if (unsent != null) {
        await settings.saveShowPreviews(show: unsent);
        _serverPreviews = unsent;
        _unsentPreviews = null;
        return local.copyWith(showPreviews: unsent);
      }
      final server = (await settings.load())?.showPreviews;
      if (server == null) {
        // First run: the device's value moves to the server.
        await settings.saveShowPreviews(show: local.showPreviews);
        _serverPreviews = local.showPreviews;
        return local;
      }
      _serverPreviews = server;
      final shown = local.copyWith(showPreviews: server);
      if (server != local.showPreviews) {
        await _store.save(shown);
      }
      return shown;
    } catch (_) {
      _retryAfter = DateTime.now().add(_retryDelay);
      return local;
    }
  }

  /// Saves on the device and, for the previews switch, on the server. Throws
  /// when the server could not be told (the device still has the choice, and
  /// the server is told again at the next load).
  Future<void> save(NotificationPreferences preferences) async {
    await _store.save(preferences);
    final settings = _settings;
    if (settings == null || _currentUserId?.call() == null) {
      return;
    }
    if (_serverPreviews == preferences.showPreviews &&
        _unsentPreviews == null) {
      return;
    }
    _unsentPreviews = preferences.showPreviews;
    await settings.saveShowPreviews(show: preferences.showPreviews);
    _serverPreviews = preferences.showPreviews;
    _unsentPreviews = null;
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
