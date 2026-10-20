import 'package:flutter/foundation.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart' show cleanImageAlt;

/// Most photos in one Moment.
const maxMomentPhotos = 9;

/// The one video of a Moment: at most 3 minutes (half a second of slack for
/// the rounding of the player) and 50 MB. The server checks both too.
const maxMomentVideoDuration = Duration(seconds: 180, milliseconds: 500);
const maxMomentVideoBytes = 50 * 1024 * 1024;

/// Most friends one Moment can remind to read it ("Remind who to read").
const maxMomentMentions = 30;

/// Most Moments a person can pin to their page.
const maxMomentPins = 3;

/// Longest Moment text and comment, as the server enforces them.
const maxMomentTextLength = 2000;
const maxMomentCommentLength = 500;

/// Who can see a Moment (the server's `visibility`).
enum MomentVisibility {
  /// Every friend.
  friends('friends'),

  /// The author's close friends (dailies only; Moments never use it).
  close('close'),

  /// Only the author.
  private('private'),

  /// Only the chosen friends and tags ("Only share with").
  only('only'),

  /// Every friend but the chosen ones ("Don't share with").
  except('except');

  const MomentVisibility(this.wire);

  final String wire;

  static MomentVisibility fromWire(Object? value) {
    return MomentVisibility.values.firstWhere(
      (visibility) => visibility.wire == value,
      orElse: () => MomentVisibility.friends,
    );
  }
}

/// The audience chosen for a Moment: a mode and, for "only" and "except",
/// friends and tags.
@immutable
class MomentAudience {
  const MomentAudience({
    this.visibility = MomentVisibility.friends,
    this.friendIds = const {},
    this.tagIds = const {},
  });

  static const everyone = MomentAudience();

  final MomentVisibility visibility;
  final Set<String> friendIds;
  final Set<String> tagIds;

  bool get usesLists =>
      visibility == MomentVisibility.only ||
      visibility == MomentVisibility.except;

  /// A list mode needs at least one friend or tag to mean anything.
  bool get isComplete =>
      !usesLists || friendIds.isNotEmpty || tagIds.isNotEmpty;

