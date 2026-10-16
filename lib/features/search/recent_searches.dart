import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final recentSearchesStoreProvider = Provider<RecentSearchesStore>((ref) {
  return const SharedPreferencesRecentSearchesStore();
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

class SharedPreferencesRecentSearchesStore implements RecentSearchesStore {
  const SharedPreferencesRecentSearchesStore();

  static const _key = 'wecord.search.recent';

  @override
  Future<List<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(_key) ?? const [];
  }

  @override
  Future<void> save(List<String> searches) async {
    final preferences = await SharedPreferences.getInstance();
    if (searches.isEmpty) {
      await preferences.remove(_key);
      return;
    }
    await preferences.setStringList(_key, searches);
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
