import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/report_reason.dart';

final circlesRepositoryProvider = Provider<CirclesRepository>((ref) {
  try {
    return SupabaseCirclesRepository(
      SupabaseCirclesDataSource(ref.watch(supabaseClientProvider)),
    );
  } on AssertionError {
    return const UninitializedCirclesRepository();
  }
});

abstract interface class CirclesRepository {
  Future<List<CircleSummary>> listCircles();

  Future<CircleDetail> getCircleDetail(String circleId);

  Future<String> createCircle({required String name, List<String> memberIds});

  Future<String> createChannel({
    required String circleId,
    required String name,
  });

  Future<void> inviteMembers({
    required String circleId,
    required List<String> memberIds,
  });

  Future<String> createPost({
    required String circleId,
    required String body,
    ImageAttachment? image,
  });

  Future<ImageAttachment> uploadPostImage({
    required String circleId,
    required ChatImageUpload image,
  });

  Future<void> togglePostLike({required String postId, required bool liked});

  Future<String> createComment({required String postId, required String body});

  Future<void> deletePost(String postId);

  Future<void> reportPost({
    required String postId,
    required ReportReason reason,
    String details,
  });

  Future<String> createImageUrl(ImageAttachment attachment);

  Stream<void> circleChanges(String circleId);
}

abstract interface class CirclesDataSource {
  Future<Object?> rpc(String functionName, Map<String, dynamic> params);

  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  });

  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  });

  Stream<void> circleChanges(String circleId);
}

class SupabaseCirclesRepository implements CirclesRepository {
  const SupabaseCirclesRepository(
    this._dataSource, {
    String Function()? storagePathSeed,
    Duration storageOperationTimeout = const Duration(seconds: 30),
  }) : _storagePathSeed = storagePathSeed,
       _storageOperationTimeout = storageOperationTimeout;

  const SupabaseCirclesRepository.withDataSource(
    this._dataSource, {
    String Function()? storagePathSeed,
    Duration storageOperationTimeout = const Duration(seconds: 30),
  }) : _storagePathSeed = storagePathSeed,
       _storageOperationTimeout = storageOperationTimeout;

  final CirclesDataSource _dataSource;
  final String Function()? _storagePathSeed;
  final Duration _storageOperationTimeout;

  @override
  Future<List<CircleSummary>> listCircles() async {
    final rows = await _dataSource.rpc('list_circle_summaries', {});
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(CircleSummary.fromJson)
        .toList(growable: false);
  }

  @override
  Future<CircleDetail> getCircleDetail(String circleId) async {
    final payload = await _dataSource.rpc('get_circle_detail', {
      'target_circle_id': circleId,
    });
    return CircleDetail.fromJson(payload as Map<String, dynamic>);
  }

  @override
  Future<String> createCircle({
    required String name,
    List<String> memberIds = const <String>[],
  }) async {
    final circleId = await _dataSource.rpc('create_circle', {
      'circle_name': name.trim(),
      'member_ids': memberIds,
    });
    return circleId as String;
  }

  @override
  Future<String> createChannel({
    required String circleId,
    required String name,
  }) async {
    final channelId = await _dataSource.rpc('create_circle_channel', {
      'target_circle_id': circleId,
      'channel_name': name.trim(),
    });
    return channelId as String;
  }

  @override
  Future<void> inviteMembers({
    required String circleId,
    required List<String> memberIds,
  }) async {
    await _dataSource.rpc('invite_circle_members', {
      'target_circle_id': circleId,
      'member_ids': memberIds,
    });
  }

  @override
  Future<String> createPost({
    required String circleId,
    required String body,
    ImageAttachment? image,
  }) async {
    final postId = await _dataSource.rpc('create_circle_post', {
      'target_circle_id': circleId,
      'body': body.trim(),
      'attachment': image?.toJson(),
    });
    return postId as String;
  }

  @override
  Future<ImageAttachment> uploadPostImage({
    required String circleId,
    required ChatImageUpload image,
  }) async {
    const bucket = 'chat-media';
    final path =
        '$circleId/${_nextStoragePathSeed()}-${_safeFileName(image.fileName)}';
    await _withStorageTimeout(
      _dataSource.uploadBinary(
        bucket: bucket,
        path: path,
        bytes: image.bytes,
        mimeType: image.mimeType,
      ),
    );
    return ImageAttachment(
      bucket: bucket,
      path: path,
      mimeType: image.mimeType,
      size: image.bytes.length,
      width: image.width,
      height: image.height,
    );
  }

  @override
  Future<void> togglePostLike({
    required String postId,
    required bool liked,
  }) async {
    await _dataSource.rpc('toggle_circle_post_like', {
      'target_post_id': postId,
      'liked': liked,
    });
  }

