import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_channel_overwrite.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/shared/models/circle_notification_settings.dart';
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

  /// Throws [CircleMembershipLostException] when the current user is not
  /// (or no longer) a member of the circle.
  Future<CircleDetail> getCircleDetail(String circleId);

  Future<String> createCircle({required String name, List<String> memberIds});

  /// Creates a channel, in [categoryId] when given.
  Future<String> createChannel({
    required String circleId,
    required String name,
    String? categoryId,
  });

  /// Returns the new category id.
  Future<String> createChannelCategory({
    required String circleId,
    required String name,
  });

  Future<void> renameChannelCategory({
    required String categoryId,
    required String name,
  });

  /// Deletes the category; its channels become uncategorized.
  Future<void> deleteChannelCategory(String categoryId);

  /// Stores the order of every category and channel of the circle at once.
  Future<void> reorderChannels({
    required String circleId,
    required CircleChannelLayout layout,
  });

  Future<void> inviteMembers({
    required String circleId,
    required List<String> memberIds,
  });

  /// Returns the new invite code. Null [expiresIn] / [maxUses] mean never /
  /// unlimited.
  Future<String> createInvite({
    required String circleId,
    Duration? expiresIn,
    int? maxUses,
  });

  Future<List<CircleInvite>> listInvites(String circleId);

  Future<void> revokeInvite(String code);

  Future<CircleInvitePreview> getInvitePreview(String code);

  /// Joins the circle behind [code] and returns its id.
  Future<String> acceptInvite(String code);

  /// Sets [userId]'s nickname in the circle; null or blank clears it.
  Future<void> setNickname({
    required String circleId,
    required String userId,
    required String? nickname,
  });

  /// Creates a role just above `@everyone` and returns its id. [color] is
  /// 0xRRGGBB or null; [permissions] are `CirclePermission` bits.
  Future<String> createRole({
    required String circleId,
    required String name,
    int? color,
    int permissions = 0,
    bool hoist = false,
  });

  Future<void> updateRole({
    required String roleId,
    required String name,
    int? color,
    required int permissions,
    bool hoist = false,
  });

  Future<void> deleteRole(String roleId);

  /// Stores the order of every role except `@everyone`, highest first.
  Future<void> reorderRoles({
    required String circleId,
    required List<String> roleIds,
  });

  /// Replaces the roles assigned to [userId] (without `@everyone`).
  Future<void> setMemberRoles({
    required String circleId,
    required String userId,
    required List<String> roleIds,
  });

  /// Removes [userId] from the circle and all of its channels.
  Future<void> kickMember({required String circleId, required String userId});

  /// Leaves the circle and all of its channels. The owner must transfer
  /// ownership first.
  Future<void> leaveCircle(String circleId);

  /// Makes [newOwnerId] the circle's owner; the current owner stays as a
  /// member without roles.
  Future<void> transferOwnership({
    required String circleId,
    required String newOwnerId,
  });

  /// The permission overwrites of a channel, roles first.
  Future<List<CircleChannelOverwrite>> listChannelOverwrites(String channelId);

  /// Stores the overwrite of [roleId] or [userId] (exactly one) in a
  /// channel; [allow] = [deny] = 0 removes it.
  Future<void> setChannelOverwrite({
    required String channelId,
    String? roleId,
    String? userId,
    required int allow,
    required int deny,
  });

  /// Denies `@everyone` view channel ([isPrivate]) and send messages
  /// ([isReadOnly]) in a channel, or lifts those denies.
  Future<void> setChannelPrivacy({
    required String channelId,
    required bool isPrivate,
    required bool isReadOnly,
  });

  /// Sets how many seconds members wait between messages in a channel; 0
  /// turns slowmode off.
  Future<void> setChannelSlowmode({
    required String channelId,
    required int seconds,
  });

  /// The current user's notification settings for the circle.
  Future<CircleNotificationSettings> getNotificationSettings(String circleId);

  /// Saves the current user's notification settings; a null or past
  /// [mutedUntil] unmutes.
  Future<CircleNotificationSettings> setNotificationSettings({
    required String circleId,
    required CircleNotificationLevel level,
    DateTime? mutedUntil,
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

/// The current user is not a member of the circle (any more): they left,
/// were kicked, or the circle is gone.
class CircleMembershipLostException implements Exception {
  const CircleMembershipLostException(this.circleId);

  final String circleId;

  @override
  String toString() => 'You are no longer a member of this circle.';
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
    if (payload == null) {
      throw CircleMembershipLostException(circleId);
    }
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
    String? categoryId,
  }) async {
    final channelId = await _dataSource.rpc('create_circle_channel', {
      'target_circle_id': circleId,
      'channel_name': name.trim(),
      if (categoryId != null) 'target_category_id': categoryId,
    });
    return channelId as String;
  }

  @override
  Future<String> createChannelCategory({
    required String circleId,
    required String name,
  }) async {
    final categoryId = await _dataSource.rpc('create_channel_category', {
      'target_circle_id': circleId,
      'category_name': name.trim(),
    });
    return categoryId as String;
  }

  @override
  Future<void> renameChannelCategory({
    required String categoryId,
    required String name,
  }) async {
    await _dataSource.rpc('rename_channel_category', {
      'target_category_id': categoryId,
      'category_name': name.trim(),
    });
  }

  @override
  Future<void> deleteChannelCategory(String categoryId) async {
    await _dataSource.rpc('delete_channel_category', {
      'target_category_id': categoryId,
    });
  }

  @override
  Future<void> reorderChannels({
    required String circleId,
    required CircleChannelLayout layout,
  }) async {
    await _dataSource.rpc('reorder_circle_channels', {
      'target_circle_id': circleId,
      'layout': layout.toJson(),
    });
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
  Future<String> createInvite({
    required String circleId,
    Duration? expiresIn,
    int? maxUses,
  }) async {
    final code = await _dataSource.rpc('create_circle_invite', {
      'target_circle_id': circleId,
      'expires_in_hours': expiresIn?.inHours,
      'max_uses': maxUses,
    });
    return code as String;
  }

  @override
  Future<List<CircleInvite>> listInvites(String circleId) async {
    final rows = await _dataSource.rpc('list_circle_invites', {
      'target_circle_id': circleId,
    });
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(CircleInvite.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> revokeInvite(String code) async {
    await _dataSource.rpc('revoke_circle_invite', {'invite_code': code});
  }

  @override
  Future<void> setNickname({
    required String circleId,
    required String userId,
    required String? nickname,
  }) async {
    final trimmed = nickname?.trim();
    await _dataSource.rpc('set_circle_nickname', {
      'target_circle_id': circleId,
      'target_user_id': userId,
      'nickname': trimmed == null || trimmed.isEmpty ? null : trimmed,
    });
  }

  @override
  Future<String> createRole({
    required String circleId,
    required String name,
    int? color,
    int permissions = 0,
    bool hoist = false,
  }) async {
    final roleId = await _dataSource.rpc('create_circle_role', {
      'target_circle_id': circleId,
      'role_name': name.trim(),
      'role_color': color,
      'role_permissions': permissions,
      'role_hoist': hoist,
    });
    return roleId as String;
  }

  @override
  Future<void> updateRole({
    required String roleId,
    required String name,
    int? color,
    required int permissions,
    bool hoist = false,
  }) async {
    await _dataSource.rpc('update_circle_role', {
      'target_role_id': roleId,
      'role_name': name.trim(),
      'role_color': color,
      'role_permissions': permissions,
      'role_hoist': hoist,
    });
  }

  @override
  Future<void> deleteRole(String roleId) async {
    await _dataSource.rpc('delete_circle_role', {'target_role_id': roleId});
  }

  @override
  Future<void> reorderRoles({
    required String circleId,
    required List<String> roleIds,
  }) async {
    await _dataSource.rpc('reorder_circle_roles', {
      'target_circle_id': circleId,
      'role_ids': roleIds,
    });
  }

  @override
  Future<void> setMemberRoles({
    required String circleId,
    required String userId,
    required List<String> roleIds,
  }) async {
    await _dataSource.rpc('set_member_roles', {
      'target_circle_id': circleId,
      'target_user_id': userId,
      'role_ids': roleIds,
    });
  }

  @override
  Future<void> kickMember({
    required String circleId,
    required String userId,
  }) async {
    await _dataSource.rpc('kick_circle_member', {
      'target_circle_id': circleId,
      'target_user_id': userId,
    });
  }

  @override
  Future<void> leaveCircle(String circleId) async {
    await _dataSource.rpc('leave_circle', {'target_circle_id': circleId});
  }

  @override
  Future<void> transferOwnership({
    required String circleId,
    required String newOwnerId,
  }) async {
    await _dataSource.rpc('transfer_circle_ownership', {
      'target_circle_id': circleId,
      'new_owner_id': newOwnerId,
    });
  }

  @override
  Future<List<CircleChannelOverwrite>> listChannelOverwrites(
    String channelId,
  ) async {
    final rows = await _dataSource.rpc('list_channel_overwrites', {
      'target_channel_id': channelId,
    });
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(CircleChannelOverwrite.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> setChannelOverwrite({
    required String channelId,
    String? roleId,
    String? userId,
    required int allow,
    required int deny,
  }) async {
    await _dataSource.rpc('set_channel_overwrite', {
      'target_channel_id': channelId,
      'target_role_id': roleId,
      'target_user_id': userId,
      'allow_bits': allow,
      'deny_bits': deny,
    });
  }

  @override
  Future<void> setChannelPrivacy({
    required String channelId,
    required bool isPrivate,
    required bool isReadOnly,
  }) async {
    await _dataSource.rpc('set_channel_privacy', {
      'target_channel_id': channelId,
      'private': isPrivate,
      'read_only': isReadOnly,
    });
  }

  @override
  Future<void> setChannelSlowmode({
    required String channelId,
    required int seconds,
  }) async {
    await _dataSource.rpc('set_channel_slowmode', {
      'target_channel_id': channelId,
      'seconds': seconds,
    });
  }

  @override
  Future<CircleNotificationSettings> getNotificationSettings(
    String circleId,
  ) async {
    final payload = await _dataSource.rpc('get_circle_notification_settings', {
      'target_circle_id': circleId,
    });
    return CircleNotificationSettings.fromJson(payload as Map<String, dynamic>);
  }

  @override
  Future<CircleNotificationSettings> setNotificationSettings({
    required String circleId,
    required CircleNotificationLevel level,
    DateTime? mutedUntil,
  }) async {
    final payload = await _dataSource.rpc('set_circle_notification_settings', {
      'target_circle_id': circleId,
      'level': level.toJson(),
      'muted_until': mutedUntil?.toUtc().toIso8601String(),
    });
    return CircleNotificationSettings.fromJson(payload as Map<String, dynamic>);
  }

  @override
  Future<CircleInvitePreview> getInvitePreview(String code) async {
    final payload = await _dataSource.rpc('get_circle_invite_preview', {
      'invite_code': code,
    });
    return CircleInvitePreview.fromJson(payload as Map<String, dynamic>);
  }

  @override
  Future<String> acceptInvite(String code) async {
    final circleId = await _dataSource.rpc('accept_circle_invite', {
      'invite_code': code,
    });
    return circleId as String;
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
              table: 'circle_channel_categories',
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
              table: 'circle_roles',
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
              table: 'circle_member_roles',
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
              table: 'circle_channel_overwrites',
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
    String? categoryId,
  }) {
    throw StateError('Supabase must be initialized before creating channels.');
  }

  @override
  Future<String> createChannelCategory({
    required String circleId,
    required String name,
  }) {
    throw StateError(
      'Supabase must be initialized before creating categories.',
    );
  }

  @override
  Future<void> renameChannelCategory({
    required String categoryId,
    required String name,
  }) {
    throw StateError(
      'Supabase must be initialized before renaming categories.',
    );
  }

  @override
  Future<void> deleteChannelCategory(String categoryId) {
    throw StateError(
      'Supabase must be initialized before deleting categories.',
    );
  }

  @override
  Future<void> reorderChannels({
    required String circleId,
    required CircleChannelLayout layout,
  }) {
    throw StateError('Supabase must be initialized before reordering.');
  }

  @override
  Future<void> inviteMembers({
    required String circleId,
    required List<String> memberIds,
  }) {
    throw StateError('Supabase must be initialized before inviting members.');
  }

  @override
  Future<String> createInvite({
    required String circleId,
    Duration? expiresIn,
    int? maxUses,
  }) {
    throw StateError('Supabase must be initialized before creating invites.');
  }

  @override
  Future<List<CircleInvite>> listInvites(String circleId) async {
    return const [];
  }

  @override
  Future<void> revokeInvite(String code) {
    throw StateError('Supabase must be initialized before revoking invites.');
  }

  @override
  Future<CircleInvitePreview> getInvitePreview(String code) {
    throw StateError('Supabase must be initialized before opening invites.');
  }

  @override
  Future<void> setNickname({
    required String circleId,
    required String userId,
    required String? nickname,
  }) {
    throw StateError('Supabase must be initialized before setting nicknames.');
  }

  @override
  Future<String> acceptInvite(String code) {
    throw StateError('Supabase must be initialized before joining circles.');
  }

  @override
  Future<String> createRole({
    required String circleId,
    required String name,
    int? color,
    int permissions = 0,
    bool hoist = false,
  }) {
    throw StateError('Supabase must be initialized before creating roles.');
  }

  @override
  Future<void> updateRole({
    required String roleId,
    required String name,
    int? color,
    required int permissions,
    bool hoist = false,
  }) {
    throw StateError('Supabase must be initialized before editing roles.');
  }

  @override
  Future<void> deleteRole(String roleId) {
    throw StateError('Supabase must be initialized before deleting roles.');
  }

  @override
  Future<void> reorderRoles({
    required String circleId,
    required List<String> roleIds,
  }) {
    throw StateError('Supabase must be initialized before reordering roles.');
  }

  @override
  Future<void> setMemberRoles({
    required String circleId,
    required String userId,
    required List<String> roleIds,
  }) {
    throw StateError('Supabase must be initialized before assigning roles.');
  }

  @override
  Future<void> kickMember({required String circleId, required String userId}) {
    throw StateError('Supabase must be initialized before kicking members.');
  }

  @override
  Future<void> leaveCircle(String circleId) {
    throw StateError('Supabase must be initialized before leaving circles.');
  }

  @override
  Future<void> transferOwnership({
    required String circleId,
    required String newOwnerId,
  }) {
    throw StateError(
      'Supabase must be initialized before transferring ownership.',
    );
  }

  @override
  Future<List<CircleChannelOverwrite>> listChannelOverwrites(
    String channelId,
  ) async {
    return const [];
  }

  @override
  Future<void> setChannelOverwrite({
    required String channelId,
    String? roleId,
    String? userId,
    required int allow,
    required int deny,
  }) {
    throw StateError(
      'Supabase must be initialized before changing channel permissions.',
    );
  }

  @override
  Future<void> setChannelPrivacy({
    required String channelId,
    required bool isPrivate,
    required bool isReadOnly,
  }) {
    throw StateError(
      'Supabase must be initialized before changing channel permissions.',
    );
  }

  @override
  Future<void> setChannelSlowmode({
    required String channelId,
    required int seconds,
  }) {
    throw StateError('Supabase must be initialized before changing slowmode.');
  }

  @override
  Future<CircleNotificationSettings> getNotificationSettings(
    String circleId,
  ) async {
    return CircleNotificationSettings(circleId: circleId);
  }

  @override
  Future<CircleNotificationSettings> setNotificationSettings({
    required String circleId,
    required CircleNotificationLevel level,
    DateTime? mutedUntil,
  }) {
    throw StateError(
      'Supabase must be initialized before changing notification settings.',
    );
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
