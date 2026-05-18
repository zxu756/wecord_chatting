import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

class CircleSummary {
  const CircleSummary({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.channelCount,
    this.avatarUrl,
    this.latestActivityAt,
    this.currentUserRole,
  });

  factory CircleSummary.fromJson(Map<String, dynamic> json) {
    return CircleSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      channelCount: (json['channel_count'] as num?)?.toInt() ?? 0,
      latestActivityAt: _parseOptionalTimestamp(json['latest_activity_at']),
      currentUserRole: json['current_user_role'] as String?,
    );
  }

  final String id;
  final String name;
  final String? avatarUrl;
  final int memberCount;
  final int channelCount;
  final DateTime? latestActivityAt;
  final String? currentUserRole;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar_url': avatarUrl,
      'member_count': memberCount,
      'channel_count': channelCount,
      'latest_activity_at': latestActivityAt?.toIso8601String(),
      'current_user_role': currentUserRole,
    };
  }
}

class CircleDetail {
  const CircleDetail({
    required this.circle,
    required this.members,
    required this.channels,
    required this.posts,
  });

  factory CircleDetail.fromJson(Map<String, dynamic> json) {
    return CircleDetail(
      circle: CircleSummary.fromJson(json['circle'] as Map<String, dynamic>),
      members: _parseList(json['members'], CircleMember.fromJson),
      channels: _parseList(json['channels'], CircleChannel.fromJson),
      posts: _parseList(json['posts'], CirclePost.fromJson),
    );
  }

  final CircleSummary circle;
  final List<CircleMember> members;
  final List<CircleChannel> channels;
  final List<CirclePost> posts;

  bool get canManageCircle =>
      circle.currentUserRole == 'owner' || circle.currentUserRole == 'admin';
}

class CircleMember {
  const CircleMember({required this.profile, required this.role});

  factory CircleMember.fromJson(Map<String, dynamic> json) {
    return CircleMember(
      role: json['role'] as String,
      profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
    );
  }

  final Profile profile;
  final String role;
}

class CircleChannel {
  const CircleChannel({
    required this.id,
    required this.circleId,
    required this.conversationId,
    required this.name,
    required this.position,
  });

  factory CircleChannel.fromJson(Map<String, dynamic> json) {
    return CircleChannel(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      conversationId: json['conversation_id'] as String,
      name: json['name'] as String,
      position: (json['position'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String circleId;
  final String conversationId;
  final String name;
  final int position;
}

class CirclePost {
  const CirclePost({
    required this.id,
    required this.circleId,
    required this.authorId,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.author,
    required this.comments,
    this.attachment,
    this.deletedAt,
    this.isOwnPost = false,
    this.canManagePost = false,
    this.likeCount = 0,
    this.commentCount = 0,
    this.likedByCurrentUser = false,
  });

  factory CirclePost.fromJson(Map<String, dynamic> json) {
    return CirclePost(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      authorId: json['author_id'] as String,
      body: json['body'] as String? ?? '',
      attachment: json['attachment'] as Map<String, dynamic>?,
      createdAt: _parseTimestamp(json['created_at']),
      updatedAt: _parseTimestamp(json['updated_at']),
      deletedAt: _parseOptionalTimestamp(json['deleted_at']),
      author: Profile.fromJson(json['author'] as Map<String, dynamic>),
      comments: _parseList(json['comments'], CirclePostComment.fromJson),
      isOwnPost: json['is_own_post'] as bool? ?? false,
      canManagePost: json['can_manage_post'] as bool? ?? false,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      likedByCurrentUser: json['liked_by_current_user'] as bool? ?? false,
    );
  }

  final String id;
  final String circleId;
  final String authorId;
  final String body;
  final Map<String, dynamic>? attachment;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final Profile author;
  final List<CirclePostComment> comments;
  final bool isOwnPost;
  final bool canManagePost;
  final int likeCount;
  final int commentCount;
  final bool likedByCurrentUser;

  ImageAttachment? get imageAttachment {
    final value = attachment;
    if (value == null || value['kind'] != 'image') {
      return null;
    }
    return ImageAttachment.fromJson(value);
  }
}

class CirclePostComment {
  const CirclePostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.author,
    this.deletedAt,
  });

  factory CirclePostComment.fromJson(Map<String, dynamic> json) {
    return CirclePostComment(
      id: json['id'] as String,
      postId: json['post_id'] as String,
      authorId: json['author_id'] as String,
      body: json['body'] as String? ?? '',
      createdAt: _parseTimestamp(json['created_at']),
      updatedAt: _parseTimestamp(json['updated_at']),
      deletedAt: _parseOptionalTimestamp(json['deleted_at']),
      author: Profile.fromJson(json['author'] as Map<String, dynamic>),
    );
  }

  final String id;
  final String postId;
  final String authorId;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final Profile author;
}

DateTime _parseTimestamp(Object? value) {
  return DateTime.parse(value as String).toUtc();
}

DateTime? _parseOptionalTimestamp(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String).toUtc();
}

List<T> _parseList<T>(
  Object? value,
  T Function(Map<String, dynamic> json) parser,
) {
  return (value as List<dynamic>? ?? const <dynamic>[])
      .map((item) => parser(item as Map<String, dynamic>))
      .toList();
}
