import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';

/// A transcript kept on this device.
class CachedTranscript {
  const CachedTranscript({
    required this.text,
    required this.engine,
    required this.savedAt,
  });

  static CachedTranscript? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final text = json['t'];
    if (text is! String || text.isEmpty) {
      return null;
    }
    final engine = TranscribeEngine.values.asNameMap()[json['e']];
    final savedAt = json['at'];
    return CachedTranscript(
      text: text,
      engine: engine ?? TranscribeEngine.onDevice,
      savedAt: savedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(savedAt, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String text;
  final TranscribeEngine engine;
  final DateTime savedAt;

  Map<String, Object?> toJson() => {
    't': text,
    'e': engine.name,
    'at': savedAt.millisecondsSinceEpoch,
  };
}

/// Transcripts by message id. They are the reader's own: kept on this
/// device only (never sent to the server) and per signed-in user.
abstract interface class TranscriptCache {
  Future<CachedTranscript?> read(String messageId);

  Future<void> write(String messageId, CachedTranscript transcript);

  Future<void> remove(String messageId);

  /// How many bytes the transcripts take on this device.
  Future<int> totalBytes();

  /// Forgets every transcript.
  Future<void> clear();

  /// Forgets transcripts made before [cutoff]; returns how many bytes that
  /// freed.
  Future<int> removeOlderThan(DateTime cutoff);
}

/// Transcripts in shared preferences, one entry per signed-in user, newest
/// [maxEntries] kept. Without a user (nobody signed in) nothing is stored.
class SharedPreferencesTranscriptCache implements TranscriptCache {
  SharedPreferencesTranscriptCache({this.userId, this.maxEntries = 300});

  final String? userId;
  final int maxEntries;
  Map<String, CachedTranscript>? _entries;
  Future<void> _saving = Future.value();

  String get _key => 'wecord.transcripts.$userId';

  Future<Map<String, CachedTranscript>> _load() async {
    final loaded = _entries;
    if (loaded != null) {
      return loaded;
    }
    final entries = <String, CachedTranscript>{};
    if (userId != null) {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_key);
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            for (final MapEntry(:key, :value) in decoded.entries) {
              final transcript = CachedTranscript.fromJson(value);
              if (key is String && transcript != null) {
                entries[key] = transcript;
              }
            }
          }
        } on FormatException {
          // A damaged entry is dropped; transcripts can be made again.
        }
      }
    }
    // Entries added while loading win.
    return _entries ??= entries;
  }

  Future<void> _save(Map<String, CachedTranscript> entries) {
    final id = userId;
    if (id == null) {
      return Future.value();
    }
    final snapshot = jsonEncode({
      for (final MapEntry(:key, :value) in entries.entries) key: value.toJson(),
    });
    // One write after the other, so an older snapshot never lands last.
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
  Future<CachedTranscript?> read(String messageId) async =>
      (await _load())[messageId];

  @override
  Future<void> write(String messageId, CachedTranscript transcript) async {
    final entries = await _load();
    entries[messageId] = transcript;
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
  Future<void> remove(String messageId) async {
    final entries = await _load();
    if (entries.remove(messageId) != null) {
      await _save(entries);
    }
  }

  @override
  Future<int> totalBytes() async => _size(await _load());

  @override
  Future<void> clear() async {
    final entries = await _load();
    if (entries.isNotEmpty) {
      entries.clear();
      await _save(entries);
    }
  }

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

  static int _size(Map<String, CachedTranscript> entries) {
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

/// Transcripts in memory (tests, and nobody signed in).
class InMemoryTranscriptCache implements TranscriptCache {
  InMemoryTranscriptCache([Map<String, CachedTranscript>? entries])
    : entries = entries ?? {};

  final Map<String, CachedTranscript> entries;

  @override
  Future<CachedTranscript?> read(String messageId) async => entries[messageId];

  @override
  Future<void> write(String messageId, CachedTranscript transcript) async {
    entries[messageId] = transcript;
  }

  @override
  Future<void> remove(String messageId) async {
    entries.remove(messageId);
  }

  @override
  Future<int> totalBytes() async =>
      entries.values.fold<int>(0, (sum, value) => sum + value.text.length);

  @override
  Future<void> clear() async => entries.clear();

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
final transcriptUserIdProvider = Provider<String?>((ref) {
  try {
    return ref.watch(authStateProvider.select((state) => state.value?.id)) ??
        ref.read(authRepositoryProvider).currentUser?.id;
  } on Object {
    return null;
  }
});

final transcriptCacheProvider = Provider<TranscriptCache>((ref) {
  return SharedPreferencesTranscriptCache(
    userId: ref.watch(transcriptUserIdProvider),
  );
});
