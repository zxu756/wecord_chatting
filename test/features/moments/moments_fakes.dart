import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/friend_tags/friend_tags_repository.dart';
import 'package:wecord/features/moments/moment_photos.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/features/moments/moments_repository.dart';

import '../wallpapers/wallpaper_fakes.dart' show samplePhotoBytes;

/// A Moment posted through [FakeMomentsRepository.create].
class CreatedMoment {
  CreatedMoment({
    required this.id,
    required this.body,
    required this.photoCount,
    required this.audience,
    this.linkUrl,
    this.linkTitle,
    this.location,
    this.video,
    this.mentionedIds = const [],
    this.photoAlts = const [],
  });

  final String id;
  final String body;
  final int photoCount;
  final MomentAudience audience;
  final String? linkUrl;
  final String? linkTitle;
  final String? location;
  final MomentVideoDraft? video;
  final List<String> mentionedIds;

  /// The description of each photo (null where there is none).
  final List<String?> photoAlts;
}

/// The Moments server in memory. It does not apply the visibility rules (the
/// database does, see test/supabase/moments_behaviour.sql): [posts] already
/// hold what the signed-in person may see.
class FakeMomentsRepository implements MomentsRepository {
  FakeMomentsRepository({
    this.me = 'user-1',
    this.myName = 'Ada Lovelace',
    List<MomentPost>? posts,
  }) : posts = posts ?? [];

  final String me;
  final String myName;

  /// Newest first.
  List<MomentPost> posts;

  /// The bucket: path to picture bytes.
  final bucket = <String, Uint8List>{};

  var settingsValue = const MomentsSettings();
  final profiles = <String, MomentsProfile>{};
  var prefs = <MomentsFriendPref>[];
  var unseenValue = MomentsUnseen.none;
  var notificationList = <MomentNotification>[];

  final created = <CreatedMoment>[];
  final likeCalls = <(String, bool)>[];
  final comments = <(String postId, String body, String? replyTo)>[];
  final commentPictures = <MomentCommentPicture?>[];
  final pinCalls = <(String, bool)>[];
  final cardsSent = <(String conversationId, String postId)>[];

  /// What a Moment card in a chat shows, by post id; none: "Can't view".
  final cardInfos = <String, MomentCardInfo>{};

  /// The most Moments the fake lets the person pin (the server says 3).
  var pinLimit = maxMomentPins;
  final deletedComments = <String>[];
  final deletedCommentImages = <String?>[];
  final deletedPosts = <String>[];
  final feedCalls =
      <({DateTime? beforeAt, String? beforeId, String? authorId})>[];
  final readNotifications = <List<String>?>[];
  final ranges = <MomentsRange>[];
  var coversSet = 0;
  var coversCleared = 0;
  var markSeenCalls = 0;
  var unseenCalls = 0;

  /// Makes the next write fail.
  Object? failNext;

  void _maybeFail() {
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
  }

  @override
  Future<List<MomentPost>> feed({
    int limit = 20,
    DateTime? beforeAt,
    String? beforeId,
    String? authorId,
  }) async {
    feedCalls.add((beforeAt: beforeAt, beforeId: beforeId, authorId: authorId));
    final all = [
      for (final post in posts)
        if (authorId == null || post.authorId == authorId) post,
    ]..sort(_newestFirst);
    final after = beforeAt == null
        ? all
        : all.where((post) {
            final byTime = post.createdAt.compareTo(beforeAt);
            return byTime < 0 ||
                (byTime == 0 && post.id.compareTo(beforeId ?? '') < 0);
          }).toList();
    return after.take(limit).toList();
  }

