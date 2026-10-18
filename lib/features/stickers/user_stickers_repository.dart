import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/push/push_repository.dart';
import 'package:wecord/features/stickers/sticker_formats.dart';
import 'package:wecord/features/stickers/user_sticker.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// A person's own stickers: the table, the private bucket and sending
/// (202610220500, 202610220510).
abstract interface class UserStickersRepository {
  /// The library, in the person's order.
  Future<List<UserSticker>> list();

  /// Uploads [sticker] and adds it to the library, at the front. Throws
  /// [UserStickerException] when the library is full or the server refuses
  /// the picture.
  Future<UserSticker> add(PreparedSticker sticker);

  /// Deletes the row and then the image.
  Future<void> delete(UserSticker sticker);

  /// Saves the order of the library: [ids] first, in this order.
  Future<void> reorder(List<String> ids);

  /// A signed URL for a file of the library or of a chat.
  Future<String> createUrl(StickerFile file);

  /// The bytes of a file the person can read (a picture of a chat, a sticker
  /// of a circle, a sticker of their own).
  Future<Uint8List> download(StickerFile file);

  /// Sends [sticker] to [conversationId]: copies the image into the
  /// conversation's folder in the chat bucket and sends a sticker message
  /// that names the copy. Throws the same refusals as any send
  /// ([SlowmodeException], [SendRefusedException]).
  Future<void> send({
    required String conversationId,
    required UserSticker sticker,
  });
}

/// The signed-in person's library, kept for the session and reloaded when
/// the account changes or after managing it.
final userStickersProvider = FutureProvider<List<UserSticker>>((ref) async {
  ref.watch(authStateProvider.select((state) => state.value?.id));
  try {
    return await ref.watch(userStickersRepositoryProvider).list();
  } catch (_) {
    return const [];
  }
});

final userStickersRepositoryProvider = Provider<UserStickersRepository>((ref) {
  try {
    return SupabaseUserStickersRepository(
      SupabaseUserStickersDataSource(ref.watch(supabaseClientProvider)),
      onSent: ref.watch(pushRepositoryProvider).notifySent,
    );
  } on ProviderException {
    return const UninitializedUserStickersRepository();
  }
});

/// The image of a sticker file, cached for the session; null when it cannot
/// be loaded. [animated] is passed on to the widgets that hold still.
final stickerFileImageProvider =
    FutureProvider.family<ImageProvider?, StickerFile>((ref, file) async {
      try {
        final url = await ref
            .watch(userStickersRepositoryProvider)
            .createUrl(file);
        return NetworkImage(url);
      } catch (_) {
        return null;
      }
    });

abstract interface class UserStickersDataSource {
  Future<List<Map<String, dynamic>>> selectAll();

  Future<Map<String, dynamic>> insert(Map<String, dynamic> row);

  Future<void> deleteRow(String id);

  Future<Object?> rpc(String functionName, Map<String, dynamic> params);

  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  });

  Future<void> remove({required String bucket, required String path});

  Future<void> copy({
    required String fromBucket,
    required String fromPath,
    required String toBucket,
    required String toPath,
  });

  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  });

  Future<Uint8List> download({required String bucket, required String path});

  String get currentUserId;
}

class SupabaseUserStickersRepository implements UserStickersRepository {
  SupabaseUserStickersRepository(
    this._dataSource, {
    this.onSent,
    String Function()? newId,
  }) : _newId = newId ?? _randomUuid;

  final UserStickersDataSource _dataSource;
  final String Function() _newId;

  /// Told the id of a sent message, to push it to the others.
  final Future<void> Function(String messageId)? onSent;

  @override
  Future<List<UserSticker>> list() async {
    final rows = await _dataSource.selectAll();
    return [for (final row in rows) UserSticker.fromJson(row)];
  }

  @override
  Future<UserSticker> add(PreparedSticker sticker) async {
    final ownerId = _dataSource.currentUserId;
    final path = '$ownerId/${_newId()}.${sticker.format.extension}';
    await _dataSource.uploadBinary(
      bucket: userStickerBucket,
      path: path,
      bytes: sticker.bytes,
      mimeType: sticker.format.mimeType,
    );
    try {
      final row = await _dataSource.insert({
        'owner_id': ownerId,
        'path': path,
        'width': sticker.width,
        'height': sticker.height,
        'animated': sticker.animated,
      });
      return UserSticker.fromJson(row);
    } catch (error) {
      // The image is useless without its row.
      unawaited(
        _dataSource
            .remove(bucket: userStickerBucket, path: path)
            .catchError((Object _) {}),
      );
      throw _readable(error);
    }
  }

