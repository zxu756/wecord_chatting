import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'wecord.appearance.theme_mode';

/// Where the app's light / dark choice is kept; tests swap in memory.
abstract interface class ThemeModeStore {
  Future<ThemeMode?> load();

  Future<void> save(ThemeMode mode);
}

class SharedPreferencesThemeModeStore implements ThemeModeStore {
  const SharedPreferencesThemeModeStore();

  @override
  Future<ThemeMode?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final name = preferences.getString(_themeModeKey);
    return ThemeMode.values.where((mode) => mode.name == name).firstOrNull;
  }

  @override
  Future<void> save(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeModeKey, mode.name);
  }
}

class InMemoryThemeModeStore implements ThemeModeStore {
  InMemoryThemeModeStore([this._mode]);

  ThemeMode? _mode;

  @override
  Future<ThemeMode?> load() async => _mode;

  @override
  Future<void> save(ThemeMode mode) async => _mode = mode;
}

final themeModeStoreProvider = Provider<ThemeModeStore>(
  (ref) => const SharedPreferencesThemeModeStore(),
);

/// System, light or dark, remembered on this device. Follows the system
/// until the saved choice has loaded.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  var _changed = false;

  @override
  ThemeMode build() {
    ref.read(themeModeStoreProvider).load().then((mode) {
      // A choice made while loading wins over the saved one.
      if (mode != null && !_changed) {
        state = mode;
      }
    }, onError: (Object _) {});
    return ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    _changed = true;
    state = mode;
    try {
      await ref.read(themeModeStoreProvider).save(mode);
    } on Object {
      // Still applies for this session.
    }
  }
}
