import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the lock keeps its settings on this device: the app lock switch and
/// timeout, the PIN's salted hash, the failed attempts, the chats that are
/// locked and whether they are hidden, and the secret code's salted hash.
///
/// Read at once and written behind: the app reads everything before it draws
/// the first frame (a locked app must never show a flash of its content), so
/// [read] is synchronous. Nothing here leaves the device.
abstract interface class LockStorage {
  String? read(String key);

  /// Keeps [value] under [key]; null removes it. A failure to write is
  /// swallowed: the lock still works for this run.
  Future<void> write(String key, String? value);

  /// Every key kept, for wiping.
  Iterable<String> get keys;
}

const lockStoragePrefix = 'wecord.lock.';

/// The device's SharedPreferences (the browser's localStorage on the web),
/// read once at start.
class SharedPreferencesLockStorage implements LockStorage {
  SharedPreferencesLockStorage._(this._preferences, this._cache);

  /// Reads the saved settings. An unreadable store is an empty one.
  static Future<SharedPreferencesLockStorage> open() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final cache = <String, String>{
        for (final key in preferences.getKeys())
          if (key.startsWith(lockStoragePrefix) &&
              preferences.getString(key) != null)
            key.substring(lockStoragePrefix.length): preferences.getString(
              key,
            )!,
      };
      return SharedPreferencesLockStorage._(preferences, cache);
    } on Object {
      return SharedPreferencesLockStorage._(null, {});
    }
  }

  final SharedPreferences? _preferences;
  final Map<String, String> _cache;

  @override
  String? read(String key) => _cache[key];

  @override
  Iterable<String> get keys => _cache.keys.toList();

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    try {
      final preferences = _preferences;
      if (preferences == null) {
        return;
      }
      if (value == null) {
        await preferences.remove('$lockStoragePrefix$key');
      } else {
        await preferences.setString('$lockStoragePrefix$key', value);
      }
    } on Object {
      // Still applies for this run.
    }
  }
}

/// Keeps everything in memory; the default before the app opens the device's
/// store, and what tests use.
class InMemoryLockStorage implements LockStorage {
  InMemoryLockStorage([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  @override
  String? read(String key) => _values[key];

  @override
  Iterable<String> get keys => _values.keys.toList();

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}

/// The device's store; the app overrides it with the one it opened before
/// the first frame.
final lockStorageProvider = Provider<LockStorage>(
  (ref) => InMemoryLockStorage(),
);