  @override
  Future<void> delete(UserSticker sticker) async {
    await _dataSource.deleteRow(sticker.id);
    // Leaving the image behind is harmless; nothing points at it.
    await _dataSource
        .remove(bucket: userStickerBucket, path: sticker.path)
        .catchError((Object _) {});
  }

  @override
  Future<void> reorder(List<String> ids) async {
    await _dataSource.rpc('reorder_user_stickers', {'sticker_ids': ids});
  }

  @override
  Future<String> createUrl(StickerFile file) {
    return _dataSource.createSignedUrl(
      bucket: file.bucket,
      path: file.path,
      // Cached for the session.
      expiresIn: const Duration(hours: 24),
    );
  }

  @override
  Future<Uint8List> download(StickerFile file) {
    return _dataSource.download(bucket: file.bucket, path: file.path);
  }

  @override
  Future<void> send({
    required String conversationId,
    required UserSticker sticker,
  }) async {
    final copyPath = '$conversationId/sticker-${_newId()}.${sticker.extension}';
    await _dataSource.copy(
      fromBucket: userStickerBucket,
      fromPath: sticker.path,
      toBucket: stickerChatBucket,
      toPath: copyPath,
    );
    final Object? messageId;
    try {
      messageId = await _dataSource.rpc('send_personal_sticker', {
        'target_conversation_id': conversationId,
        'target_sticker_id': sticker.id,
        'chat_path': copyPath,
      });
    } on PostgrestException catch (error) {
      _forgetCopy(copyPath);
      final slowmode = SlowmodeException.fromPostgrest(error);
      if (slowmode != null) {
        throw slowmode;
      }
      final refused = SendRefusedException.fromPostgrest(error);
      if (refused != null) {
        throw refused;
      }
      rethrow;
    }
    if (messageId is! String) {
      // AutoMod refuses some sends quietly and leaves a note of why.
      _forgetCopy(copyPath);
      Map<String, dynamic>? notice;
      try {
        final answer = await _dataSource.rpc('take_automod_notice', {
          'target_conversation_id': conversationId,
        });
        notice = answer is Map<String, dynamic> ? answer : null;
      } catch (_) {
        notice = null;
      }
      throw AutoModBlockedException(notice?['reason'] as String?);
    }
    unawaited(onSent?.call(messageId));
  }

  void _forgetCopy(String path) {
    // Only a recalled message's picture can be removed by its sender, so this
    // usually does nothing; the unused copy is not shown anywhere.
    unawaited(
      _dataSource
          .remove(bucket: stickerChatBucket, path: path)
          .catchError((Object _) {}),
    );
  }

  Object _readable(Object error) {
    if (error is! PostgrestException) {
      return error;
    }
    return switch (error.code) {
      '54000' => UserStickerException.full(),
      '22023' => UserStickerException.animatedTooLarge(),
      _ => error,
    };
  }
}

class SupabaseUserStickersDataSource implements UserStickersDataSource {
  const SupabaseUserStickersDataSource(this._client);

  final SupabaseClient _client;

  @override
  String get currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Sign in to keep stickers.');
    }
    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> selectAll() async {
    final rows = await _client
        .from('user_stickers')
        .select()
        .order('sort_key', ascending: true)
        .order('created_at', ascending: false);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row) async {
    return Map<String, dynamic>.from(
      await _client.from('user_stickers').insert(row).select().single(),
    );
  }

  @override
  Future<void> deleteRow(String id) async {
    await _client.from('user_stickers').delete().eq('id', id);
  }

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
  Future<void> copy({
    required String fromBucket,
    required String fromPath,
    required String toBucket,
    required String toPath,
  }) async {
    await _client.storage
        .from(fromBucket)
        .copy(fromPath, toPath, destinationBucket: toBucket);
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
  Future<Uint8List> download({required String bucket, required String path}) {
    return _client.storage.from(bucket).download(path);
  }
}

class UninitializedUserStickersRepository implements UserStickersRepository {
  const UninitializedUserStickersRepository();

  @override
  Future<List<UserSticker>> list() async => const [];

  @override
  Future<UserSticker> add(PreparedSticker sticker) {
    throw StateError('Supabase must be initialized before adding stickers.');
  }

  @override
  Future<void> delete(UserSticker sticker) {
    throw StateError('Supabase must be initialized before deleting stickers.');
  }

  @override
  Future<void> reorder(List<String> ids) {
    throw StateError('Supabase must be initialized before ordering stickers.');
  }

  @override
  Future<String> createUrl(StickerFile file) {
    throw StateError('Supabase must be initialized before loading stickers.');
  }

  @override
  Future<Uint8List> download(StickerFile file) {
    throw StateError('Supabase must be initialized before loading stickers.');
  }

  @override
  Future<void> send({
    required String conversationId,
    required UserSticker sticker,
  }) {
    throw StateError('Supabase must be initialized before sending stickers.');
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
