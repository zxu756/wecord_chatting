import 'package:flutter/foundation.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// The private bucket with the photos, videos and thumbnails of dailies.
const storiesBucket = 'stories';

/// How long a daily lasts.
const storyLifetime = Duration(hours: 24);

/// The one video of a daily: 15 seconds (half a second of slack for the
/// rounding of the player) and 20 MB. The server checks both too.
const maxStoryVideoDuration = Duration(seconds: 15, milliseconds: 500);
const maxStoryVideoBytes = 20 * 1024 * 1024;

/// How long a photo stays on screen before the next one (a video plays to its
/// end, never longer than 15 seconds).
const storyPhotoDuration = Duration(seconds: 5);

/// Longest caption, as the server enforces it.
const maxStoryCaption = 200;

/// The quick emojis under a daily.
const storyQuickEmojis = ['❤️', '😂', '😮', '😢', '👏', '🔥'];

enum StoryMediaKind {
  photo('photo'),
  video('video');

  const StoryMediaKind(this.wire);

  final String wire;

  static StoryMediaKind fromWire(Object? value) =>
      value == 'video' ? StoryMediaKind.video : StoryMediaKind.photo;
}

/// One person in the row of dailies: the friend, how many of their dailies
/// are up and how many of those are new to the signed-in person.
@immutable
class StoryTrayEntry {
  const StoryTrayEntry({
    required this.authorId,
    required this.name,
    this.avatarUrl,
    this.isMe = false,
    this.storyCount = 0,
    this.unseenCount = 0,
    this.latestAt,
  });

  factory StoryTrayEntry.fromJson(Map<String, dynamic> json) {
    return StoryTrayEntry(
      authorId: json['author_id'] as String,
      name: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      isMe: json['is_me'] as bool? ?? false,
      storyCount: (json['story_count'] as num?)?.toInt() ?? 0,
      unseenCount: (json['unseen_count'] as num?)?.toInt() ?? 0,
      latestAt: DateTime.tryParse('${json['latest_at']}')?.toLocal(),
    );
  }

  final String authorId;
  final String name;
  final String? avatarUrl;
  final bool isMe;
  final int storyCount;
  final int unseenCount;
  final DateTime? latestAt;

  /// Something new to watch: the ring is drawn in the accent color.
  bool get hasUnseen => unseenCount > 0;
}

/// A daily as the viewer shows it.
@immutable
class Story {
  const Story({
    required this.id,
    required this.authorId,
    required this.kind,
    required this.mediaPath,
    required this.thumbPath,
    required this.createdAt,
    required this.expiresAt,
    this.posterPath,
    this.width = 0,
    this.height = 0,
    this.duration,
    this.caption = '',
    this.visibility = 'friends',
    this.viewed = false,
    this.myReaction,
    this.viewCount = 0,
    this.reactionCount = 0,
  });