  static int _newestFirst(MomentPost a, MomentPost b) {
    final byTime = b.createdAt.compareTo(a.createdAt);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  var postCalls = 0;

  @override
  Future<MomentPost?> post(String id) async {
    postCalls += 1;
    return posts.where((post) => post.id == id).firstOrNull;
  }

  @override
  Future<void> create({
    required String id,
    String body = '',
    List<MomentPhotoDraft> photos = const [],
    String? linkUrl,
    String? linkTitle,
    String? location,
    MomentAudience audience = MomentAudience.everyone,
    MomentVideoDraft? video,
    List<String> mentionedIds = const [],
    void Function(double? progress)? onUploadProgress,
  }) async {
    _maybeFail();
    if (video != null) {
      onUploadProgress?.call(0.5);
      onUploadProgress?.call(1);
    }
    created.add(
      CreatedMoment(
        id: id,
        body: body,
        photoCount: photos.length,
        audience: audience,
        linkUrl: linkUrl,
        linkTitle: linkTitle,
        location: location,
        video: video,
        mentionedIds: mentionedIds,
        photoAlts: [for (final photo in photos) photo.alt],
      ),
    );
    MomentVideo? storedVideo;
    if (video != null) {
      final path = '$me/$id-v.${video.extension}';
      bucket['$me/$id-0.jpg'] = video.poster;
      bucket['$me/$id-0-t.jpg'] = video.posterThumb;
      bucket[path] = Uint8List(0);
      storedVideo = MomentVideo(
        path: path,
        poster: '$me/$id-0.jpg',
        thumb: '$me/$id-0-t.jpg',
        duration: video.duration,
        width: video.width,
        height: video.height,
        size: video.size,
        mimeType: video.mimeType,
      );
    }
    final entries = <MomentPhoto>[];
    for (final (index, photo) in photos.indexed) {
      final path = '$me/$id-$index.jpg';
      final thumb = '$me/$id-$index-t.jpg';
      bucket[path] = photo.full;
      bucket[thumb] = photo.thumb;
      entries.add(
        MomentPhoto(
          path: path,
          thumb: thumb,
          width: photo.width,
          height: photo.height,
          alt: photo.alt,
        ),
      );
    }
    posts = [
      MomentPost(
        id: id,
        authorId: me,
        authorName: myName,
        body: body,
        kind: storedVideo != null
            ? MomentKind.video
            : entries.isNotEmpty
            ? MomentKind.photos
            : linkUrl != null
            ? MomentKind.link
            : MomentKind.text,
        photos: entries,
        video: storedVideo,
        linkUrl: linkUrl,
        linkTitle: linkTitle,
        location: location,
        visibility: audience.visibility,
        createdAt: DateTime.now().toUtc(),
      ),
      ...posts,
    ];
  }

  MomentPost _replace(String id, MomentPost Function(MomentPost) change) {
    final index = posts.indexWhere((post) => post.id == id);
    final updated = change(posts[index]);
    posts = [...posts]..[index] = updated;
    return updated;
  }

  @override
  Future<void> deletePost(String id) async {
    _maybeFail();
    deletedPosts.add(id);
    posts = [
      for (final post in posts)
        if (post.id != id) post,
    ];
  }

  @override
  Future<void> setPinned(String id, {required bool pinned}) async {
    _maybeFail();
    pinCalls.add((id, pinned));
    if (pinned && posts.where((post) => post.isPinned).length >= pinLimit) {
      throw const MomentPinLimitException();
    }
    _replace(
      id,
      (post) => pinned
          ? post.copyWith(pinnedAt: DateTime.now().toUtc())
          : post.copyWith(clearPin: true),
    );
  }

  @override
  Future<void> setLiked(String postId, {required bool liked}) async {
    _maybeFail();
    likeCalls.add((postId, liked));
    _replace(postId, (post) {
      final others = post.likes.where((like) => like.userId != me).toList();
      final likes = liked
          ? [...others, MomentLiker(userId: me, name: myName)]
          : others;
      return post.copyWith(
        likedByMe: liked,
        likes: likes,
        likeCount: likes.length,
      );
    });
  }

  @override
  Future<void> comment({
    required String postId,
    required String body,
    String? replyToCommentId,
    MomentCommentPicture? picture,
  }) async {
    _maybeFail();
    comments.add((postId, body, replyToCommentId));
    commentPictures.add(picture);
    _replace(postId, (post) {
      final parent = post.comments
          .where((comment) => comment.id == replyToCommentId)
          .firstOrNull;
      final next = [
        ...post.comments,
        MomentComment(
          id: 'comment-${comments.length}',
          userId: me,
          name: myName,
          body: body,
          createdAt: DateTime.now().toUtc(),
          replyToCommentId: parent?.id,
          replyToUserId: parent?.userId,
          replyToName: parent?.name,
          image: picture == null
              ? null
              : MomentCommentImage(
                  path: '$me/c-comment-${comments.length}.${picture.extension}',
                  width: picture.width,
                  height: picture.height,
                  alt: picture.alt,
                ),
        ),
      ];
      return post.copyWith(comments: next, commentCount: next.length);
    });
  }

  @override
  Future<void> deleteComment(String commentId, {String? imagePath}) async {
    _maybeFail();
    deletedComments.add(commentId);
    deletedCommentImages.add(imagePath);
    posts = [
      for (final post in posts)
        post.comments.any((comment) => comment.id == commentId)
            ? post.copyWith(
                comments: [
                  for (final comment in post.comments)
                    if (comment.id != commentId) comment,
                ],
                commentCount: post.commentCount - 1,
              )
            : post,
    ];
  }

  @override
  Future<MomentsProfile?> profile(String userId) async {
    return profiles[userId] ??
        MomentsProfile(
          userId: userId,
          name: userId == me ? myName : 'Friend',
          coverPath: userId == me ? settingsValue.coverPath : null,
        );
  }

  @override
  Future<MomentsSettings> settings() async => settingsValue;

  @override
  Future<void> setRange(MomentsRange range) async {
    _maybeFail();
    ranges.add(range);
    settingsValue = MomentsSettings(
      range: range,
      coverPath: settingsValue.coverPath,
      pushEnabled: settingsValue.pushEnabled,
    );
  }

  @override
  Future<void> setCover(Uint8List jpeg) async {
    _maybeFail();
    coversSet += 1;
    const path = 'user-1/cover-test.jpg';
    bucket[path] = jpeg;
    settingsValue = MomentsSettings(
      range: settingsValue.range,
      coverPath: path,
      pushEnabled: settingsValue.pushEnabled,
    );
  }

  @override
  Future<void> clearCover() async {
    coversCleared += 1;
    settingsValue = MomentsSettings(
      range: settingsValue.range,
      pushEnabled: settingsValue.pushEnabled,
    );
  }

  final pushSwitches = <bool>[];

  @override
  Future<void> setPushEnabled({required bool enabled}) async {
    _maybeFail();
    pushSwitches.add(enabled);
    settingsValue = MomentsSettings(
      range: settingsValue.range,
      coverPath: settingsValue.coverPath,
      pushEnabled: enabled,
    );
  }

  final _signals = StreamController<MomentsSignal>.broadcast();

  @override
  Stream<MomentsSignal> signals() => _signals.stream;

  /// Whether the app listens for live signals.
  bool get hasSignalListener => _signals.hasListener;

  /// What the server would send; change [posts] first.
  void emit(MomentsSignalKind kind, [String? postId]) =>
      _signals.add(MomentsSignal(kind, postId));

  @override
  Future<List<MomentsFriendPref>> friendPrefs() async => prefs;

  final prefCalls = <(String, bool?, bool?)>[];

  @override
  Future<void> setFriendPref(
    String friendId, {
    bool? hideMine,
    bool? hideTheirs,
  }) async {
    _maybeFail();
    prefCalls.add((friendId, hideMine, hideTheirs));
    final existing = prefs
        .where((pref) => pref.friendId == friendId)
        .firstOrNull;
    final next = MomentsFriendPref(
      friendId: friendId,
      name: existing?.name ?? friendId,
      hideMine: hideMine ?? existing?.hideMine ?? false,
      hideTheirs: hideTheirs ?? existing?.hideTheirs ?? false,
    );
    prefs = [
      for (final pref in prefs)
        if (pref.friendId != friendId) pref,
      if (next.hideMine || next.hideTheirs) next,
    ];
  }

  @override
  Future<MomentsUnseen> unseen() async {
    unseenCalls += 1;
    return unseenValue;
  }

  @override
  Future<void> markSeen() async {
    markSeenCalls += 1;
    unseenValue = MomentsUnseen.none;
  }

  @override
  Future<List<MomentNotification>> notifications({int limit = 50}) async =>
      notificationList;

  @override
  Future<void> markNotificationsRead([List<String>? ids]) async {
    readNotifications.add(ids);
    notificationList = [
      for (final notification in notificationList)
        if (ids == null || ids.contains(notification.id))
          MomentNotification(
            id: notification.id,
            kind: notification.kind,
            postId: notification.postId,
            actorId: notification.actorId,
            actorName: notification.actorName,
            actorAvatarUrl: notification.actorAvatarUrl,
            snippet: notification.snippet,
            postExcerpt: notification.postExcerpt,
            postThumb: notification.postThumb,
            createdAt: notification.createdAt,
            isUnread: false,
          )
        else
          notification,
    ];
  }

  @override
  Future<String> signedUrl(String path) async => 'fake://$path';

  @override
  Future<MomentCardInfo?> momentCard(String postId) async => cardInfos[postId];

  @override
  Future<String> sendMomentCard({
    required String conversationId,
    required String postId,
  }) async {
    _maybeFail();
    cardsSent.add((conversationId, postId));
    return 'message-${cardsSent.length}';
  }
}

/// The tags and stars in memory.
class FakeFriendTagsRepository implements FriendTagsRepository {
  FakeFriendTagsRepository([this.data = const FriendTagsData()]);

