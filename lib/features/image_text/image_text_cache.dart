import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/local_cipher_provider.dart';

/// The text read from a picture, kept on this device. An empty [text] means
/// the picture was read and holds no text.
class CachedImageText {
  const CachedImageText({required this.text, required this.savedAt});

  static CachedImageText? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final text = json['t'];
    if (text is! String) {
      return null;
    }
    final at = json['at'];
    return CachedImageText(
      text: text,
      savedAt: DateTime.fromMillisecondsSinceEpoch(
        at is int ? at : 0,
        isUtc: true,
      ),
    );
  }

  final String text;
  final DateTime savedAt;

  Map<String, Object?> toJson() => {
    't': text,
    'at': savedAt.millisecondsSinceEpoch,
  };
}

/// Text read from pictures, by message. It is the reader's own: kept on this
/// device only (never sent to the server) and per signed-in user.
abstract interface class ImageTextCache {
  Future<CachedImageText?> read(String key);

  Future<void> write(String key, CachedImageText text);

  Future<void> clear();

  Future<void> remove(String key);

  /// How many bytes the texts take on this device.
  Future<int> totalBytes();

  /// Forgets texts read before [cutoff]; returns how many bytes that freed.
  Future<int> removeOlderThan(DateTime cutoff);
}

/// The cache key of a picture: its message, or where it is stored when it
/// has none (a picture opened from a circle post, say).
String imageTextKey({String? messageId, required String storagePath}) =>
    messageId != null && messageId.isNotEmpty
    ? 'm:$messageId'
    : 'f:$storagePath';

/// Texts in shared preferences, one entry per signed-in user, the newest
/// [maxEntries] kept. Without a user (nobody signed in) nothing is stored.
/// What is stored is encrypted with the device key (G8); texts saved before
/// that are read as they are and written back encrypted.
class SharedPreferencesImageTextCache implements ImageTextCache {
  SharedPreferencesImageTextCache({
    this.userId,
    this.maxEntries = 200,
    LocalCipher? cipher,
  }) : cipher = cipher ?? sessionLocalCipher;

  final String? userId;
  final int maxEntries;
  final LocalCipher cipher;
  Map<String, CachedImageText>? _entries;
  Future<void> _saving = Future.value();

  String get _key => 'wecord.image_text.$userId';

  Future<Map<String, CachedImageText>> _load() async {
    final loaded = _entries;
    if (loaded != null) {
      return loaded;
    }
    final entries = <String, CachedImageText>{};
    var legacy = false;
    if (userId != null) {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString(_key);
      final opened = await cipher.read(stored);
      legacy = opened.legacy;
      final raw = opened.text;
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            for (final MapEntry(:key, :value) in decoded.entries) {
              final text = CachedImageText.fromJson(value);
              if (key is String && text != null) {
                entries[key] = text;
              }
            }
          }
        } on FormatException {
          // A damaged entry is dropped; the text can be read again.
        }
      }
    }
    final result = _entries ??= entries;
    if (legacy && result.isNotEmpty) {
      // Saved in the clear by an earlier version: written back encrypted.
      unawaited(_save(result));
    }
    return result;
  }

  Future<void> _save(Map<String, CachedImageText> entries) {
    if (userId == null) {
      return Future.value();
    }
    final snapshot = jsonEncode({
      for (final MapEntry(:key, :value) in entries.entries) key: value.toJson(),
    });
    return _saving = _saving
        .then((_) async {
          final preferences = await SharedPreferences.getInstance();
          if (entries.isEmpty) {
            await preferences.remove(_key);
          } else {
            await preferences.setString(_key, await cipher.seal(snapshot));
          }
        })
        .catchError((Object _) {});
  }

  @override
  Future<CachedImageText?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(String key, CachedImageText text) async {
    final entries = await _load();
    entries[key] = text;
    if (entries.length > maxEntries) {
      final oldest = entries.entries.toList()
        ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
      for (final entry in oldest.take(entries.length - maxEntries)) {
        entries.remove(entry.key);
      }
    }
    await _save(entries);
  }

  @override
  Future<void> clear() async {
    final entries = await _load();
    entries.clear();
    await _save(entries);
  }

  @override
  Future<void> remove(String key) async {
    final entries = await _load();
    if (entries.remove(key) != null) {
      await _save(entries);
    }
  }

  @override
  Future<int> totalBytes() async => _size(await _load());

  @override
  Future<int> removeOlderThan(DateTime cutoff) async {
    final entries = await _load();
    final before = _size(entries);
    entries.removeWhere((_, value) => value.savedAt.isBefore(cutoff));
    if (_size(entries) == before) {
      return 0;
    }
    await _save(entries);
    return before - _size(entries);
  }

  static int _size(Map<String, CachedImageText> entries) {
    if (entries.isEmpty) {
      return 0;
    }
    return utf8
        .encode(
          jsonEncode({
            for (final MapEntry(:key, :value) in entries.entries)
              key: value.toJson(),
          }),
        )
        .length;
  }
}

/// Texts in memory (tests).
class InMemoryImageTextCache implements ImageTextCache {
  InMemoryImageTextCache([Map<String, CachedImageText>? entries])
    : entries = entries ?? {};

  final Map<String, CachedImageText> entries;

  @override
  Future<CachedImageText?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, CachedImageText text) async {
    entries[key] = text;
  }

  @override
  Future<void> clear() async => entries.clear();

  @override
  Future<void> remove(String key) async {
    entries.remove(key);
  }

  @override
  Future<int> totalBytes() async =>
      entries.values.fold<int>(0, (sum, value) => sum + value.text.length);

  @override
  Future<int> removeOlderThan(DateTime cutoff) async {
    var freed = 0;
    entries.removeWhere((_, value) {
      final old = value.savedAt.isBefore(cutoff);
      if (old) {
        freed += value.text.length;
      }
      return old;
    });
    return freed;
  }
}

/// The signed-in user's id, or null when nobody is (or sign-in isn't set up,
/// as in tests).
final imageTextUserIdProvider = Provider<String?>((ref) {
  try {
    return ref.watch(authStateProvider.select((state) => state.value?.id)) ??
        ref.read(authRepositoryProvider).currentUser?.id;
  } on Object {
    return null;
  }
});

final imageTextCacheProvider = Provider<ImageTextCache>((ref) {
  return SharedPreferencesImageTextCache(
    userId: ref.watch(imageTextUserIdProvider),
    cipher: ref.watch(localCipherProvider),
  );
});