  factory Story.fromJson(Map<String, dynamic> json) {
    final ms = (json['duration_ms'] as num?)?.toInt();
    return Story(
      id: json['id'] as String,
      authorId: json['author_id'] as String,
      kind: StoryMediaKind.fromWire(json['media_kind']),
      mediaPath: json['media_path'] as String,
      posterPath: json['poster_path'] as String?,
      thumbPath: json['thumb_path'] as String,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      duration: ms == null ? null : Duration(milliseconds: ms),
      caption: json['caption'] as String? ?? '',
      visibility: json['visibility'] as String? ?? 'friends',
      createdAt: DateTime.parse('${json['created_at']}').toLocal(),
      expiresAt: DateTime.parse('${json['expires_at']}').toLocal(),
      viewed: json['viewed'] as bool? ?? false,
      myReaction: json['my_reaction'] as String?,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      reactionCount: (json['reaction_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String authorId;
  final StoryMediaKind kind;

  /// The photo, or the video file.
  final String mediaPath;

  /// A video's poster frame.
  final String? posterPath;
  final String thumbPath;
  final int width;
  final int height;
  final Duration? duration;
  final String caption;
  final String visibility;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool viewed;
  final String? myReaction;

  /// Only the author gets these.
  final int viewCount;
  final int reactionCount;

  bool get isVideo => kind == StoryMediaKind.video;

  bool hasEndedAt(DateTime now) => !expiresAt.isAfter(now);

  /// How long this one stays on screen.
  Duration get screenTime {
    if (!isVideo) {
      return storyPhotoDuration;
    }
    final length = duration;
    return length == null || length <= Duration.zero
        ? storyPhotoDuration
        : length;
  }

  Story copyWith({bool? viewed, Object? myReaction = _keep, int? viewCount}) {
    return Story(
      id: id,
      authorId: authorId,
      kind: kind,
      mediaPath: mediaPath,
      posterPath: posterPath,
      thumbPath: thumbPath,
      width: width,
      height: height,
      duration: duration,
      caption: caption,
      visibility: visibility,
      createdAt: createdAt,
      expiresAt: expiresAt,
      viewed: viewed ?? this.viewed,
      myReaction: identical(myReaction, _keep)
          ? this.myReaction
          : myReaction as String?,
      viewCount: viewCount ?? this.viewCount,
      reactionCount: reactionCount,
    );
  }
}

const Object _keep = Object();

/// Someone who watched one of my dailies, and the emoji they left.
@immutable
class StoryViewerEntry {
  const StoryViewerEntry({
    required this.viewerId,
    required this.name,
    required this.viewedAt,
    this.avatarUrl,
    this.emoji,
  });

  factory StoryViewerEntry.fromJson(Map<String, dynamic> json) {
    return StoryViewerEntry(
      viewerId: json['viewer_id'] as String,
      name: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      viewedAt: DateTime.parse('${json['viewed_at']}').toLocal(),
      emoji: json['emoji'] as String?,
    );
  }

  final String viewerId;
  final String name;
  final String? avatarUrl;
  final DateTime viewedAt;
  final String? emoji;
}

/// What a reply card shows about the daily it replies to.
@immutable
class StoryRefInfo {
  const StoryRefInfo({
    required this.storyId,
    required this.authorId,
    required this.kind,
    required this.thumbPath,
  });

  factory StoryRefInfo.fromJson(Map<String, dynamic> json) {
    return StoryRefInfo(
      storyId: json['story_id'] as String,
      authorId: json['author_id'] as String,
      kind: StoryMediaKind.fromWire(json['media_kind']),
      thumbPath: json['thumb_path'] as String,
    );
  }

  final String storyId;
  final String authorId;
  final StoryMediaKind kind;
  final String thumbPath;
}

/// The `story_ref` attachment of a reply (`send_story_reply`,
/// `202610240220_stories_rpcs.sql`).
@immutable
class StoryRef {
  const StoryRef({
    required this.storyId,
    required this.ownerId,
    required this.kind,
  });

  static const attachmentKind = 'story_ref';

  /// The reference in [attachment], or null when it is not a well-formed one.
  static StoryRef? maybeFromAttachment(Map<String, dynamic>? attachment) {
    if (attachment == null || attachment['kind'] != attachmentKind) {
      return null;
    }
    final id = attachment['story_id'];
    final owner = attachment['owner_id'];
    if (id is! String || id.isEmpty || owner is! String || owner.isEmpty) {
      return null;
    }
    return StoryRef(
      storyId: id,
      ownerId: owner,
      kind: StoryMediaKind.fromWire(attachment['media_kind']),
    );
  }

  final String storyId;
  final String ownerId;
  final StoryMediaKind kind;
}

extension StoryReplyMessage on ChatMessage {
  /// The daily this message replies to, or null.
  StoryRef? get storyRef {
    if (type != MessageType.text || recalledAt != null) {
      return null;
    }
    return StoryRef.maybeFromAttachment(attachment);
  }
}

/// What the server tells about dailies changing: ids only, never content.
enum StorySignalKind {
  story('story'),
  storyRemoved('story_removed'),

  /// The line came back: anything may have changed.
  resync('resync');

  const StorySignalKind(this.wire);

  final String wire;
}

@immutable
class StorySignal {
  const StorySignal(this.kind, [this.storyId]);

  final StorySignalKind kind;
  final String? storyId;
}

/// "5h ago" style age of a daily, and how long it has left.
String storyAgeLabel(DateTime createdAt, DateTime now) {
  final age = now.difference(createdAt);
  if (age.inMinutes < 1) {
    return tr('Just now');
  }
  if (age.inMinutes < 60) {
    return tr('{count}m ago', {'count': age.inMinutes});
  }
  return tr('{count}h ago', {'count': age.inHours});
}

/// "Ends in 5h" for the author's own dailies.
String storyRemainingLabel(DateTime expiresAt, DateTime now) {
  final left = expiresAt.difference(now);
  if (left.inMinutes < 1) {
    return tr('Ends soon');
  }
  if (left.inMinutes < 60) {
    return tr('Ends in {count}m', {'count': left.inMinutes});
  }
  return tr('Ends in {count}h', {'count': left.inHours});
}
