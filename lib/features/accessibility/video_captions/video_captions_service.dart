import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_models.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';

/// Why captions could not be made for a video.
enum VideoCaptionFailure {
  /// The video has no sound to turn into words.
  noSpeech,

  /// Speech recognition is turned off for WeCord in the system settings.
  notAuthorized,

  /// The device cannot recognize this language without sending the sound to
  /// a server, which captions never do.
  language,

  /// The system cannot open the video's sound.
  unreadable,
  failed,
}

class VideoCaptionException implements Exception {
  const VideoCaptionException(this.kind);

  final VideoCaptionFailure kind;

  @override
  String toString() => 'VideoCaptionException($kind)';
}

/// Makes captions for a video from its sound, on this device: the same
/// system speech recognizer that transcribes voice messages, so the sound
/// never leaves the phone or the Mac. Tests swap in a fake.
abstract interface class VideoCaptionMaker {
  /// Whether this platform can make captions at all (iPhone and Mac).
  bool get available;

  /// The captions of [file]; the video is downloaded first when it is not
  /// kept on the device yet.
  Future<VideoCaptions> make(
    PreviewFile file, {
    required Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  });
}

/// Where captions cannot be made (the web, Android, Windows, Linux).
class UnsupportedVideoCaptionMaker implements VideoCaptionMaker {
  const UnsupportedVideoCaptionMaker();

  @override
  bool get available => false;

  @override
  Future<VideoCaptions> make(
    PreviewFile file, {
    required Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) => Future.error(const VideoCaptionException(VideoCaptionFailure.failed));
}

/// The system's speech recognizer through the Runner apps' `TranscribePlugin`
/// (channel `wecord/transcribe`), asked for the words with their times
/// (`segments`) of a video's sound (`video`), on the device only.
class NativeVideoCaptionMaker implements VideoCaptionMaker {
  NativeVideoCaptionMaker({
    required this.fetcher,
    this._channel = const MethodChannel('wecord/transcribe'),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final FileFetcher fetcher;
  final MethodChannel _channel;
  final DateTime Function() _clock;

  @override
  bool get available => true;

  @override
  Future<VideoCaptions> make(
    PreviewFile file, {
    required Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async {
    final path = await fetcher.download(
      file,
      url: url,
      onProgress: onProgress,
      cancel: cancel,
    );
    final Map<String, Object?>? result;
    try {
      result = await _channel.invokeMapMethod<String, Object?>('transcribe', {
        'path': path,
        'locales': speechLocales(),
        // Captions never go to a server: a language the device cannot
        // recognize on its own gets none.
        'allowServer': false,
        'video': true,
        'segments': true,
      });
    } on MissingPluginException {
      throw const VideoCaptionException(VideoCaptionFailure.failed);
    } on PlatformException catch (error) {
      throw VideoCaptionException(switch (error.code) {
        'not_authorized' => VideoCaptionFailure.notAuthorized,
        'no_speech' => VideoCaptionFailure.noSpeech,
        'unreadable' => VideoCaptionFailure.unreadable,
        'needs_server' || 'unsupported_locale' => VideoCaptionFailure.language,
        _ => VideoCaptionFailure.failed,
      });
    }
    final cues = cuesFromSegments(parseSpokenSegments(result?['segments']));
    if (cues.isEmpty) {
      throw const VideoCaptionException(VideoCaptionFailure.noSpeech);
    }
    return VideoCaptions(
      cues: cues,
      locale: result?['locale'] as String? ?? '',
      savedAt: _clock().toUtc(),
    );
  }
}

/// The words the plugin sent: `[{t: seconds in, d: seconds long, s: text}]`.
List<SpokenSegment> parseSpokenSegments(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  final segments = <SpokenSegment>[];
  for (final item in raw) {
    if (item is! Map) {
      continue;
    }
    final start = item['t'];
    final duration = item['d'];
    final text = item['s'];
    if (start is! num || duration is! num || text is! String) {
      continue;
    }
    segments.add(
      SpokenSegment(
        start: Duration(milliseconds: (start * 1000).round()),
        duration: Duration(milliseconds: (duration * 1000).round()),
        text: text,
      ),
    );
  }
  return segments;
}

/// Captions made on this device, by video (its stored object's key). They are
/// the viewer's own: kept here only (never sent to the server) and per
/// signed-in user.
abstract interface class VideoCaptionCache {
  Future<VideoCaptions?> read(String key);

  Future<void> write(String key, VideoCaptions captions);

  Future<void> remove(String key);

  Future<void> clear();

  /// How many bytes the captions take on this device.
  Future<int> totalBytes();

  /// Forgets captions made before [cutoff]; returns how many bytes that
  /// freed.
  Future<int> removeOlderThan(DateTime cutoff);
}

/// Captions in shared preferences, one entry per signed-in user, the newest
/// [maxEntries] kept. Without a user nothing is stored.
class SharedPreferencesVideoCaptionCache implements VideoCaptionCache {
  SharedPreferencesVideoCaptionCache({this.userId, this.maxEntries = 20});

  final String? userId;
  final int maxEntries;
  Map<String, VideoCaptions>? _entries;
  Future<void> _saving = Future.value();

  String get _key => 'wecord.video_captions.$userId';

  Future<Map<String, VideoCaptions>> _load() async {
    final loaded = _entries;
    if (loaded != null) {
      return loaded;
    }
    final entries = <String, VideoCaptions>{};
    if (userId != null) {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_key);
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            for (final MapEntry(:key, :value) in decoded.entries) {
              final captions = VideoCaptions.fromJson(value);
              if (key is String && captions != null) {
                entries[key] = captions;
              }
            }
          }
        } on FormatException {
          // Damaged: captions can be made again.
        }
      }
    }
    return _entries ??= entries;
  }

