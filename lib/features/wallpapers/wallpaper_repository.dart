import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// The bucket the photos live in.
const wallpaperBucket = 'wallpapers';

/// Reads and writes the person's wallpapers on the server (`chat_wallpapers`
/// and the private `wallpapers` bucket). Every call is the signed-in
/// person's own; nothing here can touch anyone else's.
abstract interface class WallpaperRepository {
  /// Every wallpaper the person chose.
  Future<WallpaperSettings> load();

  /// Sets the wallpaper for [conversationId] (null: the default). A photo
  /// the change leaves unused is removed from the bucket.
  Future<void> save(String? conversationId, ChatWallpaper wallpaper);

  /// Removes the wallpaper of [conversationId] (null: the default), so the
  /// chat follows the default again.
  Future<void> clear(String? conversationId);

  /// Uploads a prepared JPEG and returns its path in the bucket.
  Future<String> uploadPhoto(Uint8List bytes);

  /// Removes an uploaded photo that was never used (the person backed out).
  Future<void> discardPhoto(String path);

  /// The photo at [path].
  Future<Uint8List> downloadPhoto(String path);

  /// Pings when the person's wallpapers changed on another device.
  Stream<void> changes();
}

class SupabaseWallpaperRepository implements WallpaperRepository {
  const SupabaseWallpaperRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Sign in to change the wallpaper.');
    }
    return id;
  }

  @override
  Future<WallpaperSettings> load() async {
    final rows = await _client.from('chat_wallpapers').select();
    return WallpaperSettings.fromRows([
      for (final row in rows) Map<String, dynamic>.from(row),
    ]);
  }

  @override
  Future<void> save(String? conversationId, ChatWallpaper wallpaper) async {
    final freed = await _client.rpc<String?>(
      'set_chat_wallpaper',
      params: {
        'target_conversation_id': conversationId,
        'wallpaper_kind': wallpaper.kind.name,
        'wallpaper_preset_id': wallpaper.presetId,
        'wallpaper_photo_path': wallpaper.photoPath,
        'wallpaper_dim': wallpaper.dim,
        'wallpaper_blur': wallpaper.blur,
        'wallpaper_focus_x': wallpaper.focusX,
        'wallpaper_focus_y': wallpaper.focusY,
      },
    );
    await _remove(freed);
  }

  @override
  Future<void> clear(String? conversationId) async {
    final freed = await _client.rpc<String?>(
      'clear_chat_wallpaper',
      params: {'target_conversation_id': conversationId},
    );
    await _remove(freed);
  }

  Future<void> _remove(String? path) async {
    if (path == null) {
      return;
    }
    try {
      await _client.storage.from(wallpaperBucket).remove([path]);
    } on Object {
      // An orphaned file is harmless: only its owner can see it.
    }
  }

  @override
  Future<String> uploadPhoto(Uint8List bytes) async {
    final path = '$_userId/${_randomUuid()}.jpg';
    await _client.storage
        .from(wallpaperBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );
    return path;
  }

  @override
  Future<void> discardPhoto(String path) => _remove(path);

  @override
  Future<Uint8List> downloadPhoto(String path) {
    return _client.storage.from(wallpaperBucket).download(path);
  }

  @override
  Stream<void> changes() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Stream<void>.empty();
    }
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('chat-wallpapers-$userId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'chat_wallpapers',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId,
              ),
              callback: (_) => controller.add(null),
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

/// A random version 4 UUID, for a photo's file name.
String _randomUuid() {
  final random = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int from, int to) => [
    for (var i = from; i < to; i++) bytes[i].toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// Stands in before Supabase is set up (tests): nothing is stored.
class UninitializedWallpaperRepository implements WallpaperRepository {
  const UninitializedWallpaperRepository();

  @override
  Future<WallpaperSettings> load() {
    throw StateError('Supabase must be initialized to load wallpapers.');
  }

  @override
  Future<void> save(String? conversationId, ChatWallpaper wallpaper) {
    throw StateError('Supabase must be initialized to change wallpapers.');
  }

  @override
  Future<void> clear(String? conversationId) {
    throw StateError('Supabase must be initialized to change wallpapers.');
  }

  @override
  Future<String> uploadPhoto(Uint8List bytes) {
    throw StateError('Supabase must be initialized to upload a wallpaper.');
  }

  @override
  Future<void> discardPhoto(String path) async {}

  @override
  Future<Uint8List> downloadPhoto(String path) {
    throw StateError('Supabase must be initialized to load a wallpaper.');
  }

  @override
  Stream<void> changes() => const Stream<void>.empty();
}

final wallpaperRepositoryProvider = Provider<WallpaperRepository>((ref) {
  try {
    return SupabaseWallpaperRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedWallpaperRepository();
  }
});