  FriendTagsData data;
  var _nextId = 1;
  final calls = <String>[];
  Object? failNext;

  void _maybeFail() {
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
  }

  @override
  Future<FriendTagsData> load() async => data;

  @override
  Future<FriendTag> createTag(String name) async {
    _maybeFail();
    final problem = checkFriendTagName(name, data.tags);
    if (problem != null) {
      throw FriendTagNameException(problem);
    }
    final tag = FriendTag(id: 'tag-${_nextId++}', name: name.trim());
    calls.add('create:${tag.name}');
    data = FriendTagsData(
      tags: [...data.tags, tag],
      members: data.members,
      starred: data.starred,
    );
    return tag;
  }

  @override
  Future<void> renameTag(String tagId, String name) async {
    _maybeFail();
    final problem = checkFriendTagName(
      name,
      data.tags.where((tag) => tag.id != tagId),
    );
    if (problem != null) {
      throw FriendTagNameException(problem);
    }
    calls.add('rename:$tagId:${name.trim()}');
    data = FriendTagsData(
      tags: [
        for (final tag in data.tags)
          if (tag.id == tagId) FriendTag(id: tagId, name: name.trim()) else tag,
      ],
      members: data.members,
      starred: data.starred,
    );
  }

  @override
  Future<void> deleteTag(String tagId) async {
    _maybeFail();
    calls.add('delete:$tagId');
    data = FriendTagsData(
      tags: [
        for (final tag in data.tags)
          if (tag.id != tagId) tag,
      ],
      members: {...data.members}..remove(tagId),
      starred: data.starred,
    );
  }