  MomentAudience copyWith({
    MomentVisibility? visibility,
    Set<String>? friendIds,
    Set<String>? tagIds,
  }) {
    return MomentAudience(
      visibility: visibility ?? this.visibility,
      friendIds: friendIds ?? this.friendIds,
      tagIds: tagIds ?? this.tagIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MomentAudience &&
      other.visibility == visibility &&
      setEquals(other.friendIds, friendIds) &&
      setEquals(other.tagIds, tagIds);

  @override
  int get hashCode => Object.hash(
    visibility,
    Object.hashAllUnordered(friendIds),
    Object.hashAllUnordered(tagIds),
  );
}

/// A picture of a Moment: the full one and its thumbnail, both paths in the
/// private `moments` bucket.
@immutable
class MomentPhoto {
  const MomentPhoto({
    required this.path,
    required this.thumb,
    this.width = 0,
    this.height = 0,
    this.alt,
  });

  factory MomentPhoto.fromJson(Map<String, dynamic> json) {
    return MomentPhoto(
      path: json['path'] as String,
      thumb: json['thumb'] as String? ?? json['path'] as String,
      width: (json['w'] as num?)?.toInt() ?? 0,
      height: (json['h'] as num?)?.toInt() ?? 0,
      alt: cleanImageAlt(json['alt']),
    );
  }

  final String path;
  final String thumb;
  final int width;
  final int height;

  /// What the author wrote about the picture, for people who cannot see it.
  final String? alt;

  double? get aspectRatio => width > 0 && height > 0 ? width / height : null;
}

/// The video of a Moment (`moments_posts.video`): the file, its poster frame
/// and thumbnail (both pictures of the bucket), the length and the size.
@immutable
class MomentVideo {
  const MomentVideo({
    required this.path,
    required this.poster,
    required this.thumb,
    required this.duration,
    this.width = 0,
    this.height = 0,
    this.size = 0,
    this.mimeType = 'video/mp4',
  });

  factory MomentVideo.fromJson(Map<String, dynamic> json) {
    return MomentVideo(
      path: json['path'] as String,
      poster: json['poster'] as String? ?? json['thumb'] as String,
      thumb: json['thumb'] as String? ?? json['poster'] as String,
      duration: Duration(
        milliseconds: (json['duration_ms'] as num?)?.toInt() ?? 0,
      ),
      width: (json['w'] as num?)?.toInt() ?? 0,
      height: (json['h'] as num?)?.toInt() ?? 0,
      size: (json['size'] as num?)?.toInt() ?? 0,
      mimeType: json['mime'] as String? ?? 'video/mp4',
    );
  }

  final String path;
  final String poster;
  final String thumb;
  final Duration duration;
  final int width;
  final int height;
  final int size;
  final String mimeType;

  double? get aspectRatio => width > 0 && height > 0 ? width / height : null;

  /// "0:42".
  String get durationLabel {
    final seconds = (duration.inMilliseconds / 1000).round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

enum MomentKind {
  text,
  photos,
  link,
  video;

  static MomentKind fromWire(Object? value) {
    return MomentKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => MomentKind.text,
    );
  }
}

/// Somebody who liked a Moment (only people the viewer may see).
@immutable
class MomentLiker {
  const MomentLiker({required this.userId, required this.name, this.avatarUrl});

  factory MomentLiker.fromJson(Map<String, dynamic> json) {
    return MomentLiker(
      userId: json['user_id'] as String,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  final String userId;
  final String name;
  final String? avatarUrl;
}

/// The picture or sticker on a comment (`moments_comments.image`): a file in
/// the commenter's folder of the moments bucket and what they wrote about it.
@immutable
class MomentCommentImage {
  const MomentCommentImage({
    required this.path,
    this.width = 0,
    this.height = 0,
    this.alt,
  });

  factory MomentCommentImage.fromJson(Map<String, dynamic> json) {
    return MomentCommentImage(
      path: json['path'] as String,
      width: (json['w'] as num?)?.toInt() ?? 0,
      height: (json['h'] as num?)?.toInt() ?? 0,
      alt: cleanImageAlt(json['alt']),
    );
  }

  final String path;
  final int width;
  final int height;
  final String? alt;

  /// As a picture the full-screen viewer can open.
  MomentPhoto get asPhoto => MomentPhoto(
    path: path,
    thumb: path,
    width: width,
    height: height,
    alt: alt,
  );
}

/// A comment or a reply.
@immutable
class MomentComment {
  const MomentComment({
    required this.id,
    required this.userId,
    required this.name,
    required this.body,
    required this.createdAt,
    this.avatarUrl,
    this.replyToCommentId,
    this.replyToUserId,
    this.replyToName,
    this.image,
  });

  factory MomentComment.fromJson(Map<String, dynamic> json) {
    return MomentComment(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      body: json['body'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      replyToCommentId: json['reply_to_comment_id'] as String?,
      replyToUserId: json['reply_to_user_id'] as String?,
      replyToName: json['reply_to_name'] as String?,
      image: json['image'] is Map
          ? MomentCommentImage.fromJson(
              Map<String, dynamic>.from(json['image'] as Map),
            )
          : null,
    );
  }

  final String id;
  final String userId;
  final String name;
  final String? avatarUrl;
  final String body;
  final DateTime createdAt;
  final String? replyToCommentId;
  final String? replyToUserId;
  final String? replyToName;

  /// A picture or sticker on the comment, with or without words.
  final MomentCommentImage? image;

  bool get isReply => replyToUserId != null;
}

/// A friend the author reminded to read a Moment. Only the author is told
/// who (the server fills this for them alone).
@immutable
class MomentMention {
  const MomentMention({
    required this.userId,
    required this.name,
    this.avatarUrl,
  });

  factory MomentMention.fromJson(Map<String, dynamic> json) {
    return MomentMention(
      userId: json['user_id'] as String,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  final String userId;
  final String name;
  final String? avatarUrl;
}

/// A Moment as the viewer may see it: the likes and comments are already
/// only the ones the viewer is allowed to read.
@immutable
class MomentPost {
  const MomentPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    this.authorAvatarUrl,
    this.body = '',
    this.kind = MomentKind.text,
    this.photos = const [],
    this.video,
    this.linkUrl,
    this.linkTitle,
    this.location,
    this.visibility = MomentVisibility.friends,
    this.likeCount = 0,
    this.likedByMe = false,
    this.likes = const [],
    this.commentCount = 0,
    this.comments = const [],
    this.pinnedAt,
    this.mentionedMe = false,
    this.mentions = const [],
  });

  factory MomentPost.fromJson(Map<String, dynamic> json) {
    final photos = json['photos'];
    final likes = json['likes'];
    final comments = json['comments'];
    final mentions = json['mentions'];
    return MomentPost(
      id: json['id'] as String,
      authorId: json['author_id'] as String,
      authorName: json['author_name'] as String? ?? '',
      authorAvatarUrl: json['author_avatar_url'] as String?,
      body: json['body'] as String? ?? '',
      kind: MomentKind.fromWire(json['kind']),
      photos: photos is List
          ? [
              for (final photo in photos)
                MomentPhoto.fromJson(Map<String, dynamic>.from(photo as Map)),
            ]
          : const [],
      video: json['video'] is Map
          ? MomentVideo.fromJson(
              Map<String, dynamic>.from(json['video'] as Map),
            )
          : null,
      linkUrl: json['link_url'] as String?,
      linkTitle: json['link_title'] as String?,
      location: json['location'] as String?,
      visibility: MomentVisibility.fromWire(json['visibility']),
      createdAt: DateTime.parse(json['created_at'] as String),
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      likedByMe: json['liked_by_me'] as bool? ?? false,
      likes: likes is List
          ? [
              for (final like in likes)
                MomentLiker.fromJson(Map<String, dynamic>.from(like as Map)),
            ]
          : const [],
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      comments: comments is List
          ? [
              for (final comment in comments)
                MomentComment.fromJson(
                  Map<String, dynamic>.from(comment as Map),
                ),
            ]
          : const [],
      pinnedAt: json['pinned_at'] == null
          ? null
          : DateTime.parse(json['pinned_at'] as String),
      mentionedMe: json['mentioned_me'] as bool? ?? false,
      mentions: mentions is List
          ? [
              for (final mention in mentions)
                MomentMention.fromJson(
                  Map<String, dynamic>.from(mention as Map),
                ),
            ]
          : const [],
    );
  }

  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final String body;
  final MomentKind kind;
  final List<MomentPhoto> photos;
  final MomentVideo? video;
  final String? linkUrl;
  final String? linkTitle;
  final String? location;
  final MomentVisibility visibility;
  final DateTime createdAt;
  final int likeCount;
  final bool likedByMe;
  final List<MomentLiker> likes;
  final int commentCount;
  final List<MomentComment> comments;

  /// When the author pinned it to their page; null when it is not pinned.
  final DateTime? pinnedAt;

  /// The author reminded the viewer to read it.
  final bool mentionedMe;

  /// Whom the author reminded (filled for the author only).
  final List<MomentMention> mentions;

  bool get isPinned => pinnedAt != null;

  MomentPost copyWith({
    int? likeCount,
    bool? likedByMe,
    List<MomentLiker>? likes,
    int? commentCount,
    List<MomentComment>? comments,
    DateTime? pinnedAt,
    bool clearPin = false,
  }) {
    return MomentPost(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      body: body,
      kind: kind,
      photos: photos,
      video: video,
      linkUrl: linkUrl,
      linkTitle: linkTitle,
      location: location,
      visibility: visibility,
      createdAt: createdAt,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      likes: likes ?? this.likes,
      commentCount: commentCount ?? this.commentCount,
      comments: comments ?? this.comments,
      pinnedAt: clearPin ? null : pinnedAt ?? this.pinnedAt,
      mentionedMe: mentionedMe,
      mentions: mentions,
    );
  }
}

/// How far back friends can see the person's older Moments.
enum MomentsRange {
  all('all'),
  sixMonths('six_months'),
  oneMonth('one_month'),
  threeDays('three_days');

  const MomentsRange(this.wire);

  final String wire;

  static MomentsRange fromWire(Object? value) {
    return MomentsRange.values.firstWhere(
      (range) => range.wire == value,
      orElse: () => MomentsRange.all,
    );
  }

  String get label => switch (this) {
    MomentsRange.all => tr('All'),
    MomentsRange.sixMonths => tr('Last 6 months'),
    MomentsRange.oneMonth => tr('Last month'),
    MomentsRange.threeDays => tr('Last 3 days'),
  };
}

/// The person's own Moments settings.
@immutable
class MomentsSettings {
  const MomentsSettings({
    this.range = MomentsRange.all,
    this.coverPath,
    this.pushEnabled = true,
  });

  final MomentsRange range;
  final String? coverPath;

  /// Whether likes, comments and replies on the person's Moments are pushed
  /// to their devices (they always show in Notifications).
  final bool pushEnabled;
}

/// What a live signal says happened (the server's broadcast `event`).
enum MomentsSignalKind {
  /// A friend posted something the person may see.
  post('post'),

  /// A Moment the person could see is gone.
  postRemoved('post_removed'),

  /// A like or comment appeared or went on a Moment the person may see.
  reaction('reaction'),

  /// The channel (re)connected: anything may have changed.
  resync('resync');

  const MomentsSignalKind(this.wire);

  final String wire;
}

/// "Something changed", never what: the app reads the data again through the
/// same functions as always, which apply the visibility rules. Signals
/// compare by identity, so two in a row are two events.
class MomentsSignal {
  const MomentsSignal(this.kind, [this.postId]);

  final MomentsSignalKind kind;
  final String? postId;
}

/// A person's Moments page header: their name and, when the viewer may see
/// it, their cover.
@immutable
class MomentsProfile {
  const MomentsProfile({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.coverPath,
    this.canView = true,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final String? coverPath;
  final bool canView;
}

/// A friend the person hides Moments from, or whose Moments they hide.
@immutable
class MomentsFriendPref {
  const MomentsFriendPref({
    required this.friendId,
    required this.name,
    this.avatarUrl,
    this.hideMine = false,
    this.hideTheirs = false,
  });

  final String friendId;
  final String name;
  final String? avatarUrl;

  /// "Don't let them see my Moments"
  final bool hideMine;

  /// "Hide their Moments"
  final bool hideTheirs;
}

/// New Moments since the person last looked: how many and who posted last.
@immutable
class MomentsUnseen {
  const MomentsUnseen({
    required this.count,
    this.latestAuthorId,
    this.latestAuthorName,
    this.latestAuthorAvatarUrl,
  });

  static const none = MomentsUnseen(count: 0);

  final int count;
  final String? latestAuthorId;
  final String? latestAuthorName;
  final String? latestAuthorAvatarUrl;
}

enum MomentNotificationKind {
  like,
  comment,
  reply,

  /// The author reminded the person to read their Moment.
  mention;

  static MomentNotificationKind fromWire(Object? value) {
    return MomentNotificationKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => MomentNotificationKind.like,
    );
  }
}

/// A like, comment or reply on the person's Moment or comment.
@immutable
class MomentNotification {
  const MomentNotification({
    required this.id,
    required this.kind,
    required this.postId,
    required this.actorId,
    required this.actorName,
    required this.createdAt,
    required this.isUnread,
    this.actorAvatarUrl,
    this.snippet = '',
    this.postExcerpt = '',
    this.postThumb,
    this.hasImage = false,
  });

  factory MomentNotification.fromJson(Map<String, dynamic> json) {
    return MomentNotification(
      id: json['id'] as String,
      kind: MomentNotificationKind.fromWire(json['kind']),
      postId: json['post_id'] as String,
      actorId: json['actor_id'] as String,
      actorName: json['actor_name'] as String? ?? '',
      actorAvatarUrl: json['actor_avatar_url'] as String?,
      snippet: json['snippet'] as String? ?? '',
      postExcerpt: json['post_excerpt'] as String? ?? '',
      postThumb: json['post_thumb'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      isUnread: json['is_unread'] as bool? ?? false,
      hasImage: json['has_image'] as bool? ?? false,
    );
  }

  final String id;
  final MomentNotificationKind kind;
  final String postId;
  final String actorId;
  final String actorName;
  final String? actorAvatarUrl;
  final String snippet;
  final String postExcerpt;
  final String? postThumb;
  final DateTime createdAt;
  final bool isUnread;

  /// The comment behind the notice carries a picture or sticker.
  final bool hasImage;
}

/// What a Moment card in a chat shows (`get_moment_card`): only while the
/// reader may see the Moment.
@immutable
class MomentCardInfo {
  const MomentCardInfo({
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.kind,
    this.authorAvatarUrl,
    this.excerpt = '',
    this.thumb,
    this.photoCount = 0,
  });

  factory MomentCardInfo.fromJson(Map<String, dynamic> json) {
    return MomentCardInfo(
      postId: json['post_id'] as String,
      authorId: json['author_id'] as String,
      authorName: json['author_name'] as String? ?? '',
      authorAvatarUrl: json['author_avatar_url'] as String?,
      kind: MomentKind.fromWire(json['kind']),
      excerpt: json['excerpt'] as String? ?? '',
      thumb: json['thumb'] as String?,
      photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String postId;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final MomentKind kind;
  final String excerpt;
  final String? thumb;
  final int photoCount;
}

/// The words for who can see a Moment, e.g. "Friends", "Only me" or
/// "Only: Family, Bob". [tagNames] and [friendNames] are the chosen ones.
String momentAudienceLabel(
  MomentAudience audience, {
  Iterable<String> tagNames = const [],
  Iterable<String> friendNames = const [],
}) {
  String names() {
    final all = [...tagNames, ...friendNames];
    if (all.length <= 2) {
      return all.join(', ');
    }
    return tr('{first}, {second} and {count} more', {
      'first': all[0],
      'second': all[1],
      'count': all.length - 2,
    });
  }

  return switch (audience.visibility) {
    MomentVisibility.friends => tr('Friends'),
    MomentVisibility.close => tr('Close friends'),
    MomentVisibility.private => tr('Only me'),
    MomentVisibility.only =>
      audience.isComplete
          ? tr('Only: {names}', {'names': names()})
          : tr('Only share with…'),
    MomentVisibility.except =>
      audience.isComplete
          ? tr('Not: {names}', {'names': names()})
          : tr("Don't share with…"),
  };
}
