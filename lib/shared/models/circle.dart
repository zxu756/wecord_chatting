import 'package:wecord/shared/models/circle_role.dart';
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
    this.currentUserPermissions,
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
      currentUserPermissions: (json['current_user_permissions'] as num?)
          ?.toInt(),
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

  /// The current user's permission bits in the circle (see
  /// [CirclePermission]), when the server sent them.
  final int? currentUserPermissions;

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
      if (currentUserPermissions != null)
        'current_user_permissions': currentUserPermissions,
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
    this.roles = const [],
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
      roles: _parseList(json['roles'], CircleRole.fromJson)
        ..sort((left, right) => right.position.compareTo(left.position)),
    );
  }

  final CircleSummary circle;
  final List<CircleMember> members;

  /// Every channel, ordered by position.
  final List<CircleChannel> channels;

  /// Channel categories, ordered by position.
  final List<CircleChannelCategory> categories;
  final List<CirclePost> posts;

  /// Every role, highest first; `@everyone` is last.
  final List<CircleRole> roles;

  bool get isOwner => circle.currentUserRole == 'owner';

  /// The current user's permission bits. Payloads without them (older
  /// servers, tests) fall back to what the legacy owner / admin / member
  /// roles could do.
  int get currentUserPermissions {
    final permissions = circle.currentUserPermissions;
    if (permissions != null) {
      return permissions;
    }
    return switch (circle.currentUserRole) {
      'owner' => CirclePermission.all,
      'admin' =>
        CirclePermission.all &
            ~CirclePermission.maskOf(const [
              CirclePermission.manageRoles,
              CirclePermission.administrator,
            ]),
      'member' => CirclePermission.defaultRolePermissions,
      _ => 0,
    };
  }

  bool can(CirclePermission permission) {
    return isOwner || permission.isGrantedBy(currentUserPermissions);
  }

  bool get canManageChannels => can(CirclePermission.manageChannels);

  bool get canCreateInvites => can(CirclePermission.createInvites);

  bool get canManageRoles => can(CirclePermission.manageRoles);

  bool get canViewAuditLog => can(CirclePermission.viewAuditLog);

  /// The current user's permission bits in [channel]: what the server
  /// computed with its overwrites, otherwise the circle-wide permissions.
  int channelPermissionsOf(CircleChannel channel) {
    if (isOwner) {
      return CirclePermission.all;
    }
    return channel.currentUserPermissions ?? currentUserPermissions;
  }

  /// Whether the current user has [permission] in [channel].
  bool canInChannel(CircleChannel channel, CirclePermission permission) {
    return permission.isGrantedBy(channelPermissionsOf(channel));
  }

  /// The slowmode the current user waits out in [channel]: none with
  /// manage messages there.
  int slowmodeFor(CircleChannel channel) {
    return canInChannel(channel, CirclePermission.manageMessages)
        ? 0
        : channel.slowmodeSeconds;
  }

  /// Whether the current user may open channel settings: permissions need
  /// manage roles, the rest manage channels.
  bool get canOpenChannelSettings => canManageRoles || canManageChannels;

  /// Whether the current user may edit the overwrite of [role] in a
  /// channel: like the server, only roles below their highest role.
  bool canEditRoleOverwrite(CircleRole role) {
    return canManageRoles && role.position < currentUserRank;
  }

  /// Whether the current user may edit [member]'s overwrite in a channel:
  /// their own, or a member ranked below them.
  bool canEditMemberOverwrite(CircleMember member) {
    return canManageRoles &&
        (member.isCurrentUser || rankOf(member) < currentUserRank);
  }

  CircleMember? get currentMember {
    for (final member in members) {
      if (member.isCurrentUser) {
        return member;
      }
    }
    return null;
  }

  /// The assigned roles of [member], highest first (without `@everyone`).
  List<CircleRole> rolesOf(CircleMember member) {
    if (member.roleIds.isEmpty) {
      return const [];
    }
    return [
      for (final role in roles)
        if (!role.isDefault && member.roleIds.contains(role.id)) role,
    ];
  }

  /// Where [member] stands in the role hierarchy: the owner above everyone,
  /// others at their highest role's position (0 with none).
  int rankOf(CircleMember member) {
    if (member.role == 'owner') {
      return circleOwnerRank;
    }
    final memberRoles = rolesOf(member);
    if (memberRoles.isNotEmpty) {
      return memberRoles.first.position;
    }
    // Payloads without roles rank legacy admins above members.
    return roles.isEmpty && member.role == 'admin' ? 1 : 0;
  }

  int get currentUserRank {
    if (isOwner) {
      return circleOwnerRank;
    }
    final member = currentMember;
    if (member != null) {
      return rankOf(member);
    }
    return roles.isEmpty && circle.currentUserRole == 'admin' ? 1 : 0;
  }

  /// The colour of [member]'s highest coloured role, as 0xRRGGBB.
  int? roleColorOf(CircleMember member) {
    for (final role in rolesOf(member)) {
      if (role.color != null) {
        return role.color;
      }
    }
    return null;
  }

  /// [member]'s highest hoisted role, which groups them in the member list.
  CircleRole? hoistedRoleOf(CircleMember member) {
    for (final role in rolesOf(member)) {
      if (role.hoist) {
        return role;
      }
    }
    return null;
  }

  /// Whether the current user may edit [role]: it must rank below them.
  bool canManageRole(CircleRole role) {
    return canManageRoles && role.position < currentUserRank;
  }

  /// Roles the current user may assign or remove.
  List<CircleRole> get assignableRoles {
    return [
      for (final role in roles)
        if (!role.isDefault && canManageRole(role)) role,
    ];
  }

  /// Whether the current user may change [member]'s roles: only the owner
  /// may change the owner's.
  bool canManageRolesOf(CircleMember member) {
    if (!canManageRoles || assignableRoles.isEmpty) {
      return false;
    }
    return member.role != 'owner' || isOwner;
  }

  /// Whether the current user may kick [member]: never themselves or the
  /// owner, and only members ranked below them.
  bool canKick(CircleMember member) {
    return can(CirclePermission.kickMembers) &&
        !member.isCurrentUser &&
        member.role != 'owner' &&
        rankOf(member) < currentUserRank;
  }

  /// Everyone may rename themselves; renaming others needs manage
  /// nicknames and a higher rank than theirs.
  bool canChangeNickname(CircleMember member) {
    if (member.isCurrentUser) {
      return true;
    }
    return can(CirclePermission.manageNicknames) &&
        rankOf(member) < currentUserRank;
  }
}

