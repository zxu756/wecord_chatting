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
    this.unreadCount = 0,
    this.mentionCount = 0,
    this.isMuted = false,
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
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      mentionCount: (json['mention_count'] as num?)?.toInt() ?? 0,
      isMuted: json['is_muted'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final String? avatarUrl;
  final int memberCount;
  final int channelCount;
  final DateTime? latestActivityAt;
  final String? currentUserRole;

  /// Unread messages across the circle's channels.
  final int unreadCount;

  /// Unread messages mentioning the current user across the channels.
  final int mentionCount;

  /// Muted or set to notify about nothing: shown dimmed, not highlighted.
  final bool isMuted;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar_url': avatarUrl,
      'member_count': memberCount,
      'channel_count': channelCount,
      'latest_activity_at': latestActivityAt?.toIso8601String(),
      'current_user_role': currentUserRole,
      'unread_count': unreadCount,
      'mention_count': mentionCount,
      'is_muted': isMuted,
    };
  }
}

class CircleDetail {
  const CircleDetail({
    required this.circle,
    required this.members,
    required this.channels,
    required this.posts,
    this.categories = const [],
  });

  factory CircleDetail.fromJson(Map<String, dynamic> json) {
    return CircleDetail(
      circle: CircleSummary.fromJson(json['circle'] as Map<String, dynamic>),
      members: _parseList(json['members'], CircleMember.fromJson),
      channels: _parseList(json['channels'], CircleChannel.fromJson),
      categories: _parseList(
        json['categories'],
        CircleChannelCategory.fromJson,
      ),
      posts: _parseList(json['posts'], CirclePost.fromJson),
    );
  }

  final CircleSummary circle;
  final List<CircleMember> members;

  /// Every channel, ordered by position.
  final List<CircleChannel> channels;

  /// Channel categories, ordered by position.
  final List<CircleChannelCategory> categories;
  final List<CirclePost> posts;

  bool get canManageCircle =>
      circle.currentUserRole == 'owner' || circle.currentUserRole == 'admin';

  /// Everyone may rename themselves; owners and admins may rename others,
  /// but only the owner may rename the owner.
  bool canChangeNickname(CircleMember member) {
    if (member.isCurrentUser) {
      return true;
    }
    if (!canManageCircle) {
      return false;
    }
    return member.role != 'owner' || circle.currentUserRole == 'owner';
  }
}

class CircleMember {
  const CircleMember({
    required this.profile,
    required this.role,
    this.nickname,
    this.isCurrentUser = false,
  });

  factory CircleMember.fromJson(Map<String, dynamic> json) {
    return CircleMember(
      role: json['role'] as String,
      profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
      nickname: json['nickname'] as String?,
      isCurrentUser: json['is_current_user'] == true,
    );
  }

  final Profile profile;
  final String role;

  /// This circle's nickname for the member, if they have one.
  final String? nickname;
  final bool isCurrentUser;

  /// The name shown inside the circle: nickname, then display name, then
  /// username.
  String get displayName {
    final nickname = this.nickname?.trim();
    if (nickname != null && nickname.isNotEmpty) {
      return nickname;
    }
    return profile.displayName.trim().isEmpty
        ? profile.username
        : profile.displayName;
  }
}

class CircleChannel {
  const CircleChannel({
    required this.id,
    required this.circleId,
    required this.conversationId,
    required this.name,
    required this.position,
    this.categoryId,
  });

  factory CircleChannel.fromJson(Map<String, dynamic> json) {
    return CircleChannel(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      conversationId: json['conversation_id'] as String,
      name: json['name'] as String,
      position: (json['position'] as num?)?.toInt() ?? 0,
      categoryId: json['category_id'] as String?,
    );
  }

  final String id;
  final String circleId;
  final String conversationId;
  final String name;
  final int position;

  /// Null for channels listed above every category.
  final String? categoryId;
}

class CircleChannelCategory {
  const CircleChannelCategory({
    required this.id,
    required this.circleId,
    required this.name,
    required this.position,
  });

