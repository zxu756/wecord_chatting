import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/circle_emoji.dart';

final circleEmojiRepositoryProvider = Provider<CircleEmojiRepository>((ref) {
  try {
    return SupabaseCircleEmojiRepository(
      SupabaseCircleEmojiDataSource(ref.watch(supabaseClientProvider)),
    );
  } on AssertionError {
    return const UninitializedCircleEmojiRepository();
  }
});

/// A circle's emoji and stickers, for its management page.
final circleEmojisProvider = FutureProvider.autoDispose
    .family<List<CircleEmoji>, String>((ref, circleId) {
      return ref
          .watch(circleEmojiRepositoryProvider)
          .listCircleEmojis(circleId);
    });

/// The emoji and stickers of every circle the current user is in, kept for
/// the session (refreshed when the user changes and after managing them).
/// Failures leave the list empty, so messages fall back to `:name:`.
final usableEmojisProvider = FutureProvider<List<CircleEmoji>>((ref) async {
  // Another account sees other circles.
  ref.watch(authStateProvider.select((state) => state.valueOrNull?.id));
  try {
    return await ref.watch(circleEmojiRepositoryProvider).listUsableEmojis();
  } catch (_) {
    return const [];
  }
});

/// [usableEmojisProvider] by id; empty while loading.
final usableEmojisByIdProvider = Provider<Map<String, CircleEmoji>>((ref) {
  final emojis = ref.watch(usableEmojisProvider).valueOrNull ?? const [];
  return {for (final emoji in emojis) emoji.id: emoji};
});

/// The image of an emoji or sticker at a storage path, cached for the
/// session; null when it cannot be loaded.
final circleEmojiImageProvider = FutureProvider.family<ImageProvider?, String>((
  ref,
  storagePath,
) async {
  try {
    final url = await ref
        .watch(circleEmojiRepositoryProvider)
        .createEmojiUrl(storagePath);
    return NetworkImage(url);
  } catch (_) {
    return null;
  }
});

abstract interface class CircleEmojiRepository {
  Future<List<CircleEmoji>> listCircleEmojis(String circleId);

  Future<List<CircleEmoji>> listUsableEmojis();

  /// Uploads [bytes] (PNG, GIF or WebP of at most [maxCircleEmojiBytes])
  /// and adds it to the circle as [name]. Throws [CircleEmojiException]
  /// with a readable message when the server refuses it.
  Future<CircleEmoji> addCircleEmoji({
    required String circleId,
    required String name,
    required CircleEmojiKind kind,
    required Uint8List bytes,
  });

  Future<CircleEmoji> renameCircleEmoji({
    required String emojiId,
    required String name,
  });

  /// Deletes the emoji or sticker and then its image.
  Future<void> deleteCircleEmoji(String emojiId);

  /// A signed URL for an image in the `circle-emojis` bucket.
  Future<String> createEmojiUrl(String storagePath);
}

abstract interface class CircleEmojiDataSource {
  Future<Object?> rpc(String functionName, Map<String, dynamic> params);

  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  });

  Future<void> remove({required String bucket, required String path});

  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  });
}

