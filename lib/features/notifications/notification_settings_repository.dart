import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/notifications/notification_settings.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// The person's notification settings on the server (table
/// `user_notification_settings`, owner-only by row level security).
abstract interface class NotificationSettingsRepository {
  /// The saved settings; null while the person has no row yet.
  Future<NotificationSettings?> load();

  /// Saves the quiet hours switch, window, weekdays and exceptions.
  Future<void> saveQuietHours(NotificationSettings settings);

  /// Saves the message previews switch (this is also how the device's own
  /// value is moved to the server the first time).
  Future<void> saveShowPreviews({required bool show});

  /// Saves the IANA time zone of this device.
  Future<void> saveTimeZone(String timeZone);

  /// Adds or removes one friend from the important contacts.
  Future<void> setImportantContact(String friendId, {required bool important});
}

class SupabaseNotificationSettingsRepository
    implements NotificationSettingsRepository {
  const SupabaseNotificationSettingsRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Sign in to change notification settings.');
    }
    return id;
  }

  @override
  Future<NotificationSettings?> load() async {
    final row = await _client
        .from('user_notification_settings')
        .select()
        .eq('user_id', _userId)
        .maybeSingle();
    return row == null ? null : NotificationSettings.fromRow(row);
  }

  // An upsert of only the columns given: the others of an existing row are
  // left as they are, and a new row gets the defaults.
  Future<void> _upsert(Map<String, dynamic> columns) async {
    await _client.from('user_notification_settings').upsert({
      'user_id': _userId,
      ...columns,
    }, onConflict: 'user_id');
  }

  @override
  Future<void> saveQuietHours(NotificationSettings settings) {
    return _upsert(settings.quietColumns());
  }

  @override
  Future<void> saveShowPreviews({required bool show}) {
    return _upsert({'show_previews': show});
  }

  @override
  Future<void> saveTimeZone(String timeZone) {
    return _upsert({'timezone': timeZone});
  }

  @override
  Future<void> setImportantContact(
    String friendId, {
    required bool important,
  }) async {
    await _client.rpc(
      'set_important_contact',
      params: {'target_friend_id': friendId, 'important': important},
    );
  }
}

/// Keeps the settings in memory: stands in before Supabase is set up (tests)
/// and for tests that need a server to look at.
class InMemoryNotificationSettingsRepository
    implements NotificationSettingsRepository {
  InMemoryNotificationSettingsRepository([this.settings]);

  /// What the "server" holds; null for a person without a row.
  NotificationSettings? settings;

  /// Makes every call fail, to test the errors.
  Object? failWith;

  var saves = 0;

  void _check() {
    final failure = failWith;
    if (failure != null) {
      throw failure;
    }
  }

  NotificationSettings get _row => settings ?? NotificationSettings.defaults;

  @override
  Future<NotificationSettings?> load() async {
    _check();
    return settings;
  }

  @override
  Future<void> saveQuietHours(NotificationSettings next) async {
    _check();
    saves++;
    settings = next.copyWith(
      timezone: _row.timezone,
      vipUserIds: _row.vipUserIds,
      showPreviews: _row.showPreviews,
    );
  }

  @override
  Future<void> saveShowPreviews({required bool show}) async {
    _check();
    saves++;
    settings = _row.copyWith(showPreviews: show);
  }

  @override
  Future<void> saveTimeZone(String timeZone) async {
    _check();
    saves++;
    settings = _row.copyWith(timezone: timeZone);
  }

  @override
  Future<void> setImportantContact(
    String friendId, {
    required bool important,
  }) async {
    _check();
    saves++;
    final vips = {..._row.vipUserIds};
    important ? vips.add(friendId) : vips.remove(friendId);
    settings = _row.copyWith(vipUserIds: vips);
  }
}

final notificationSettingsRepositoryProvider =
    Provider<NotificationSettingsRepository>((ref) {
      try {
        return SupabaseNotificationSettingsRepository(
          ref.watch(supabaseClientProvider),
        );
      } on ProviderException {
        return InMemoryNotificationSettingsRepository();
      }
    });
