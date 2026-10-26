import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/local_cipher_provider.dart';

final recentSearchesStoreProvider = Provider<RecentSearchesStore>((ref) {
  return SharedPreferencesRecentSearchesStore(
    cipher: ref.watch(localCipherProvider),
  );
});

/// The searches run on this device, newest first.
final recentSearchesProvider =
    NotifierProvider<RecentSearchesController, List<String>>(
      RecentSearchesController.new,
    );

/// Where recent searches are kept on this device.
abstract interface class RecentSearchesStore {
  Future<List<String>> load();

  Future<void> save(List<String> searches);
}

/// Recent searches in shared preferences, encrypted with the device key
/// (G8): what someone searched for is as private as what they read. An
/// earlier version kept them as a plain list under another name; that list
/// is read once, moved over and removed.
class SharedPreferencesRecentSearchesStore implements RecentSearchesStore {
  SharedPreferencesRecentSearchesStore({LocalCipher? cipher})
    : cipher = cipher ?? sessionLocalCipher;

  final LocalCipher cipher;

  static const _key = 'wecord.search.recent.v2';
  static const _legacyKey = 'wecord.search.recent';

  @override
  Future<List<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final sealed = preferences.getString(_key);
    if (sealed != null) {
      final text = await cipher.open(sealed);
      if (text != null) {
        try {
          return [
            for (final item in jsonDecode(text) as List<dynamic>) '$item',
          ];
        } on Object {
          return const [];
        }
      }
    }
    final legacy = preferences.getStringList(_legacyKey);
    if (legacy != null) {
      await save(legacy);
      await preferences.remove(_legacyKey);
      return legacy;
    }
    return const [];
  }

  @override
  Future<void> save(List<String> searches) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_legacyKey);
    if (searches.isEmpty) {
      await preferences.remove(_key);
      return;
    }
    await preferences.setString(_key, await cipher.seal(jsonEncode(searches)));
  }
}

class RecentSearchesController extends Notifier<List<String>> {
  /// How many searches are kept.
  static const limit = 10;

  @override
  List<String> build() {
    unawaited(_load());
    return const [];
  }

  Future<void> _load() async {
    try {
      final loaded = await ref.read(recentSearchesStoreProvider).load();
      // Searches added while loading come first.
      state = _normalize([...state, ...loaded]);
    } catch (_) {
      // Recent searches are a convenience.
    }
  }

  /// Puts [query] first (once).
  void add(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _set(_normalize([trimmed, ...state]));
  }

  void remove(String query) {
    _set([
      for (final item in state)
        if (item != query) item,
    ]);
  }

  void clear() => _set(const []);

  void _set(List<String> searches) {
    state = searches;
    unawaited(
      ref
          .read(recentSearchesStoreProvider)
          .save(searches)
          .catchError((Object _) {}),
    );
  }

  static List<String> _normalize(List<String> searches) {
    final seen = <String>{};
    return [
      for (final search in searches)
        if (search.trim().isNotEmpty && seen.add(search.trim().toLowerCase()))
          search.trim(),
    ].take(limit).toList(growable: false);
  }
}
