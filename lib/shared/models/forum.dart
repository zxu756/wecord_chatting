import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

/// A tag posts in a forum channel can carry.
class ForumTag {
  const ForumTag({
    required this.id,
    required this.channelId,
    required this.name,
    this.emoji,
    this.position = 0,
  });

  factory ForumTag.fromJson(Map<String, dynamic> json) {
    return ForumTag(
      id: json['id'] as String,
      channelId: json['channel_id'] as String? ?? '',
      name: json['name'] as String,
      emoji: switch (json['emoji']) {
        final String emoji when emoji.trim().isNotEmpty => emoji,
        _ => null,
      },
      position: (json['position'] as num?)?.toInt() ?? 0,
    );
  }

  /// Longest tag name the server accepts.
  static const maxNameLength = 20;

  /// Most tags a forum can have.
  static const maxPerForum = 20;

  /// Most tags a post can carry.
  static const maxPerPost = 5;

  final String id;
  final String channelId;
  final String name;
  final String? emoji;
  final int position;

  /// "🐛 Bug", or just the name.
  String get label => emoji == null ? name : '$emoji $name';
}

/// How a forum's posts are ordered.
enum ForumPostSort {
  /// Most recently active first.
  activity('activity', 'Latest activity'),

  /// Newest posts first.
  created('created', 'Newest');

  const ForumPostSort(this.value, this._label);

  /// The `sort_order` value of `list_forum_posts`.
  final String value;
  final String _label;

  String get label => tr(_label);
}

/// Where the next page of a forum's posts starts: after this post.
class ForumPostCursor {
  const ForumPostCursor({required this.at, required this.id});

  final DateTime at;
  final String id;
}

/// The author of a forum post, with their name and colour in the circle.
class ForumPostAuthor {
  const ForumPostAuthor({required this.profile, this.nickname, this.roleColor});

  factory ForumPostAuthor.fromJson(Map<String, dynamic> json) {
    return ForumPostAuthor(
      profile: Profile.fromJson(json),
      nickname: json['nickname'] as String?,
      roleColor: (json['role_color'] as num?)?.toInt(),
    );
  }

  final Profile profile;
  final String? nickname;

  /// Their highest coloured role, as 0xRRGGBB.
  final int? roleColor;

  /// Nickname, then display name, then username.
  String get name {
    final nickname = this.nickname?.trim();
    if (nickname != null && nickname.isNotEmpty) {
      return nickname;
    }
    return profile.displayName.trim().isEmpty
        ? profile.username
        : profile.displayName;
  }
}

/// A post of a forum channel: a thread whose first message is its body.
class ForumPost {
  const ForumPost({
    required this.id,
    required this.conversationId,
    required this.channelId,
    required this.title,
    required this.createdAt,
    required this.lastActivityAt,
    this.createdBy,
    this.author,
    this.tags = const [],
    this.body = '',
    this.replyCount = 0,
    this.unreadCount = 0,
    this.isPinned = false,
    this.archivedAt,
    this.thumbnail,
    this.canManage = false,
    this.solvedAt,
    this.solvedMessageId,
  });

  factory ForumPost.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    final opening = json['opening_message'];
    final thumbnail = json['thumbnail'];
    return ForumPost(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      channelId: json['channel_id'] as String,
      title: json['title'] as String? ?? 'Post',
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      lastActivityAt: DateTime.parse(
        (json['last_activity_at'] ?? json['created_at']) as String,
      ).toUtc(),
      archivedAt: switch (json['archived_at']) {
        final String value => DateTime.parse(value).toUtc(),
        _ => null,
      },
      isPinned: json['is_pinned'] == true,
      author: author is Map<String, dynamic>
          ? ForumPostAuthor.fromJson(author)
          : null,
      tags: [
        for (final tag in json['tags'] as List<dynamic>? ?? const [])
          ForumTag.fromJson(tag as Map<String, dynamic>),
      ],
      body: opening is Map<String, dynamic>
          ? opening['body'] as String? ?? ''
          : '',
      replyCount: (json['reply_count'] as num?)?.toInt() ?? 0,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      thumbnail: _parseImage(thumbnail),
      canManage: json['can_manage'] == true,
      solvedAt: switch (json['solved_at']) {
        final String value => DateTime.parse(value).toUtc(),
        _ => null,
      },
      solvedMessageId: json['solved_message_id'] as String?,
    );
  }

  /// Longest post title the server accepts.
  static const maxTitleLength = 100;

  /// Longest post body the server accepts.
  static const maxBodyLength = 4000;

  /// The thread id.
  final String id;

  /// The thread's conversation, where the body and replies live.
  final String conversationId;
  final String channelId;
  final String title;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime lastActivityAt;

  /// Null when the author's account is gone.
  final ForumPostAuthor? author;
  final List<ForumTag> tags;

  /// The first message's text (Markdown), empty for an image-only post.
  final String body;

  /// Messages after the opening post.
  final int replyCount;
  final int unreadCount;
  final bool isPinned;
  final DateTime? archivedAt;

  /// The post's first image, for a thumbnail.
  final ImageAttachment? thumbnail;

  /// The current user may archive the post and change its tags.
  final bool canManage;

  bool get isArchived => archivedAt != null;

  /// A question of a Q&A channel that was marked solved; null elsewhere and
  /// while the question is open.
  final DateTime? solvedAt;

  /// The answer picked for a solved question, when one was.
  final String? solvedMessageId;

  bool get isSolved => solvedAt != null;

  /// Where the next page starts when this is the last post of a page.
  ForumPostCursor cursorFor(ForumPostSort sort) {
    return ForumPostCursor(
      at: sort == ForumPostSort.created ? createdAt : lastActivityAt,
      id: id,
    );
  }
}

ImageAttachment? _parseImage(Object? json) {
  if (json is! Map<String, dynamic>) {
    return null;
  }
  try {
    return ImageAttachment.fromJson(json);
  } on Object {
    return null;
  }
}
