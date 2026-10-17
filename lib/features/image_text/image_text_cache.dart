import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/auth/auth_repository.dart';

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
}

/// The cache key of a picture: its message, or where it is stored when it
/// has none (a picture opened from a circle post, say).
String imageTextKey({String? messageId, required String storagePath}) =>
    messageId != null && messageId.isNotEmpty
    ? 'm:$messageId'
    : 'f:$storagePath';

/// Texts in shared preferences, one entry per signed-in user, the newest
/// [maxEntries] kept. Without a user (nobody signed in) nothing is stored.
class SharedPreferencesImageTextCache implements ImageTextCache {
  SharedPreferencesImageTextCache({this.userId, this.maxEntries = 200});

  final String? userId;
  final int maxEntries;
  Map<String, CachedImageText>? _entries;
  Future<void> _saving = Future.value();

  String get _key => 'wecord.image_text.$userId';

  Future<Map<String, CachedImageText>> _load() async {
    final loaded = _entries;
    if (loaded != null) {
      return loaded;
    }
    final entries = <String, CachedImageText>{};
    if (userId != null) {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_key);
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
    return _entries ??= entries;
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
            await preferences.setString(_key, snapshot);
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
  );
});
