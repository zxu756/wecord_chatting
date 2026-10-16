import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/channel_webhook.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_audit_entry.dart';
import 'package:wecord/shared/models/circle_ban.dart';
import 'package:wecord/shared/models/circle_channel_overwrite.dart';
import 'package:wecord/shared/models/circle_event.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/shared/models/circle_notification_settings.dart';
import 'package:wecord/shared/models/forum.dart';
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

  /// Creates a channel of [kind], in [categoryId] when given.
  Future<String> createChannel({
    required String circleId,
    required String name,
    String? categoryId,
    CircleChannelKind kind = CircleChannelKind.text,
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

  /// Bans [userId] (a member or not) from the circle, removing them if they
  /// are a member, and deletes their circle messages from the last
  /// [deleteMessageHours] (0 keeps them).
  Future<void> banMember({
    required String circleId,
    required String userId,
    String? reason,
    int deleteMessageHours = 0,
  });

  Future<void> unbanMember({required String circleId, required String userId});

  /// Who is banned, newest first.
  Future<List<CircleBan>> listBans(String circleId);

  /// Times [userId] out for [duration], or ends their timeout with
  /// [Duration.zero]. Returns when the timeout ends.
  Future<DateTime?> timeoutMember({
    required String circleId,
    required String userId,
    required Duration duration,
  });

  /// Leaves the circle and all of its channels. The owner must transfer
  /// ownership first.
  Future<void> leaveCircle(String circleId);

  /// Makes [newOwnerId] the circle's owner; the current owner stays as a
  /// member without roles.
  Future<void> transferOwnership({
    required String circleId,
    required String newOwnerId,
  });

  /// A page of the circle's audit log, newest first: entries older than
  /// [before] (from the newest when null), at most [limit]. [action] is an
  /// action or an action group's filter (see `CircleAuditActionGroup`).
  Future<List<CircleAuditEntry>> listAuditLog({
    required String circleId,
    DateTime? before,
    int limit = 50,
    String? action,
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

  /// Renames a channel and sets its topic; a null or blank [topic] clears
  /// it.
  Future<void> updateChannel({
    required String channelId,
    required String name,
    String? topic,
  });

  /// Deletes a channel with its messages and threads.
  Future<void> deleteChannel(String channelId);

  /// The webhooks of a channel, oldest first (without their tokens).
  Future<List<ChannelWebhook>> listChannelWebhooks(String channelId);

  /// Creates a webhook; the returned token is never shown again.
  Future<ChannelWebhookSecret> createChannelWebhook({
    required String channelId,
    required String name,
  });

  Future<ChannelWebhook> renameChannelWebhook({
    required String webhookId,
    required String name,
  });

  /// Replaces a webhook's token, so its old URL stops working.
  Future<ChannelWebhookSecret> regenerateWebhookToken(String webhookId);

  Future<void> deleteChannelWebhook(String webhookId);

  /// The circle's upcoming and ongoing events by start time; with
  /// [includePast] also ended and cancelled ones. Events in channels the
  /// current user cannot see are left out.
  Future<List<CircleEvent>> listEvents({
    required String circleId,
    bool includePast = false,
  });

  /// Schedules an event (needs manage events). Voice and text events take
  /// [channelId], external ones [locationText].
  Future<CircleEvent> createEvent({
    required String circleId,
    required String title,
    String? description,
    required CircleEventLocationType locationType,
    String? channelId,
    String? locationText,
    required DateTime startsAt,
    DateTime? endsAt,
  });

  /// Changes an event (its creator or members who manage events).
  Future<CircleEvent> updateEvent({
    required String eventId,
    required String title,
    String? description,
    required CircleEventLocationType locationType,
    String? channelId,
    String? locationText,
    required DateTime startsAt,
    DateTime? endsAt,
  });

  Future<CircleEvent> cancelEvent(String eventId);

  /// Marks the current user interested in an event, or not any more, and
  /// returns the new state.
  Future<bool> toggleEventInterest(String eventId);

  /// The members interested in an event, first first.
  Future<List<CircleEventPerson>> listEventInterested(String eventId);

  /// Events the current user is interested in that start within a day.
  Future<List<CircleEventReminder>> listMyEventReminders();

  /// A page of a forum's posts: pinned posts first (on the first page,
  /// when [before] is null), then up to [limit] others by [sort], newest
  /// first, optionally only those tagged [tagId].
  Future<List<ForumPost>> listForumPosts({
    required String channelId,
    ForumPostSort sort = ForumPostSort.activity,
    String? tagId,
    ForumPostCursor? before,
    int limit = 25,
  });

  /// Creates a post with its body (and [image], uploaded with
  /// [uploadForumImage]) as the first message. [mentions] index into the
  /// trimmed body; mentions of members who cannot see the forum are dropped.
  Future<ForumPost> createForumPost({
    required String channelId,
    required String title,
    required String body,
    List<String> tagIds = const [],
    ImageAttachment? image,
    List<MessageMention> mentions = const [],
  });

  /// Uploads an image for a new post of the forum whose conversation is
  /// [forumConversationId].
  Future<ImageAttachment> uploadForumImage({
    required String forumConversationId,
    required ChatImageUpload image,
  });

  /// Replaces a post's tags (at most [ForumTag.maxPerPost]).
  Future<void> setForumPostTags({
    required String threadId,
    required List<String> tagIds,
  });

  Future<void> pinForumPost({required String threadId, required bool pinned});

  /// Adds a tag at the end of a forum's tags and returns its id.
  Future<String> createForumTag({
    required String channelId,
    required String name,
    String? emoji,
  });

  /// Renames a tag; a null or blank [emoji] clears it.
  Future<void> updateForumTag({
    required String tagId,
    required String name,
    String? emoji,
  });

  Future<void> deleteForumTag(String tagId);

  /// Stores the order of every tag of a forum.
  Future<void> reorderForumTags({
    required String channelId,
    required List<String> tagIds,
  });

  /// Fires when a forum's posts or their tags change.
  Stream<void> forumChanges({
    required String channelId,
    required String conversationId,
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
  String toString() => tr('You are no longer a member of this circle.');
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

  Future<void> removeObjects({
    required String bucket,
    required List<String> paths,
  });

  Stream<void> circleChanges(String circleId);

  Stream<void> forumChanges({
    required String channelId,
    required String conversationId,
  });
}

class SupabaseCirclesRepository implements CirclesRepository {
  const SupabaseCirclesRepository(
    this._dataSource, {
    this._storagePathSeed,
    this._storageOperationTimeout = const Duration(seconds: 30),
  });

  const SupabaseCirclesRepository.withDataSource(
    this._dataSource, {
    this._storagePathSeed,
    this._storageOperationTimeout = const Duration(seconds: 30),
  });

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
    CircleChannelKind kind = CircleChannelKind.text,
  }) async {
    final channelId = await _dataSource.rpc('create_circle_channel', {
      'target_circle_id': circleId,
      'channel_name': name.trim(),
      'target_category_id': ?categoryId,
      if (kind != CircleChannelKind.text) 'target_kind': kind.value,
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
  Future<void> banMember({
    required String circleId,
    required String userId,
    String? reason,
    int deleteMessageHours = 0,
  }) async {
    final trimmedReason = reason?.trim();
    final result = await _dataSource.rpc('ban_circle_member', {
      'target_circle_id': circleId,
      'target_user_id': userId,
      'ban_reason': trimmedReason == null || trimmedReason.isEmpty
          ? null
          : trimmedReason,
      'delete_message_hours': deleteMessageHours,
    });
    // Deleted messages' images and voice clips nothing else uses; removing
    // them is best effort, as when deleting a single message.
    await _removeDeletedMedia(result);
  }

  /// Removes the `{bucket_id, object_path}` rows an RPC returned for
  /// messages it deleted. Best effort: the deletion is done, and a leftover
  /// file is harmless.
  Future<void> _removeDeletedMedia(Object? rows) async {
    final pathsByBucket = <String, List<String>>{};
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map) {
          continue;
        }
        final bucket = row['bucket_id'];
        final path = row['object_path'];
        if (bucket is String && path is String) {
          pathsByBucket.putIfAbsent(bucket, () => []).add(path);
        }
      }
    }
    for (final MapEntry(key: bucket, value: paths) in pathsByBucket.entries) {
      // Storage removes at most 1000 objects per request.
      for (var start = 0; start < paths.length; start += 1000) {
        final end = start + 1000 < paths.length ? start + 1000 : paths.length;
        try {
          await _withStorageTimeout(
            _dataSource.removeObjects(
              bucket: bucket,
              paths: paths.sublist(start, end),
            ),
          );
        } catch (_) {
          // Leave the file behind.
        }
      }
    }
  }

  @override
  Future<void> unbanMember({
    required String circleId,
    required String userId,
  }) async {
    await _dataSource.rpc('unban_circle_member', {
      'target_circle_id': circleId,
      'target_user_id': userId,
    });
  }

  @override
  Future<List<CircleBan>> listBans(String circleId) async {
    final result = await _dataSource.rpc('list_circle_bans', {
      'target_circle_id': circleId,
    });
    if (result is! List) {
      return const [];
    }
    return [
      for (final row in result)
        if (row is Map<String, dynamic>) CircleBan.fromJson(row),
    ];
  }

  @override
  Future<DateTime?> timeoutMember({
    required String circleId,
    required String userId,
    required Duration duration,
  }) async {
    final result = await _dataSource.rpc('timeout_circle_member', {
      'target_circle_id': circleId,
      'target_user_id': userId,
      'duration_seconds': duration.inSeconds,
    });
    return result is String ? DateTime.tryParse(result) : null;
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
  Future<List<CircleAuditEntry>> listAuditLog({
    required String circleId,
    DateTime? before,
    int limit = 50,
    String? action,
  }) async {
    final rows = await _dataSource.rpc('list_circle_audit_log', {
      'target_circle_id': circleId,
      'before': before?.toUtc().toIso8601String(),
      'limit_count': limit,
      'action_filter': action,
    });
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(CircleAuditEntry.fromJson)
        .toList(growable: false);
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
  Future<void> updateChannel({
    required String channelId,
    required String name,
    String? topic,
  }) async {
    final trimmedTopic = topic?.trim();
    await _dataSource.rpc('update_circle_channel', {
      'target_channel_id': channelId,
      'channel_name': name.trim(),
      'channel_topic': trimmedTopic == null || trimmedTopic.isEmpty
          ? null
          : trimmedTopic,
    });
  }

  @override
  Future<void> deleteChannel(String channelId) async {
    final result = await _dataSource.rpc('delete_circle_channel', {
      'target_channel_id': channelId,
    });
    // The files of the channel's messages that nothing else uses.
    await _removeDeletedMedia(result);
  }

  @override
  Future<List<ChannelWebhook>> listChannelWebhooks(String channelId) async {
    final rows = await _dataSource.rpc('list_channel_webhooks', {
      'target_channel_id': channelId,
    });
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ChannelWebhook.fromJson)
        .toList(growable: false);
  }

  @override
  Future<ChannelWebhookSecret> createChannelWebhook({
    required String channelId,
    required String name,
  }) async {
    final payload = await _dataSource.rpc('create_channel_webhook', {
      'target_channel_id': channelId,
      'webhook_name': name.trim(),
    });
    return ChannelWebhookSecret.fromJson(payload as Map<String, dynamic>);
  }

  @override
  Future<ChannelWebhook> renameChannelWebhook({
    required String webhookId,
    required String name,
  }) async {
    final payload = await _dataSource.rpc('rename_channel_webhook', {
      'target_webhook_id': webhookId,
      'webhook_name': name.trim(),
    });
    return ChannelWebhook.fromJson(payload as Map<String, dynamic>);
  }

  @override
  Future<ChannelWebhookSecret> regenerateWebhookToken(String webhookId) async {
    final payload = await _dataSource.rpc('regenerate_webhook_token', {
      'target_webhook_id': webhookId,
    });
    return ChannelWebhookSecret.fromJson(payload as Map<String, dynamic>);
  }

  @override
  Future<void> deleteChannelWebhook(String webhookId) async {
    await _dataSource.rpc('delete_channel_webhook', {
      'target_webhook_id': webhookId,
    });
  }

  @override
  Future<List<CircleEvent>> listEvents({
    required String circleId,
    bool includePast = false,
  }) async {
    final rows = await _dataSource.rpc('list_circle_events', {
      'target_circle_id': circleId,
      'include_past': includePast,
    });
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(CircleEvent.fromJson)
        .toList(growable: false);
  }

  @override
  Future<CircleEvent> createEvent({
    required String circleId,
    required String title,
    String? description,
    required CircleEventLocationType locationType,
    String? channelId,
    String? locationText,
    required DateTime startsAt,
    DateTime? endsAt,
  }) async {
    final payload = await _dataSource.rpc('create_circle_event', {
      'target_circle_id': circleId,
      ..._eventFields(
        title: title,
        description: description,
        locationType: locationType,
        channelId: channelId,
        locationText: locationText,
        startsAt: startsAt,
        endsAt: endsAt,
      ),
    });
    return CircleEvent.fromJson(payload as Map<String, dynamic>);
  }

  @override
  Future<CircleEvent> updateEvent({
    required String eventId,
    required String title,
    String? description,
    required CircleEventLocationType locationType,
    String? channelId,
    String? locationText,
    required DateTime startsAt,
    DateTime? endsAt,
  }) async {
    final payload = await _dataSource.rpc('update_circle_event', {
      'target_event_id': eventId,
      ..._eventFields(
        title: title,
        description: description,
        locationType: locationType,
        channelId: channelId,
        locationText: locationText,
        startsAt: startsAt,
        endsAt: endsAt,
      ),
    });
    return CircleEvent.fromJson(payload as Map<String, dynamic>);
  }

  Map<String, dynamic> _eventFields({
    required String title,
    required String? description,
    required CircleEventLocationType locationType,
    required String? channelId,
    required String? locationText,
    required DateTime startsAt,
    required DateTime? endsAt,
  }) {
    final external = locationType == CircleEventLocationType.external;
    final trimmedDescription = description?.trim();
    return {
      'event_title': title.trim(),
      'event_description':
          trimmedDescription == null || trimmedDescription.isEmpty
          ? null
          : trimmedDescription,
      'event_location_type': locationType.value,
      'event_channel_id': external ? null : channelId,
      'event_location_text': external ? locationText?.trim() : null,
      'event_starts_at': startsAt.toUtc().toIso8601String(),
      'event_ends_at': endsAt?.toUtc().toIso8601String(),
    };
  }

  @override
  Future<CircleEvent> cancelEvent(String eventId) async {
    final payload = await _dataSource.rpc('cancel_circle_event', {
      'target_event_id': eventId,
    });
    return CircleEvent.fromJson(payload as Map<String, dynamic>);
  }

  @override
  Future<bool> toggleEventInterest(String eventId) async {
    final interested = await _dataSource.rpc('toggle_event_interest', {
      'target_event_id': eventId,
    });
    return interested == true;
  }

  @override
  Future<List<CircleEventPerson>> listEventInterested(String eventId) async {
    final rows = await _dataSource.rpc('list_event_interested', {
      'target_event_id': eventId,
    });
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(CircleEventPerson.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<CircleEventReminder>> listMyEventReminders() async {
    final rows = await _dataSource.rpc(
      'list_my_upcoming_event_reminders',
      const {},
    );
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(CircleEventReminder.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<ForumPost>> listForumPosts({
    required String channelId,
    ForumPostSort sort = ForumPostSort.activity,
    String? tagId,
    ForumPostCursor? before,
    int limit = 25,
  }) async {
    final rows = await _dataSource.rpc('list_forum_posts', {
      'target_channel_id': channelId,
      'sort_order': sort.value,
      'filter_tag_id': tagId,
      'before_at': before?.at.toUtc().toIso8601String(),
      'before_id': before?.id,
      'limit_count': limit,
    });
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ForumPost.fromJson)
        .toList(growable: false);
  }

  @override
  Future<ForumPost> createForumPost({
    required String channelId,
    required String title,
    required String body,
    List<String> tagIds = const [],
    ImageAttachment? image,
    List<MessageMention> mentions = const [],
  }) async {
    final payload = await _dataSource.rpc('create_forum_post', {
      'target_channel_id': channelId,
      'post_title': title.trim(),
      'post_body': body.trim(),
      'tag_ids': tagIds,
      'post_attachment': image?.toJson(),
      'post_mentions': [for (final mention in mentions) mention.toJson()],
    });
    final post = payload as Map<String, dynamic>;
    // AutoMod refuses a post quietly, so that its alerts and timeouts stay,
    // and leaves a note of why under the forum's conversation.
    if (post['automod_blocked'] == true) {
      Map<String, dynamic>? notice;
      final conversationId = post['conversation_id'];
      if (conversationId is String) {
        try {
          final result = await _dataSource.rpc('take_automod_notice', {
            'target_conversation_id': conversationId,
          });
          notice = result is Map<String, dynamic> ? result : null;
        } catch (_) {
          notice = null;
        }
      }
      throw AutoModBlockedException(notice?['reason'] as String?);
    }
    return ForumPost.fromJson(post);
  }

  @override
  Future<ImageAttachment> uploadForumImage({
    required String forumConversationId,
    required ChatImageUpload image,
  }) async {
    // Chat images live under their conversation; a post's image goes under
    // the forum's, where members who can post may upload.
    const bucket = 'chat-images';
    final path =
        '$forumConversationId/${_nextStoragePathSeed()}-${_safeFileName(image.fileName)}';
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
  Future<void> setForumPostTags({
    required String threadId,
    required List<String> tagIds,
  }) async {
    await _dataSource.rpc('set_forum_post_tags', {
      'target_thread_id': threadId,
      'tag_ids': tagIds,
    });
  }

  @override
  Future<void> pinForumPost({
    required String threadId,
    required bool pinned,
  }) async {
    await _dataSource.rpc('pin_forum_post', {
      'target_thread_id': threadId,
      'pinned': pinned,
    });
  }

  @override
  Future<String> createForumTag({
    required String channelId,
    required String name,
    String? emoji,
  }) async {
    final tagId = await _dataSource.rpc('create_forum_tag', {
      'target_channel_id': channelId,
      'tag_name': name.trim(),
      'tag_emoji': _blankToNull(emoji),
    });
    return tagId as String;
  }

  @override
  Future<void> updateForumTag({
    required String tagId,
    required String name,
    String? emoji,
  }) async {
    await _dataSource.rpc('update_forum_tag', {
      'target_tag_id': tagId,
      'tag_name': name.trim(),
      'tag_emoji': _blankToNull(emoji),
    });
  }

  @override
  Future<void> deleteForumTag(String tagId) async {
    await _dataSource.rpc('delete_forum_tag', {'target_tag_id': tagId});
  }

  @override
  Future<void> reorderForumTags({
    required String channelId,
    required List<String> tagIds,
  }) async {
    await _dataSource.rpc('reorder_forum_tags', {
      'target_channel_id': channelId,
      'tag_ids': tagIds,
    });
  }

  @override
  Stream<void> forumChanges({
    required String channelId,
    required String conversationId,
  }) {
    return _dataSource.forumChanges(
      channelId: channelId,
      conversationId: conversationId,
    );
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
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
  Future<void> removeObjects({
    required String bucket,
    required List<String> paths,
  }) async {
    await _client.storage.from(bucket).remove(paths);
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
              table: 'forum_tags',
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
              table: 'circle_events',
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
              table: 'circle_event_rsvps',
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

  @override
  Stream<void> forumChanges({
    required String channelId,
    required String conversationId,
  }) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        void emit(PostgresChangePayload payload) {
          controller.add(null);
        }

        channel = _client
            .channel('forum-changes-$channelId')
            // New posts, pins, archiving and activity (every reply bumps
            // the post's last_message_at).
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'conversation_threads',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'parent_conversation_id',
                value: conversationId,
              ),
              callback: emit,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'thread_tags',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'channel_id',
                value: channelId,
              ),
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
    CircleChannelKind kind = CircleChannelKind.text,
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
  Future<void> banMember({
    required String circleId,
    required String userId,
    String? reason,
    int deleteMessageHours = 0,
  }) {
    throw StateError('Supabase must be initialized before banning members.');
  }

  @override
  Future<void> unbanMember({required String circleId, required String userId}) {
    throw StateError('Supabase must be initialized before unbanning members.');
  }

  @override
  Future<List<CircleBan>> listBans(String circleId) {
    throw StateError('Supabase must be initialized before listing bans.');
  }

  @override
  Future<DateTime?> timeoutMember({
    required String circleId,
    required String userId,
    required Duration duration,
  }) {
    throw StateError('Supabase must be initialized before timing out members.');
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
  Future<List<CircleAuditEntry>> listAuditLog({
    required String circleId,
    DateTime? before,
    int limit = 50,
    String? action,
  }) async {
    return const [];
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
  Future<void> updateChannel({
    required String channelId,
    required String name,
    String? topic,
  }) {
    throw StateError('Supabase must be initialized before editing channels.');
  }

  @override
  Future<void> deleteChannel(String channelId) {
    throw StateError('Supabase must be initialized before deleting channels.');
  }

  @override
  Future<List<ChannelWebhook>> listChannelWebhooks(String channelId) async {
    return const [];
  }

  @override
  Future<ChannelWebhookSecret> createChannelWebhook({
    required String channelId,
    required String name,
  }) {
    throw StateError('Supabase must be initialized before creating webhooks.');
  }

  @override
  Future<ChannelWebhook> renameChannelWebhook({
    required String webhookId,
    required String name,
  }) {
    throw StateError('Supabase must be initialized before renaming webhooks.');
  }

  @override
  Future<ChannelWebhookSecret> regenerateWebhookToken(String webhookId) {
    throw StateError('Supabase must be initialized before changing webhooks.');
  }

  @override
  Future<void> deleteChannelWebhook(String webhookId) {
    throw StateError('Supabase must be initialized before deleting webhooks.');
  }

  @override
  Future<List<CircleEvent>> listEvents({
    required String circleId,
    bool includePast = false,
  }) async {
    return const [];
  }

  @override
  Future<CircleEvent> createEvent({
    required String circleId,
    required String title,
    String? description,
    required CircleEventLocationType locationType,
    String? channelId,
    String? locationText,
    required DateTime startsAt,
    DateTime? endsAt,
  }) {
    throw StateError('Supabase must be initialized before creating events.');
  }

  @override
  Future<CircleEvent> updateEvent({
    required String eventId,
    required String title,
    String? description,
    required CircleEventLocationType locationType,
    String? channelId,
    String? locationText,
    required DateTime startsAt,
    DateTime? endsAt,
  }) {
    throw StateError('Supabase must be initialized before editing events.');
  }

  @override
  Future<CircleEvent> cancelEvent(String eventId) {
    throw StateError('Supabase must be initialized before cancelling events.');
  }

  @override
  Future<bool> toggleEventInterest(String eventId) {
    throw StateError('Supabase must be initialized before marking interest.');
  }

  @override
  Future<List<CircleEventPerson>> listEventInterested(String eventId) async {
    return const [];
  }

  @override
  Future<List<CircleEventReminder>> listMyEventReminders() async {
    return const [];
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

  @override
  Future<List<ForumPost>> listForumPosts({
    required String channelId,
    ForumPostSort sort = ForumPostSort.activity,
    String? tagId,
    ForumPostCursor? before,
    int limit = 25,
  }) async {
    return const [];
  }

  @override
  Future<ForumPost> createForumPost({
    required String channelId,
    required String title,
    required String body,
    List<String> tagIds = const [],
    ImageAttachment? image,
    List<MessageMention> mentions = const [],
  }) {
    throw StateError('Supabase must be initialized before posting.');
  }

  @override
  Future<ImageAttachment> uploadForumImage({
    required String forumConversationId,
    required ChatImageUpload image,
  }) {
    throw StateError('Supabase must be initialized before uploading images.');
  }

  @override
  Future<void> setForumPostTags({
    required String threadId,
    required List<String> tagIds,
  }) {
    throw StateError('Supabase must be initialized before tagging posts.');
  }

  @override
  Future<void> pinForumPost({required String threadId, required bool pinned}) {
    throw StateError('Supabase must be initialized before pinning posts.');
  }

  @override
  Future<String> createForumTag({
    required String channelId,
    required String name,
    String? emoji,
  }) {
    throw StateError('Supabase must be initialized before creating tags.');
  }

  @override
  Future<void> updateForumTag({
    required String tagId,
    required String name,
    String? emoji,
  }) {
    throw StateError('Supabase must be initialized before editing tags.');
  }

  @override
  Future<void> deleteForumTag(String tagId) {
    throw StateError('Supabase must be initialized before deleting tags.');
  }

  @override
  Future<void> reorderForumTags({
    required String channelId,
    required List<String> tagIds,
  }) {
    throw StateError('Supabase must be initialized before reordering tags.');
  }

  @override
  Stream<void> forumChanges({
    required String channelId,
    required String conversationId,
  }) {
    return const Stream<void>.empty();
  }
}

extension ReportReasonJson on ReportReason {
  String toJson() => value;
}
