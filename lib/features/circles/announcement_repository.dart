import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_rpc.dart';

/// A follow of an announcement channel, as the following channel's
/// settings list it.
class ChannelFollow {
  const ChannelFollow({
    required this.id,
    required this.sourceChannelId,
    required this.sourceChannelName,
    required this.sourceCircleId,
    required this.sourceCircleName,
    required this.targetChannelId,
    this.creatorName,
  });

  factory ChannelFollow.fromJson(Map<String, dynamic> json) {
    return ChannelFollow(
      id: json['id'] as String,
      sourceChannelId: json['source_channel_id'] as String,
      sourceChannelName: json['source_channel_name'] as String? ?? '',
      sourceCircleId: json['source_circle_id'] as String,
      sourceCircleName: json['source_circle_name'] as String? ?? '',
      targetChannelId: json['target_channel_id'] as String,
      creatorName: json['creator_name'] as String?,
    );
  }

  final String id;
  final String sourceChannelId;
  final String sourceChannelName;
  final String sourceCircleId;
  final String sourceCircleName;
  final String targetChannelId;

  /// Who set the follow up; published posts arrive as sent by them.
  final String? creatorName;
}

/// A channel an announcement channel can be followed into.
class FollowTarget {
  const FollowTarget({
    required this.channelId,
    required this.channelName,
    required this.circleId,
    required this.circleName,
    this.isFollowing = false,
  });

  factory FollowTarget.fromJson(Map<String, dynamic> json) {
    return FollowTarget(
      channelId: json['channel_id'] as String,
      channelName: json['channel_name'] as String? ?? '',
      circleId: json['circle_id'] as String,
      circleName: json['circle_name'] as String? ?? '',
      isFollowing: json['is_following'] == true,
    );
  }

  final String channelId;
  final String channelName;
  final String circleId;
  final String circleName;

  /// Already follows the announcement channel.
  final bool isFollowing;
}

final announcementRepositoryProvider = Provider<AnnouncementRepository>((ref) {
  return AnnouncementRepository(ref.watch(circleRpcProvider));
});

/// The follows into a channel, for its settings.
final channelFollowsProvider = FutureProvider.autoDispose
    .family<List<ChannelFollow>, String>((ref, channelId) {
      return ref.watch(announcementRepositoryProvider).listFollows(channelId);
    });

/// Announcement channels: converting, following and publishing.
class AnnouncementRepository {
  const AnnouncementRepository(this._rpc);

  final CircleRpc _rpc;

  /// Turns a text channel into an announcement channel, or back (which
  /// removes every follow of it).
  Future<void> setAnnouncementChannel({
    required String channelId,
    required bool enabled,
  }) async {
    await _rpc('set_channel_announcement', {
      'target_channel_id': channelId,
      'enabled': enabled,
    });
  }

  /// The channels of the current user's circles that [sourceChannelId]
  /// can be followed into.
  Future<List<FollowTarget>> listFollowTargets(String sourceChannelId) async {
    final rows = await _rpc('list_follow_targets', {
      'source_channel_id': sourceChannelId,
    });
    return rpcRows(rows).map(FollowTarget.fromJson).toList();
  }

  Future<ChannelFollow> follow({
    required String sourceChannelId,
    required String targetChannelId,
  }) async {
    final result = await _rpc('follow_announcement_channel', {
      'source_channel_id': sourceChannelId,
      'target_channel_id': targetChannelId,
    });
    return ChannelFollow.fromJson(rpcObject(result));
  }

  Future<void> unfollow(String followId) async {
    await _rpc('unfollow_announcement_channel', {'target_follow_id': followId});
  }

  Future<List<ChannelFollow>> listFollows(String targetChannelId) async {
    final rows = await _rpc('list_channel_follows', {
      'target_channel_id': targetChannelId,
    });
    return rpcRows(rows).map(ChannelFollow.fromJson).toList();
  }

  /// Publishes a message to every following channel; returns how many
  /// received it.
  Future<int> publish(String messageId) async {
    final result = await _rpc('publish_message', {
      'target_message_id': messageId,
    });
    return (result as num?)?.toInt() ?? 0;
  }
}
