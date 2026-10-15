import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
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

/// A circle's emoji and stickers, for its management page; reloads when
/// someone changes them.
final circleEmojisProvider = FutureProvider.autoDispose
    .family<List<CircleEmoji>, String>((ref, circleId) {
      final repository = ref.watch(circleEmojiRepositoryProvider);
      _reloadOnChanges(ref, repository.emojiChanges(circleId: circleId));
      return repository.listCircleEmojis(circleId);
    });

/// The emoji and stickers of every circle the current user is in, kept for
/// the session (refreshed when the user changes, after managing them and
/// when someone changes them in one of the user's circles). Failures leave
/// the list empty, so messages fall back to `:name:`.
final usableEmojisProvider = FutureProvider<List<CircleEmoji>>((ref) async {
  // Another account sees other circles.
  ref.watch(authStateProvider.select((state) => state.valueOrNull?.id));
  final repository = ref.watch(circleEmojiRepositoryProvider);
  _reloadOnChanges(ref, repository.emojiChanges());
  try {
    return await repository.listUsableEmojis();
  } catch (_) {
    return const [];
  }
});

/// Reloads the provider behind [ref] on every event of [changes] until it
/// is disposed. A broken realtime connection only stops live updates.
void _reloadOnChanges(Ref<Object?> ref, Stream<void> changes) {
  final subscription = changes.listen(
    (_) => ref.invalidateSelf(),
    onError: (Object _) {},
  );
  ref.onDispose(subscription.cancel);
}

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

  /// Fires when emoji or stickers are added, renamed or deleted in
  /// [circleId], or in any circle the current user is in when it is null.
  /// Deletes elsewhere may fire it too (realtime cannot tell whose they
  /// are), so listeners just reload.
  Stream<void> emojiChanges({String? circleId});
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

  /// See [CircleEmojiRepository.emojiChanges].
  Stream<void> emojiChanges({String? circleId});
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
      throw CircleEmojiException(
        tr('Names are 2 to 32 lowercase letters, digits or underscores.'),
      );
    }
    final mimeType = circleEmojiImageMimeType(bytes);
    if (mimeType == null) {
      throw CircleEmojiException(tr('Choose a PNG, GIF or WebP image.'));
    }
    if (bytes.length > maxCircleEmojiBytes) {
      throw CircleEmojiException(tr('Images can be at most 256 KB.'));
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
      throw CircleEmojiException(
        tr('Names are 2 to 32 lowercase letters, digits or underscores.'),
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

  @override
  Stream<void> emojiChanges({String? circleId}) {
    return _dataSource.emojiChanges(circleId: circleId);
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
      '23505' => CircleEmojiException(tr('That name is already taken.')),
      '54000' => CircleEmojiException(
        kind == CircleEmojiKind.sticker
            ? tr('This circle already has {count} stickers.', {
                'count': maxCircleStickers,
              })
            : tr('This circle already has {count} emoji.', {
                'count': maxCircleEmojis,
              }),
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

  @override
  Stream<void> emojiChanges({String? circleId}) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        void emit(PostgresChangePayload payload) {
          controller.add(null);
        }

        if (circleId == null) {
          // Row level security limits inserts and updates to the user's
          // circles.
          channel = _client
              .channel('circle-emojis')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'circle_emojis',
                callback: emit,
              );
        } else {
          final inCircle = PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'circle_id',
            value: circleId,
          );
          channel = _client
              .channel('circle-emojis-$circleId')
              .onPostgresChanges(
                event: PostgresChangeEvent.insert,
                schema: 'public',
                table: 'circle_emojis',
                filter: inCircle,
                callback: emit,
              )
              .onPostgresChanges(
                event: PostgresChangeEvent.update,
                schema: 'public',
                table: 'circle_emojis',
                filter: inCircle,
                callback: emit,
              )
              // Deletes carry only the id, so they cannot be filtered.
              .onPostgresChanges(
                event: PostgresChangeEvent.delete,
                schema: 'public',
                table: 'circle_emojis',
                callback: emit,
              );
        }
        channel.subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
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

  @override
  Stream<void> emojiChanges({String? circleId}) => const Stream.empty();
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
