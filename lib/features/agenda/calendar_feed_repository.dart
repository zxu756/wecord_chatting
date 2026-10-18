import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// What the server knows about the person's calendar subscription link. It
/// never holds the link itself: only a hash of its secret is stored.
class CalendarFeedSettings {
  const CalendarFeedSettings({
    this.enabled = false,
    this.includeContent = false,
    this.createdAt,
    this.lastUsedAt,
  });

  factory CalendarFeedSettings.fromJson(Map<String, dynamic> json) {
    return CalendarFeedSettings(
      enabled: json['enabled'] == true,
      includeContent: json['include_content'] == true,
      createdAt: DateTime.tryParse('${json['created_at']}'),
      lastUsedAt: DateTime.tryParse('${json['last_used_at']}'),
    );
  }

  /// A link exists.
  final bool enabled;

  /// The calendar shows titles and details, not only times and names.
  final bool includeContent;
  final DateTime? createdAt;

  /// When a calendar app last fetched it.
  final DateTime? lastUsedAt;
}

abstract interface class CalendarFeedRepository {
  Future<CalendarFeedSettings> settings();

  /// Makes a new link secret (which ends the old link) and returns it. The
  /// server cannot show it again.
  Future<String> createToken({
    required bool includeContent,
    required int utcOffsetMinutes,
    required String language,
  });

  Future<void> setOptions({
    required bool includeContent,
    required int utcOffsetMinutes,
    required String language,
  });

  /// Turns the subscription off; its link stops working.
  Future<void> delete();
}

final calendarFeedRepositoryProvider = Provider<CalendarFeedRepository>((ref) {
  try {
    return SupabaseCalendarFeedRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedCalendarFeedRepository();
  }
});

class SupabaseCalendarFeedRepository implements CalendarFeedRepository {
  const SupabaseCalendarFeedRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<CalendarFeedSettings> settings() async {
    final json = await _client.rpc<Map<String, dynamic>>(
      'get_calendar_feed_settings',
    );
    return CalendarFeedSettings.fromJson(json);
  }

  @override
  Future<String> createToken({
    required bool includeContent,
    required int utcOffsetMinutes,
    required String language,
  }) async {
    return await _client.rpc<String>(
      'create_calendar_feed_token',
      params: {
        'p_include_content': includeContent,
        'p_utc_offset_minutes': utcOffsetMinutes,
        'p_language': language,
      },
    );
  }

  @override
  Future<void> setOptions({
    required bool includeContent,
    required int utcOffsetMinutes,
    required String language,
  }) async {
    await _client.rpc<dynamic>(
      'set_calendar_feed_options',
      params: {
        'p_include_content': includeContent,
        'p_utc_offset_minutes': utcOffsetMinutes,
        'p_language': language,
      },
    );
  }

  @override
  Future<void> delete() async {
    await _client.rpc<dynamic>('delete_calendar_feed_token');
  }
}

class UninitializedCalendarFeedRepository implements CalendarFeedRepository {
  const UninitializedCalendarFeedRepository();

  @override
  Future<CalendarFeedSettings> settings() async => const CalendarFeedSettings();

  @override
  Future<String> createToken({
    required bool includeContent,
    required int utcOffsetMinutes,
    required String language,
  }) => throw StateError('Supabase must be initialized to make a link.');

  @override
  Future<void> setOptions({
    required bool includeContent,
    required int utcOffsetMinutes,
    required String language,
  }) async {}

  @override
  Future<void> delete() async {}
}

/// Keeps the link secret on this device, so "Copy link" works after the
/// page was closed. Other devices have to reset the link to get one.
abstract interface class CalendarFeedTokenStore {
  Future<String?> read(String userId);
  Future<void> write(String userId, String token);
  Future<void> clear(String userId);
}

final calendarFeedTokenStoreProvider = Provider<CalendarFeedTokenStore>(
  (ref) => const PreferencesCalendarFeedTokenStore(),
);

class PreferencesCalendarFeedTokenStore implements CalendarFeedTokenStore {
  const PreferencesCalendarFeedTokenStore();

  static String _key(String userId) => 'agenda.calendar_feed_token.$userId';

  @override
  Future<String?> read(String userId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_key(userId));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String userId, String token) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_key(userId), token);
    } on Object {
      // The link is still shown now; it just can't be shown again later.
    }
  }

  @override
  Future<void> clear(String userId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_key(userId));
    } on Object {
      // Nothing to forget.
    }
  }
}

/// `<SUPABASE_URL>/functions/v1/calendar-feed/<token>.ics`.
Uri calendarFeedUrl(Uri supabaseUrl, String token) {
  final base = supabaseUrl.toString().replaceFirst(RegExp(r'/+$'), '');
  return Uri.parse('$base/functions/v1/calendar-feed/$token.ics');
}

/// The same address with the `webcal` scheme, which Apple Calendar (and
/// other calendar apps) open as "subscribe to this calendar".
Uri calendarFeedSubscribeUrl(Uri feedUrl) => feedUrl.replace(scheme: 'webcal');

final calendarFeedSettingsProvider =
    FutureProvider.autoDispose<CalendarFeedSettings>(
      (ref) => ref.watch(calendarFeedRepositoryProvider).settings(),
    );