  static String _encode(Map<String, VideoCaptions> entries) => jsonEncode({
    for (final MapEntry(:key, :value) in entries.entries) key: value.toJson(),
  });

  Future<void> _save(Map<String, VideoCaptions> entries) {
    if (userId == null) {
      return Future.value();
    }
    final snapshot = _encode(entries);
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
  Future<VideoCaptions?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(String key, VideoCaptions captions) async {
    final entries = await _load();
    entries.remove(key);
    entries[key] = captions;
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
  Future<void> remove(String key) async {
    final entries = await _load();
    if (entries.remove(key) != null) {
      await _save(entries);
    }
  }

  @override
  Future<void> clear() async {
    final entries = await _load();
    if (entries.isNotEmpty) {
      entries.clear();
      await _save(entries);
    }
  }

  @override
  Future<int> totalBytes() async {
    final entries = await _load();
    return entries.isEmpty ? 0 : utf8.encode(_encode(entries)).length;
  }

  @override
  Future<int> removeOlderThan(DateTime cutoff) async {
    final entries = await _load();
    final before = entries.isEmpty ? 0 : utf8.encode(_encode(entries)).length;
    entries.removeWhere((_, value) => value.savedAt.isBefore(cutoff));
    if (entries.isEmpty && before == 0) {
      return 0;
    }
    final after = entries.isEmpty ? 0 : utf8.encode(_encode(entries)).length;
    if (after == before) {
      return 0;
    }
    await _save(entries);
    return before - after;
  }
}

/// Captions in memory (tests, and nobody signed in).
class InMemoryVideoCaptionCache implements VideoCaptionCache {
  InMemoryVideoCaptionCache([Map<String, VideoCaptions>? entries])
    : entries = entries ?? {};

  final Map<String, VideoCaptions> entries;

  @override
  Future<VideoCaptions?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, VideoCaptions captions) async {
    entries[key] = captions;
  }

  @override
  Future<void> remove(String key) async {
    entries.remove(key);
  }

  @override
  Future<void> clear() async => entries.clear();

  @override
  Future<int> totalBytes() async => entries.values.fold<int>(
    0,
    (sum, value) =>
        sum + value.cues.fold<int>(0, (inner, cue) => inner + cue.text.length),
  );

  @override
  Future<int> removeOlderThan(DateTime cutoff) async {
    var freed = 0;
    entries.removeWhere((_, value) {
      final old = value.savedAt.isBefore(cutoff);
      if (old) {
        freed += value.cues.fold<int>(0, (sum, cue) => sum + cue.text.length);
      }
      return old;
    });
    return freed;
  }
}

bool get _isApple =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// How captions are made on this platform: on the device on iOS and macOS,
/// not at all elsewhere.
final videoCaptionMakerProvider = Provider<VideoCaptionMaker>((ref) {
  if (_isApple) {
    return NativeVideoCaptionMaker(fetcher: ref.watch(fileFetcherProvider));
  }
  return const UnsupportedVideoCaptionMaker();
});

final videoCaptionUserIdProvider = Provider<String?>((ref) {
  try {
    return ref.watch(authStateProvider.select((state) => state.value?.id)) ??
        ref.read(authRepositoryProvider).currentUser?.id;
  } on Object {
    return null;
  }
});

final videoCaptionCacheProvider = Provider<VideoCaptionCache>((ref) {
  return SharedPreferencesVideoCaptionCache(
    userId: ref.watch(videoCaptionUserIdProvider),
  );
});

const _captionsOnKey = 'wecord.accessibility.video_captions_on';

/// Where "captions on" is remembered; tests swap in memory.
abstract interface class VideoCaptionsPreferenceStore {
  Future<bool> load();

  Future<void> save(bool on);
}

class SharedPreferencesVideoCaptionsPreferenceStore
    implements VideoCaptionsPreferenceStore {
  const SharedPreferencesVideoCaptionsPreferenceStore();

  @override
  Future<bool> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_captionsOnKey) ?? false;
  }

  @override
  Future<void> save(bool on) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_captionsOnKey, on);
  }
}

class InMemoryVideoCaptionsPreferenceStore
    implements VideoCaptionsPreferenceStore {
  InMemoryVideoCaptionsPreferenceStore([this.on = false]);

  bool on;

  @override
  Future<bool> load() async => on;

  @override
  Future<void> save(bool on) async => this.on = on;
}

final videoCaptionsPreferenceStoreProvider =
    Provider<VideoCaptionsPreferenceStore>(
      (ref) => const SharedPreferencesVideoCaptionsPreferenceStore(),
    );

/// Whether videos open with captions on: whatever the person last chose, so
/// someone who needs captions turns them on once.
final videoCaptionsOnProvider =
    NotifierProvider<VideoCaptionsOnController, bool>(
      VideoCaptionsOnController.new,
    );

class VideoCaptionsOnController extends Notifier<bool> {
  var _changed = false;

  @override
  bool build() {
    ref.read(videoCaptionsPreferenceStoreProvider).load().then((on) {
      if (!_changed) {
        state = on;
      }
    }, onError: (Object _) {});
    return false;
  }

  Future<void> set(bool on) async {
    _changed = true;
    state = on;
    try {
      await ref.read(videoCaptionsPreferenceStoreProvider).save(on);
    } on Object {
      // Still applies for this session.
    }
  }
}