  @override
  Future<void> setTagMembers(
    String tagId,
    Set<String> friendIds, {
    required Set<String> current,
  }) async {
    _maybeFail();
    calls.add('members:$tagId:${(friendIds.toList()..sort()).join(',')}');
    data = FriendTagsData(
      tags: data.tags,
      members: {
        ...data.members,
        tagId: {...friendIds},
      },
      starred: data.starred,
    );
  }

  @override
  Future<void> setStarred(String friendId, {required bool starred}) async {
    _maybeFail();
    calls.add('${starred ? 'star' : 'unstar'}:$friendId');
    data = FriendTagsData(
      tags: data.tags,
      members: data.members,
      starred: starred
          ? {...data.starred, friendId}
          : ({...data.starred}..remove(friendId)),
    );
  }
}

/// Picks the same few pictures every time.
class FakeMomentPhotoPicker implements MomentPhotoPicker {
  FakeMomentPhotoPicker({this.available = 3});

  /// How many pictures the person "has" to pick.
  int available;
  var picks = 0;
  Uint8List? cover;
  var _counter = 0;

  @override
  Future<List<MomentPhotoDraft>> pickPhotos({required int limit}) async {
    picks += 1;
    return [
      for (var i = 0; i < available.clamp(0, limit); i++)
        sampleDraft('pick-${_counter++}', landscape: i.isEven),
    ];
  }

  @override
  Future<Uint8List?> pickCover() async => cover;

  /// What picking a video gives: a draft, nothing (cancelled), or a problem.
  MomentVideoDraft? video;
  MomentVideoProblem? videoProblem;
  var videoPicks = 0;

  /// What picking a picture for a comment gives (null: cancelled).
  MomentCommentPicture? commentPhoto;
  var commentPhotoPicks = 0;

  @override
  Future<MomentCommentPicture?> pickCommentPhoto() async {
    commentPhotoPicks += 1;
    return commentPhoto;
  }

