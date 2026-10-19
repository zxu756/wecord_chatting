import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/feature_flags/feature_flags_models.dart';

/// Asks the server which flags are on for this person and what the lowest
/// allowed version is (`get_my_flags`, migration 202610240600). Works signed
/// out too, then with the minimum version and the flags that are on for
/// everybody.
abstract interface class FeatureFlagsRepository {
  Future<FeatureFlagSnapshot> fetch({
    required String platform,
    required String version,
  });
}

class SupabaseFeatureFlagsRepository implements FeatureFlagsRepository {
  const SupabaseFeatureFlagsRepository(this._rpc);

  final CircleRpc _rpc;

  @override
  Future<FeatureFlagSnapshot> fetch({
    required String platform,
    required String version,
  }) async {
    final result = await _rpc('get_my_flags', {
      'client_platform': platform,
      'client_version': version,
    });
    return FeatureFlagSnapshot.fromJson(result);
  }
}

final featureFlagsRepositoryProvider = Provider<FeatureFlagsRepository>((ref) {
  return SupabaseFeatureFlagsRepository(ref.watch(circleRpcProvider));
});

/// What the app last heard, kept on the device so the next start (and a
/// start without a connection) has something to go on.
class CachedFeatureFlags {
  const CachedFeatureFlags({required this.snapshot, this.userId});

  final FeatureFlagSnapshot snapshot;

  /// Whose flags these are; the flags of somebody else are not used.
  final String? userId;
}

abstract interface class FeatureFlagCache {
  Future<CachedFeatureFlags?> load();

  Future<void> save(CachedFeatureFlags cached);
}

/// Never throws: a device that cannot store anything just starts from the
/// defaults each time.
class SharedPreferencesFeatureFlagCache implements FeatureFlagCache {
  const SharedPreferencesFeatureFlagCache();

  static const _key = 'wecord.feature_flags.v1';

  @override
  Future<CachedFeatureFlags?> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final text = preferences.getString(_key);
      if (text == null) {
        return null;
      }
      final json = jsonDecode(text);
      if (json is! Map) {
        return null;
      }
      final user = json['user'];
      return CachedFeatureFlags(
        snapshot: FeatureFlagSnapshot.fromJson(json),
        userId: user is String ? user : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(CachedFeatureFlags cached) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _key,
        jsonEncode({...cached.snapshot.toJson(), 'user': cached.userId}),
      );
    } catch (_) {
      // Nothing to do: the next start asks again.
    }
  }
}

class InMemoryFeatureFlagCache implements FeatureFlagCache {
  InMemoryFeatureFlagCache([this.cached]);

  CachedFeatureFlags? cached;

  @override
  Future<CachedFeatureFlags?> load() async => cached;

  @override
  Future<void> save(CachedFeatureFlags cached) async => this.cached = cached;
}

final featureFlagCacheProvider = Provider<FeatureFlagCache>(
  (ref) => const SharedPreferencesFeatureFlagCache(),
);