/// The rank of a circle's owner, above every role.
const circleOwnerRank = 0x7fffffff;

class CircleMember {
  const CircleMember({
    required this.profile,
    required this.role,
    this.nickname,
    this.isCurrentUser = false,
    this.roleIds = const [],
  });

  factory CircleMember.fromJson(Map<String, dynamic> json) {
    return CircleMember(
      role: json['role'] as String,
      profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
      nickname: json['nickname'] as String?,
      isCurrentUser: json['is_current_user'] == true,
      roleIds: [
        for (final id in json['role_ids'] as List<dynamic>? ?? const [])
          id as String,
      ],
    );
  }

  final Profile profile;
  final String role;

  /// This circle's nickname for the member, if they have one.
  final String? nickname;
  final bool isCurrentUser;

  /// Assigned role ids, highest first (`@everyone` is implied).
  final List<String> roleIds;

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
    this.currentUserPermissions,
    this.isPrivate = false,
    this.isReadOnly = false,
    this.slowmodeSeconds = 0,
    this.topic,
    this.kind = CircleChannelKind.text,
  });

  factory CircleChannel.fromJson(Map<String, dynamic> json) {
    return CircleChannel(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      conversationId: json['conversation_id'] as String,
      name: json['name'] as String,
      position: (json['position'] as num?)?.toInt() ?? 0,
      categoryId: json['category_id'] as String?,
      currentUserPermissions: (json['current_user_permissions'] as num?)
          ?.toInt(),
      isPrivate: json['is_private'] == true,
      isReadOnly: json['is_read_only'] == true,
      slowmodeSeconds: (json['slowmode_seconds'] as num?)?.toInt() ?? 0,
      topic: switch (json['topic']) {
        final String topic when topic.trim().isNotEmpty => topic,
        _ => null,
      },
      kind: CircleChannelKind.fromJson(json['kind']),
    );
  }

  /// Longest channel name the server accepts.
  static const maxNameLength = 48;

  /// Longest channel topic the server accepts.
  static const maxTopicLength = 1024;

  final String id;
  final String circleId;
  final String conversationId;
  final String name;
  final int position;

  /// Null for channels listed above every category.
  final String? categoryId;

  /// The current user's permission bits in this channel, after channel
  /// overwrites, when the server sent them.
  final int? currentUserPermissions;

  /// `@everyone` may not see the channel.
  final bool isPrivate;

  /// `@everyone` may not send messages in the channel.
  final bool isReadOnly;

  /// How long members wait between messages; 0 when slowmode is off.
  final int slowmodeSeconds;

  /// Shown under the channel name; null when not set.
  final String? topic;

  final CircleChannelKind kind;
}

/// What a channel holds: a chat, voice (later) or forum posts.
enum CircleChannelKind {
  text('text'),
  voice('voice'),
  forum('forum');

  const CircleChannelKind(this.value);

  /// The `circle_channels.kind` value.
  final String value;

  /// Unknown values (newer servers) read as text.
  static CircleChannelKind fromJson(Object? value) {
    for (final kind in values) {
      if (kind.value == value) {
        return kind;
      }
    }
    return text;
  }
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
