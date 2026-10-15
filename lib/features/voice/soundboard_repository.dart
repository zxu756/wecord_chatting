import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/voice/audio_clip.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_sound.dart';

final soundboardRepositoryProvider = Provider<SoundboardRepository>((ref) {
  try {
    return SupabaseSoundboardRepository(
      SupabaseSoundboardDataSource(ref.watch(supabaseClientProvider)),
    );
  } on AssertionError {
    return const UninitializedSoundboardRepository();
  }
});

/// A circle's soundboard; reloads when someone adds or deletes a sound.
final circleSoundsProvider = FutureProvider.autoDispose
    .family<List<CircleSound>, String>((ref, circleId) {
      final repository = ref.watch(soundboardRepositoryProvider);
      final subscription = repository
          .soundChanges(circleId)
          .listen((_) => ref.invalidateSelf(), onError: (Object _) {});
      ref.onDispose(subscription.cancel);
      return repository.listSounds(circleId);
    });

/// A refused upload or play, with a message to show.
class SoundboardException implements Exception {
  const SoundboardException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Played too soon after the last sound.
class SoundboardCooldownException extends SoundboardException {
  SoundboardCooldownException()
    : super(tr('Wait a moment before playing another sound.'));
}

abstract interface class SoundboardRepository {
  Future<List<CircleSound>> listSounds(String circleId);

  /// Checks [bytes] (MP3, Ogg or WAV of at most [maxCircleSoundBytes] and
  /// [maxCircleSoundDuration]), uploads it and adds it to the circle.
  /// Throws [SoundboardException] with a readable message when it can't.
  Future<CircleSound> addSound({
    required String circleId,
    required String name,
    String? emoji,
    required Uint8List bytes,
  });

  /// Deletes the sound and then its clip.
  Future<void> deleteSound(String soundId);

  /// A signed URL for a clip.
  Future<String> createSoundUrl(String storagePath);

  /// Plays [soundId] for everyone in [channelId]. Throws
  /// [SoundboardCooldownException] when played too soon after the last.
  Future<void> play({required String channelId, required String soundId});

  /// Sounds played in [channelId], as they are played.
  Stream<SoundboardPlay> plays(String channelId);

  /// Fires when the circle's sounds change (deletes elsewhere may fire it
  /// too).
  Stream<void> soundChanges(String circleId);
}

abstract interface class SoundboardDataSource {
  Future<Object?> rpc(String functionName, Map<String, dynamic> params);

  Future<void> uploadBinary({
    required String path,
    required Uint8List bytes,
    required String mimeType,
  });

  Future<void> remove(String path);

  Future<String> createSignedUrl(String path, Duration expiresIn);

  /// New `soundboard_plays` rows in [channelId].
  Stream<Map<String, dynamic>> playInserts(String channelId);

  Stream<void> soundChanges(String circleId);
}

/// Whether [name] is a name the server takes.
bool isValidSoundName(String name) {
  final trimmed = name.trim();
  return trimmed.isNotEmpty && trimmed.length <= maxCircleSoundNameLength;
}

class SupabaseSoundboardRepository implements SoundboardRepository {
  SupabaseSoundboardRepository(this._dataSource, {String Function()? newId})
    : _newId = newId ?? _randomUuid;

  final SoundboardDataSource _dataSource;
  final String Function() _newId;