  @override
  Future<MomentVideoDraft?> pickVideo() async {
    videoPicks += 1;
    final problem = videoProblem;
    if (problem != null) {
      throw MomentVideoException(problem);
    }
    return video;
  }
}

/// A video of [seconds] with a sample poster.
MomentVideoDraft sampleVideo({int seconds = 42, String name = 'walk.mp4'}) {
  final poster = sampleDraft('video-poster');
  return MomentVideoDraft(
    file: XFile.fromData(Uint8List(8), name: name, mimeType: 'video/mp4'),
    mimeType: 'video/mp4',
    size: 3 * 1024 * 1024,
    duration: Duration(seconds: seconds),
    poster: poster.full,
    posterThumb: poster.thumb,
    width: poster.width,
    height: poster.height,
  );
}

MomentPhotoDraft sampleDraft(String id, {bool landscape = true}) {
  final full = samplePhotoBytes(
    width: landscape ? 480 : 320,
    height: landscape ? 320 : 480,
  );
  return MomentPhotoDraft(
    id: id,
    full: full,
    thumb: samplePhotoBytes(
      width: landscape ? 160 : 107,
      height: landscape ? 107 : 160,
    ),
    width: landscape ? 480 : 320,
    height: landscape ? 320 : 480,
  );
}

/// The overrides that put Moments, tags and the picker in memory; pictures
/// of the fake bucket show from memory.
List<Override> momentsOverrides({
  required FakeMomentsRepository repository,
  FakeFriendTagsRepository? tags,
  MomentPhotoPicker? picker,
}) {
  return [
    momentsRepositoryProvider.overrideWithValue(repository),
    friendTagsRepositoryProvider.overrideWithValue(
      tags ?? FakeFriendTagsRepository(),
    ),
    ?(picker == null
        ? null
        : momentPhotoPickerProvider.overrideWithValue(picker)),
    momentImageProviderFactory.overrideWithValue(
      (url) => MemoryImage(
        repository.bucket[url.replaceFirst('fake://', '')] ?? _placeholder,
      ),
    ),
  ];
}

final _placeholder = samplePhotoBytes(width: 120, height: 90);

// ---- Sample data for screens and screenshots.

MomentPost post(
  String id, {
  String authorId = 'user-2',
  String authorName = 'Bart the Bold',
  String body = 'Sunrise from the north lot',
  List<MomentPhoto> photos = const [],
  List<MomentLiker> likes = const [],
  List<MomentComment> comments = const [],
  bool likedByMe = false,
  int minutesAgo = 30,
  MomentVisibility visibility = MomentVisibility.friends,
  String? location,
  String? linkUrl,
  DateTime? pinnedAt,
  bool mentionedMe = false,
  List<MomentMention> mentions = const [],
}) {
  return MomentPost(
    id: id,
    authorId: authorId,
    authorName: authorName,
    body: body,
    kind: photos.isNotEmpty ? MomentKind.photos : MomentKind.text,
    photos: photos,
    location: location,
    linkUrl: linkUrl,
    visibility: visibility,
    createdAt: DateTime.now().toUtc().subtract(Duration(minutes: minutesAgo)),
    likeCount: likes.length,
    likedByMe: likedByMe,
    likes: likes,
    commentCount: comments.length,
    comments: comments,
    pinnedAt: pinnedAt,
    mentionedMe: mentionedMe,
    mentions: mentions,
  );
}

MomentComment comment(
  String id,
  String userId,
  String name,
  String body, {
  String? replyToId,
  String? replyToUserId,
  String? replyToName,
  int minutesAgo = 10,
  MomentCommentImage? image,
}) {
  return MomentComment(
    id: id,
    userId: userId,
    name: name,
    body: body,
    createdAt: DateTime.now().toUtc().subtract(Duration(minutes: minutesAgo)),
    replyToCommentId: replyToId,
    replyToUserId: replyToUserId,
    replyToName: replyToName,
    image: image,
  );
}

List<MomentPhoto> photos(
  FakeMomentsRepository repository,
  String postId,
  int count,
) {
  return [
    for (var i = 0; i < count; i++)
      () {
        final path = 'user-2/$postId-$i.jpg';
        final thumb = 'user-2/$postId-$i-t.jpg';
        repository.bucket[path] = samplePhotoBytes(width: 480, height: 320);
        repository.bucket[thumb] = samplePhotoBytes(width: 160, height: 107);
        return MomentPhoto(path: path, thumb: thumb, width: 480, height: 320);
      }(),
  ];
}