/// A refused upload, rename or limit, with a message to show.
class CircleEmojiException implements Exception {
  const CircleEmojiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SupabaseCircleEmojiRepository implements CircleEmojiRepository {
  SupabaseCircleEmojiRepository(this._dataSource, {String Function()? newId})
    : _newId = newId ?? _randomUuid;

  final CircleEmojiDataSource _dataSource;
  final String Function() _newId;

  @override
  Future<List<CircleEmoji>> listCircleEmojis(String circleId) async {
    final rows = await _dataSource.rpc('list_circle_emojis', {
      'target_circle_id': circleId,
    });
    return _emojis(rows);
  }

  @override
  Future<List<CircleEmoji>> listUsableEmojis() async {
    return _emojis(await _dataSource.rpc('list_my_usable_emojis', {}));
  }

  @override
  Future<CircleEmoji> addCircleEmoji({
    required String circleId,
    required String name,
    required CircleEmojiKind kind,
    required Uint8List bytes,
  }) async {
    final trimmedName = name.trim();
    if (!circleEmojiNamePattern.hasMatch(trimmedName)) {
      throw const CircleEmojiException(
        'Names are 2 to 32 lowercase letters, digits or underscores.',
      );
    }
    final mimeType = circleEmojiImageMimeType(bytes);
    if (mimeType == null) {
      throw const CircleEmojiException('Choose a PNG, GIF or WebP image.');
    }
    if (bytes.length > maxCircleEmojiBytes) {
      throw const CircleEmojiException('Images can be at most 256 KB.');
    }
    final path = '$circleId/${_newId()}.${circleEmojiExtension(mimeType)}';
    await _dataSource.uploadBinary(
      bucket: circleEmojiBucket,
      path: path,
      bytes: bytes,
      mimeType: mimeType,
    );
    try {
      final row = await _dataSource.rpc('create_circle_emoji', {
        'target_circle_id': circleId,
        'emoji_name': trimmedName,
        'emoji_kind': kind.toJson(),
        'storage_path': path,
        'mime_type': mimeType,
      });
      return CircleEmoji.fromJson(Map<String, dynamic>.from(row! as Map));
    } catch (error) {
      // The image is useless without its row.
      unawaited(
        _dataSource
            .remove(bucket: circleEmojiBucket, path: path)
            .catchError((Object _) {}),
      );
      throw _readable(error, kind);
    }
  }

  @override
  Future<CircleEmoji> renameCircleEmoji({
    required String emojiId,
    required String name,
  }) async {
    final trimmedName = name.trim();
    if (!circleEmojiNamePattern.hasMatch(trimmedName)) {
      throw const CircleEmojiException(
        'Names are 2 to 32 lowercase letters, digits or underscores.',
      );
    }
    try {
      final row = await _dataSource.rpc('rename_circle_emoji', {
        'target_emoji_id': emojiId,
        'emoji_name': trimmedName,
      });
      return CircleEmoji.fromJson(Map<String, dynamic>.from(row! as Map));
    } catch (error) {
      throw _readable(error, null);
    }
  }

  @override
  Future<void> deleteCircleEmoji(String emojiId) async {
    final path = await _dataSource.rpc('delete_circle_emoji', {
      'target_emoji_id': emojiId,
    });
    if (path is String && path.isNotEmpty) {
      // Leaving the image behind is harmless; nothing points at it.
      await _dataSource
          .remove(bucket: circleEmojiBucket, path: path)
          .catchError((Object _) {});
    }
  }

  @override
  Future<String> createEmojiUrl(String storagePath) {
    return _dataSource.createSignedUrl(
      bucket: circleEmojiBucket,
      path: storagePath,
      // Cached for the session.
      expiresIn: const Duration(hours: 24),
    );
  }

  List<CircleEmoji> _emojis(Object? rows) {
    return (rows as List<dynamic>)
        .map((row) => CircleEmoji.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Object _readable(Object error, CircleEmojiKind? kind) {
    if (error is! PostgrestException) {
      return error;
    }
    return switch (error.code) {
      '23505' => const CircleEmojiException('That name is already taken.'),
      '54000' => CircleEmojiException(
        kind == CircleEmojiKind.sticker
            ? 'This circle already has $maxCircleStickers stickers.'
            : 'This circle already has $maxCircleEmojis emoji.',
      ),
      '22023' => CircleEmojiException(error.message),
      _ => error,
    };
  }
}

class SupabaseCircleEmojiDataSource implements CircleEmojiDataSource {
  const SupabaseCircleEmojiDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) {
    return _client.rpc<Object?>(functionName, params: params);
  }

  @override
  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
  }

  @override
  Future<void> remove({required String bucket, required String path}) async {
    await _client.storage.from(bucket).remove([path]);
  }

  @override
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  }) {
    return _client.storage
        .from(bucket)
        .createSignedUrl(path, expiresIn.inSeconds);
  }
}

class UninitializedCircleEmojiRepository implements CircleEmojiRepository {
  const UninitializedCircleEmojiRepository();

  @override
  Future<List<CircleEmoji>> listCircleEmojis(String circleId) async {
    return const [];
  }

  @override
  Future<List<CircleEmoji>> listUsableEmojis() async => const [];

  @override
  Future<CircleEmoji> addCircleEmoji({
    required String circleId,
    required String name,
    required CircleEmojiKind kind,
    required Uint8List bytes,
  }) {
    throw StateError('Supabase must be initialized before adding emoji.');
  }

  @override
  Future<CircleEmoji> renameCircleEmoji({
    required String emojiId,
    required String name,
  }) {
    throw StateError('Supabase must be initialized before renaming emoji.');
  }

  @override
  Future<void> deleteCircleEmoji(String emojiId) {
    throw StateError('Supabase must be initialized before deleting emoji.');
  }

  @override
  Future<String> createEmojiUrl(String storagePath) {
    throw StateError('Supabase must be initialized before loading emoji.');
  }
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