  @override
  Future<List<CircleSound>> listSounds(String circleId) async {
    final rows = await _dataSource.rpc('list_circle_sounds', {
      'target_circle_id': circleId,
    });
    return [
      if (rows is List)
        for (final row in rows)
          if (row is Map) CircleSound.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<CircleSound> addSound({
    required String circleId,
    required String name,
    String? emoji,
    required Uint8List bytes,
  }) async {
    final trimmedName = name.trim();
    if (!isValidSoundName(trimmedName)) {
      throw SoundboardException(tr('Names are 1 to 32 characters.'));
    }
    if (bytes.length > maxCircleSoundBytes) {
      throw SoundboardException(tr('Sounds can be at most 512 KB.'));
    }
    final clip = readAudioClip(bytes);
    if (clip == null) {
      throw SoundboardException(tr('Choose an MP3, Ogg or WAV file.'));
    }
    if (clip.duration > maxCircleSoundDuration) {
      throw SoundboardException(tr('Sounds can be at most 5 seconds long.'));
    }
    final path = '$circleId/${_newId()}.${clip.extension}';
    await _dataSource.uploadBinary(
      path: path,
      bytes: bytes,
      mimeType: clip.mimeType,
    );
    try {
      final row = await _dataSource.rpc('create_circle_sound', {
        'target_circle_id': circleId,
        'sound_name': trimmedName,
        'sound_emoji': emoji?.trim().isEmpty ?? true ? null : emoji!.trim(),
        'storage_path': path,
        'mime_type': clip.mimeType,
        'duration_ms': max(1, clip.duration.inMilliseconds),
      });
      return CircleSound.fromJson(Map<String, dynamic>.from(row! as Map));
    } catch (error) {
      // The clip is useless without its row.
      unawaited(_dataSource.remove(path).catchError((Object _) {}));
      throw _readable(error);
    }
  }

  @override
  Future<void> deleteSound(String soundId) async {
    final path = await _dataSource.rpc('delete_circle_sound', {
      'target_sound_id': soundId,
    });
    if (path is String && path.isNotEmpty) {
      // Leaving the clip behind is harmless; nothing points at it.
      await _dataSource.remove(path).catchError((Object _) {});
    }
  }

  @override
  Future<String> createSoundUrl(String storagePath) {
    // Cached for the session.
    return _dataSource.createSignedUrl(storagePath, const Duration(hours: 24));
  }

  @override
  Future<void> play({
    required String channelId,
    required String soundId,
  }) async {
    try {
      await _dataSource.rpc('play_soundboard_sound', {
        'target_channel_id': channelId,
        'target_sound_id': soundId,
      });
    } on PostgrestException catch (error) {
      if (error.code == 'P0001' &&
          (error.details?.toString() ?? '').startsWith(
            'soundboard_cooldown_ms=',
          )) {
        throw SoundboardCooldownException();
      }
      if (error.code == '42501') {
        throw SoundboardException(tr("You can't play sounds here right now."));
      }
      rethrow;
    }
  }

  @override
  Stream<SoundboardPlay> plays(String channelId) {
    return _dataSource
        .playInserts(channelId)
        .map(SoundboardPlay.fromRecord)
        .where((play) => play != null && play.channelId == channelId)
        .cast<SoundboardPlay>();
  }

  @override
  Stream<void> soundChanges(String circleId) {
    return _dataSource.soundChanges(circleId);
  }

  Object _readable(Object error) {
    if (error is! PostgrestException) {
      return error;
    }
    return switch (error.code) {
      '23505' => SoundboardException(tr('That name is already taken.')),
      '54000' => SoundboardException(
        tr('This circle already has {count} sounds.', {
          'count': maxCircleSounds,
        }),
      ),
      '22023' => SoundboardException(error.message),
      _ => error,
    };
  }
}

class SupabaseSoundboardDataSource implements SoundboardDataSource {
  const SupabaseSoundboardDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) {
    return _client.rpc<Object?>(functionName, params: params);
  }

  @override
  Future<void> uploadBinary({
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    await _client.storage
        .from(circleSoundBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
  }

  @override
  Future<void> remove(String path) async {
    await _client.storage.from(circleSoundBucket).remove([path]);
  }

  @override
  Future<String> createSignedUrl(String path, Duration expiresIn) {
    return _client.storage
        .from(circleSoundBucket)
        .createSignedUrl(path, expiresIn.inSeconds);
  }

  @override
  Stream<Map<String, dynamic>> playInserts(String channelId) {
    late RealtimeChannel channel;
    late StreamController<Map<String, dynamic>> controller;
    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        channel = _client
            .channel('soundboard-plays-$channelId')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'soundboard_plays',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'channel_id',
                value: channelId,
              ),
              callback: (payload) => controller.add(payload.newRecord),
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  Stream<void> soundChanges(String circleId) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        void emit(PostgresChangePayload payload) => controller.add(null);
        final inCircle = PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'circle_id',
          value: circleId,
        );
        channel = _client
            .channel('circle-sounds-$circleId')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'circle_sounds',
              filter: inCircle,
              callback: emit,
            )
            // Deletes carry only the id, so they cannot be filtered.
            .onPostgresChanges(
              event: PostgresChangeEvent.delete,
              schema: 'public',
              table: 'circle_sounds',
              callback: emit,
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }
}

class UninitializedSoundboardRepository implements SoundboardRepository {
  const UninitializedSoundboardRepository();

  @override
  Future<List<CircleSound>> listSounds(String circleId) async => const [];

  @override
  Future<CircleSound> addSound({
    required String circleId,
    required String name,
    String? emoji,
    required Uint8List bytes,
  }) {
    throw StateError('Supabase must be initialized before adding sounds.');
  }

  @override
  Future<void> deleteSound(String soundId) async {}

  @override
  Future<String> createSoundUrl(String storagePath) {
    throw StateError('Supabase must be initialized before loading sounds.');
  }

  @override
  Future<void> play({
    required String channelId,
    required String soundId,
  }) async {}

  @override
  Stream<SoundboardPlay> plays(String channelId) => const Stream.empty();

  @override
  Stream<void> soundChanges(String circleId) => const Stream.empty();
}

/// A random version 4 UUID.
String _randomUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [
    for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