  factory CircleChannelCategory.fromJson(Map<String, dynamic> json) {
    return CircleChannelCategory(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      name: json['name'] as String,
      position: (json['position'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String circleId;
  final String name;
  final int position;
}

/// The order of a circle's categories and channels: uncategorized channels
/// first, then each category with its channels. This is what
/// `reorder_circle_channels` stores.
class CircleChannelLayout {
  const CircleChannelLayout({
    required this.categories,
    required this.uncategorized,
    required this.channelsByCategory,
  });

  /// Groups [channels] (already in position order) under [categories].
  /// Channels pointing at an unknown category count as uncategorized.
  factory CircleChannelLayout.fromChannels({
    required List<CircleChannelCategory> categories,
    required List<CircleChannel> channels,
  }) {
    final channelsByCategory = {
      for (final category in categories) category.id: <CircleChannel>[],
    };
    final uncategorized = <CircleChannel>[];
    for (final channel in channels) {
      (channelsByCategory[channel.categoryId] ?? uncategorized).add(channel);
    }
    return CircleChannelLayout(
      categories: List.unmodifiable(categories),
      uncategorized: List.unmodifiable(uncategorized),
      channelsByCategory: {
        for (final entry in channelsByCategory.entries)
          entry.key: List.unmodifiable(entry.value),
      },
    );
  }

  final List<CircleChannelCategory> categories;
  final List<CircleChannel> uncategorized;
  final Map<String, List<CircleChannel>> channelsByCategory;

  /// Channels of [categoryId], or the uncategorized ones for null.
  List<CircleChannel> channelsIn(String? categoryId) {
    return categoryId == null
        ? uncategorized
        : channelsByCategory[categoryId] ?? const [];
  }

  /// Moves [channelId] into [categoryId] (null: uncategorized) at [index]
  /// of that category's channel list, counted without the moved channel.
  CircleChannelLayout moveChannel(
    String channelId, {
    required String? categoryId,
    required int index,
  }) {
    CircleChannel? moved;
    List<CircleChannel> without(List<CircleChannel> channels) {
      return channels.where((channel) => channel.id != channelId).toList();
    }

    for (final channel in [
      ...uncategorized,
      for (final channels in channelsByCategory.values) ...channels,
    ]) {
      if (channel.id == channelId) {
        moved = channel;
      }
    }
    if (moved == null ||
        (categoryId != null && !channelsByCategory.containsKey(categoryId))) {
      return this;
    }
    final nextUncategorized = without(uncategorized);
    final nextByCategory = {
      for (final entry in channelsByCategory.entries)
        entry.key: without(entry.value),
    };
    final target = categoryId == null
        ? nextUncategorized
        : nextByCategory[categoryId]!;
    target.insert(index.clamp(0, target.length), moved);
    return CircleChannelLayout(
      categories: categories,
      uncategorized: List.unmodifiable(nextUncategorized),
      channelsByCategory: {
        for (final entry in nextByCategory.entries)
          entry.key: List.unmodifiable(entry.value),
      },
    );
  }

  /// Moves [categoryId] to [index] among the categories, counted without
  /// the moved category. Its channels move with it.
  CircleChannelLayout moveCategory(String categoryId, int index) {
    final next = [...categories];
    final from = next.indexWhere((category) => category.id == categoryId);
    if (from < 0) {
      return this;
    }
    final moved = next.removeAt(from);
    next.insert(index.clamp(0, next.length), moved);
    return CircleChannelLayout(
      categories: List.unmodifiable(next),
      uncategorized: uncategorized,
      channelsByCategory: channelsByCategory,
    );
  }

  /// Categories with fresh positions.
  List<CircleChannelCategory> get orderedCategories {
    return [
      for (final (index, category) in categories.indexed)
        CircleChannelCategory(
          id: category.id,
          circleId: category.circleId,
          name: category.name,
          position: index,
        ),
    ];
  }

  /// Every channel in display order, with fresh positions and categories.
  List<CircleChannel> get orderedChannels {
    final ordered = <CircleChannel>[];
    for (final categoryId in <String?>[
      null,
      for (final category in categories) category.id,
    ]) {
      for (final channel in channelsIn(categoryId)) {
        ordered.add(
          CircleChannel(
            id: channel.id,
            circleId: channel.circleId,
            conversationId: channel.conversationId,
            name: channel.name,
            position: ordered.length,
            categoryId: categoryId,
          ),
        );
      }
    }
    return ordered;
  }

  /// The payload of `reorder_circle_channels`.
  Map<String, dynamic> toJson() {
    return {
      'categories': [for (final category in categories) category.id],
      'channels': [
        for (final channel in orderedChannels)
          {'id': channel.id, 'category_id': channel.categoryId},
      ],
    };
  }
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