  @override
  Future<String> createComment({
    required String postId,
    required String body,
  }) async {
    final commentId = await _dataSource.rpc('create_circle_post_comment', {
      'target_post_id': postId,
      'body': body.trim(),
    });
    return commentId as String;
  }

  @override
  Future<void> deletePost(String postId) async {
    await _dataSource.rpc('delete_circle_post', {'target_post_id': postId});
  }

  @override
  Future<void> reportPost({
    required String postId,
    required ReportReason reason,
    String details = '',
  }) async {
    await _dataSource.rpc('report_circle_post', {
      'target_post_id': postId,
      'report_reason': reason.toJson(),
      'report_details': details,
    });
  }

  @override
  Future<String> createImageUrl(ImageAttachment attachment) {
    return _withStorageTimeout(
      _dataSource.createSignedUrl(
        bucket: attachment.bucket,
        path: attachment.path,
        expiresIn: const Duration(hours: 1),
      ),
    );
  }

  @override
  Stream<void> circleChanges(String circleId) {
    return _dataSource.circleChanges(circleId);
  }

  String _nextStoragePathSeed() {
    return _storagePathSeed?.call() ??
        DateTime.now().toUtc().microsecondsSinceEpoch.toString();
  }

  Future<T> _withStorageTimeout<T>(Future<T> operation) {
    return operation.timeout(
      _storageOperationTimeout,
      onTimeout: () {
        throw TimeoutException(
          'Circle media storage request timed out',
          _storageOperationTimeout,
        );
      },
    );
  }

  String _safeFileName(String fileName) {
    final normalized = fileName.trim().toLowerCase();
    final sanitized = normalized
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return sanitized.isEmpty ? 'image.jpg' : sanitized;
  }
}

class SupabaseCirclesDataSource implements CirclesDataSource {
  const SupabaseCirclesDataSource(this._client);

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
  Stream<void> circleChanges(String circleId) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        void emit(PostgresChangePayload payload) {
          controller.add(null);
        }

        channel = _client
            .channel('circle-changes-$circleId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'circles',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: circleId,
              ),
              callback: emit,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'circle_members',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'circle_id',
                value: circleId,
              ),
              callback: emit,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'circle_channels',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'circle_id',
                value: circleId,
              ),
              callback: emit,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'circle_posts',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'circle_id',
                value: circleId,
              ),
              callback: emit,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'circle_post_likes',
              callback: emit,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'circle_post_comments',
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

class UninitializedCirclesRepository implements CirclesRepository {
  const UninitializedCirclesRepository();

  @override
  Future<List<CircleSummary>> listCircles() async {
    return const [];
  }

  @override
  Future<CircleDetail> getCircleDetail(String circleId) {
    throw StateError('Supabase must be initialized before opening circles.');
  }

  @override
  Future<String> createCircle({
    required String name,
    List<String> memberIds = const <String>[],
  }) {
    throw StateError('Supabase must be initialized before creating circles.');
  }

  @override
  Future<String> createChannel({
    required String circleId,
    required String name,
  }) {
    throw StateError('Supabase must be initialized before creating channels.');
  }

  @override
  Future<void> inviteMembers({
    required String circleId,
    required List<String> memberIds,
  }) {
    throw StateError('Supabase must be initialized before inviting members.');
  }

  @override
  Future<String> createPost({
    required String circleId,
    required String body,
    ImageAttachment? image,
  }) {
    throw StateError('Supabase must be initialized before creating posts.');
  }

  @override
  Future<ImageAttachment> uploadPostImage({
    required String circleId,
    required ChatImageUpload image,
  }) {
    throw StateError('Supabase must be initialized before uploading images.');
  }

  @override
  Future<void> togglePostLike({required String postId, required bool liked}) {
    throw StateError('Supabase must be initialized before liking posts.');
  }

  @override
  Future<String> createComment({required String postId, required String body}) {
    throw StateError('Supabase must be initialized before commenting.');
  }

  @override
  Future<void> deletePost(String postId) {
    throw StateError('Supabase must be initialized before deleting posts.');
  }

  @override
  Future<void> reportPost({
    required String postId,
    required ReportReason reason,
    String details = '',
  }) {
    throw StateError('Supabase must be initialized before reporting posts.');
  }

  @override
  Future<String> createImageUrl(ImageAttachment attachment) {
    throw StateError('Supabase must be initialized before loading images.');
  }

  @override
  Stream<void> circleChanges(String circleId) {
    return const Stream<void>.empty();
  }
}

extension ReportReasonJson on ReportReason {
  String toJson() => value;
}
