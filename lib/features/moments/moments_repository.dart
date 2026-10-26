import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/push/push_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/message.dart' show cleanImageAlt;
import 'package:wecord/shared/realtime/private_channels.dart';
import 'package:wecord/features/chats/chats_repository.dart'
    show AutoModBlockedException, SendRefusedException;

/// The private bucket with the pictures and covers.
const momentsBucket = 'moments';

/// A picture of a Moment being written: already scaled down and compressed,
/// with its thumbnail, and not yet uploaded.
@immutable
class MomentPhotoDraft {
  const MomentPhotoDraft({
    required this.id,
    required this.full,
    required this.thumb,
    required this.width,
    required this.height,
    this.alt,
  });

  final String id;
  final Uint8List full;
  final Uint8List thumb;
  final int width;
  final int height;

  /// What the author wrote about the picture, for people who cannot see it.
  final String? alt;

  /// The same picture with [alt] as its description (empty or null takes it
  /// away).
  MomentPhotoDraft withAlt(String? alt) {
    return MomentPhotoDraft(
      id: id,
      full: full,
      thumb: thumb,
      width: width,
      height: height,
      alt: cleanImageAlt(alt),
    );
  }
}

/// The picture or sticker being put on a comment: the file's bytes as they
/// will be stored (a sticker keeps its own format, a photo is a JPEG), and
/// what the commenter wrote about it.
@immutable
class MomentCommentPicture {
  const MomentCommentPicture({
    required this.bytes,
    required this.extension,
    this.width = 0,
    this.height = 0,
    this.alt,
    this.sticker = false,
  });

  final Uint8List bytes;

  /// `jpg`, `png`, `webp` or `gif`: the name the bucket stores it under.
  final String extension;
  final int width;
  final int height;
  final String? alt;

  /// It came from the person's own stickers.
  final bool sticker;

  String get mimeType => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => 'image/jpeg',
  };

  MomentCommentPicture withAlt(String? alt) {
    return MomentCommentPicture(
      bytes: bytes,
      extension: extension,
      width: width,
      height: height,
      alt: cleanImageAlt(alt),
      sticker: sticker,
    );
  }
}

/// The video of a Moment being written: the file as the device holds it
/// (it is streamed from disk when posted, never held in memory), its length,
/// and the poster frame the feed shows first, already a JPEG with its
/// thumbnail.
@immutable
class MomentVideoDraft {
  const MomentVideoDraft({
    required this.file,
    required this.mimeType,
    required this.size,
    required this.duration,
    required this.poster,
    required this.posterThumb,
    required this.width,
    required this.height,
  });

  final XFile file;

  /// `video/mp4`, `video/quicktime` or `video/webm`.
  final String mimeType;
  final int size;
  final Duration duration;
  final Uint8List poster;
  final Uint8List posterThumb;

  /// The poster frame's size, which gives the video its shape in the feed.
  final int width;
  final int height;

  /// The file extension the bucket stores it under.
  String get extension => switch (mimeType) {
    'video/quicktime' => 'mov',
    'video/webm' => 'webm',
    _ => 'mp4',
  };
}

/// Everything the Moments pages need from the server. The visibility rules
/// live in the database (see migrations 202610180041 and 202610180042); the
/// answers here are already only what the signed-in person may see.
abstract interface class MomentsRepository {
  /// The feed (without [authorId]) or one person's page, newest first. Pass
  /// the last post's time and id as [beforeAt] and [beforeId] for the next
  /// page.
  ///
  /// With [tag] only the Moments written with that topic (#话题) the
  /// person may see: a filter on the feed, never a public page.
  Future<List<MomentPost>> feed({
    int limit = 20,
    DateTime? beforeAt,
    String? beforeId,
    String? authorId,
    String? tag,
  });

  /// The topics the person's and their friends' recent Moments use, with
  /// how many of those Moments the person may see.
  Future<List<MomentTopic>> topics({int limit = 20});

  /// One Moment, or null when it is gone or the person may not see it.
  Future<MomentPost?> post(String id);

  /// Uploads the pictures and posts the Moment under [id]. Posting the same
  /// id again changes nothing, so a retry after a lost answer is safe.
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
  });

  Future<void> deletePost(String id);

  /// Pins the person's own Moment to their page, or takes it off. Throws
  /// [MomentPinLimitException] when three are already pinned.
  Future<void> setPinned(String id, {required bool pinned});

  Future<void> setLiked(String postId, {required bool liked});

  /// Comments with words, a [picture] or both.
  Future<void> comment({
    required String postId,
    required String body,
    String? replyToCommentId,
    MomentCommentPicture? picture,
  });

  /// Deletes a comment; [imagePath] is the file of its picture when it is
  /// the person's own, to remove from the bucket.
  Future<void> deleteComment(String commentId, {String? imagePath});

  Future<MomentsProfile?> profile(String userId);

  Future<MomentsSettings> settings();

  Future<void> setRange(MomentsRange range);

  /// Turns the push for likes, comments and replies on or off.
  Future<void> setPushEnabled({required bool enabled});

  /// Signals that the feed, a post or the notifications changed, as long as
  /// someone listens; [MomentsSignalKind.resync] after every (re)connection.
  /// They carry no content (see migration 202610190020).
  Stream<MomentsSignal> signals();

  /// Uploads [jpeg] as the cover.
  Future<void> setCover(Uint8List jpeg);

  Future<void> clearCover();

  Future<List<MomentsFriendPref>> friendPrefs();

  Future<void> setFriendPref(
    String friendId, {
    bool? hideMine,
    bool? hideTheirs,
  });

  Future<MomentsUnseen> unseen();

  Future<void> markSeen();

  Future<List<MomentNotification>> notifications({int limit = 50});

  Future<void> markNotificationsRead([List<String>? ids]);

  /// A temporary link to a picture in the bucket.
  Future<String> signedUrl(String path);

  /// What a Moment card in a chat shows; null when the person may not see
  /// the Moment (any more).
  Future<MomentCardInfo?> momentCard(String postId);

  /// Sends a card of the Moment to a chat; returns the message's id. The card
  /// holds nothing but the Moment's id.
  Future<String> sendMomentCard({
    required String conversationId,
    required String postId,
  });
}

/// Three Moments are already pinned.
class MomentPinLimitException implements Exception {
  const MomentPinLimitException();

  @override
  String toString() => 'You can pin at most $maxMomentPins Moments.';
}

class SupabaseMomentsRepository implements MomentsRepository {
  const SupabaseMomentsRepository(this._client, [this._uploader, this._onSent]);

  final SupabaseClient _client;

  /// Told the id of a sent message, to push it to the others.
  final Future<void> Function(String messageId)? _onSent;

  /// The chat's streaming uploader, for the video.
  final ChatMediaUploader? _uploader;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Sign in to use Moments.');
    }
    return id;
  }

  List<Map<String, dynamic>> _rows(dynamic result) => [
    for (final row in result as List) Map<String, dynamic>.from(row as Map),
  ];

  @override
  Future<List<MomentPost>> feed({
    int limit = 20,
    DateTime? beforeAt,
    String? beforeId,
    String? authorId,
    String? tag,
  }) async {
    final rows = await _client.rpc<dynamic>(
      'moments_feed',
      params: {
        'p_limit': limit,
        'p_before_at': beforeAt?.toUtc().toIso8601String(),
        'p_before_id': beforeId,
        'p_author_id': authorId,
        'p_tag': ?tag,
      },
    );
    return [for (final row in _rows(rows)) MomentPost.fromJson(row)];
  }

  @override
  Future<List<MomentTopic>> topics({int limit = 20}) async {
    final rows = await _client.rpc<dynamic>(
      'list_moment_hashtags',
      params: {'p_limit': limit},
    );
    return [for (final row in _rows(rows)) MomentTopic.fromJson(row)];
  }

  @override
  Future<MomentPost?> post(String id) async {
    final rows = await _client.rpc<dynamic>(
      'moments_feed',
      params: {'p_limit': 1, 'p_post_id': id},
    );
    final list = _rows(rows);
    return list.isEmpty ? null : MomentPost.fromJson(list.first);
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
    final owner = _userId;
    final uploaded = <String>[];
    final entries = <Map<String, Object?>>[];
    Map<String, Object?>? videoEntry;
    try {
      if (video != null) {
        // The poster frame is stored like a photo, then the video itself
        // is streamed from disk, as the chat does.
        final poster = '$owner/$id-0.jpg';
        final posterThumb = '$owner/$id-0-t.jpg';
        final path = '$owner/$id-v.${video.extension}';
        await Future.wait([
          _upload(poster, video.poster),
          _upload(posterThumb, video.posterThumb),
        ]);
        uploaded
          ..add(poster)
          ..add(posterThumb);
        final uploader = _uploader;
        if (uploader == null) {
          throw StateError('Uploads are not available');
        }
        await uploader.upload(
          bucket: momentsBucket,
          path: path,
          mimeType: video.mimeType,
          length: video.size,
          data: video.file.openRead(),
          onProgress: onUploadProgress,
        );
        uploaded.add(path);
        videoEntry = {
          'path': path,
          'poster': poster,
          'thumb': posterThumb,
          'w': video.width,
          'h': video.height,
          'duration_ms': video.duration.inMilliseconds,
          'size': video.size,
        };
      }
      for (final (index, photo) in photos.indexed) {
        final path = '$owner/$id-$index.jpg';
        final thumb = '$owner/$id-$index-t.jpg';
        await Future.wait([
          _upload(path, photo.full),
          _upload(thumb, photo.thumb),
        ]);
        uploaded
          ..add(path)
          ..add(thumb);
        entries.add({
          'path': path,
          'thumb': thumb,
          'w': photo.width,
          'h': photo.height,
          'alt': ?cleanImageAlt(photo.alt),
        });
      }
      await _client.rpc<dynamic>(
        'create_moment',
        params: {
          'p_id': id,
          'p_body': body,
          'p_photos': entries,
          'p_link_url': linkUrl,
          'p_link_title': linkTitle,
          'p_location': location,
          'p_visibility': audience.visibility.wire,
          'p_friend_ids': audience.usesLists ? audience.friendIds.toList() : [],
          'p_tag_ids': audience.usesLists ? audience.tagIds.toList() : [],
          'p_video': ?videoEntry,
          'p_mentioned_ids': mentionedIds,
        },
      );
      if (mentionedIds.isNotEmpty) {
        // The reminder is pushed to the people it names.
        unawaited(_pushFor(id));
      }
    } on PostgrestException {
      // The server refused the post: the pictures are not needed. (After a
      // lost connection they stay, since the post may have been made.)
      await _remove(uploaded);
      rethrow;
    }
  }

  /// Stores [bytes] at [path]. The same file already being there (an earlier
  /// try got through before the answer was lost) is fine.
  Future<void> _upload(
    String path,
    Uint8List bytes, {
    String contentType = 'image/jpeg',
  }) async {
    try {
      await _client.storage
          .from(momentsBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );
    } on StorageException catch (error) {
      if (error.statusCode != '409') {
        rethrow;
      }
    }
  }

  Future<void> _remove(Iterable<String> paths) async {
    final list = paths.toList();
    if (list.isEmpty) {
      return;
    }
    try {
      await _client.storage.from(momentsBucket).remove(list);
    } on Object {
      // A leftover file is harmless: only its owner can read it.
    }
  }

  @override
  Future<void> deletePost(String id) async {
    final rows = await _client.rpc<dynamic>(
      'delete_moment',
      params: {'p_id': id},
    );
    await _remove([
      for (final row in _rows(rows)) row['object_path'] as String,
    ]);
  }

  @override
  Future<void> setPinned(String id, {required bool pinned}) async {
    try {
      await _client.rpc<dynamic>(
        'set_moment_pinned',
        params: {'p_id': id, 'p_pinned': pinned},
      );
    } on PostgrestException catch (error) {
      if (error.code == '54000') {
        throw const MomentPinLimitException();
      }
      rethrow;
    }
  }

  @override
  Future<void> setLiked(String postId, {required bool liked}) async {
    final owner = _userId;
    if (liked) {
      await _client
          .from('moments_likes')
          .upsert(
            {'post_id': postId, 'user_id': owner},
            onConflict: 'post_id,user_id',
            ignoreDuplicates: true,
          );
      unawaited(_pushFor(postId));
    } else {
      await _client
          .from('moments_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', owner);
    }
  }

  @override
  Future<void> comment({
    required String postId,
    required String body,
    String? replyToCommentId,
    MomentCommentPicture? picture,
  }) async {
    final owner = _userId;
    // The picture's file is named after the comment, so the id is made here.
    final id = newMomentId();
    String? path;
    Map<String, Object?>? image;
    if (picture != null) {
      path = '$owner/c-$id.${picture.extension}';
      await _upload(path, picture.bytes, contentType: picture.mimeType);
      image = {
        'path': path,
        'w': picture.width,
        'h': picture.height,
        'alt': ?cleanImageAlt(picture.alt),
      };
    }
    try {
      await _client.from('moments_comments').insert({
        'id': id,
        'post_id': postId,
        'author_id': owner,
        'body': body,
        'reply_to_comment_id': ?replyToCommentId,
        'image': ?image,
      });
    } on PostgrestException {
      // Refused: the picture is not needed.
      if (path != null) {
        await _remove([path]);
      }
      rethrow;
    }
    unawaited(_pushFor(postId));
  }

  /// Asks the push function to notify the person this like or comment is
  /// for. It claims only what this person just did and re-checks who may
  /// see it; never throws (the like or comment is already made, and the
  /// scheduled dispatch sends what this misses).
  Future<void> _pushFor(String postId) async {
    try {
      await _client.functions.invoke('push', body: {'moments_post_id': postId});
    } on Object {
      // Push is a courtesy.
    }
  }

  @override
  Future<void> deleteComment(String commentId, {String? imagePath}) async {
    await _client.from('moments_comments').delete().eq('id', commentId);
    if (imagePath != null && imagePath.startsWith('$_userId/')) {
      await _remove([imagePath]);
    }
  }

  @override
  Future<MomentsProfile?> profile(String userId) async {
    final rows = _rows(
      await _client.rpc<dynamic>(
        'get_moments_profile',
        params: {'p_user_id': userId},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return MomentsProfile(
      userId: row['user_id'] as String,
      name: row['display_name'] as String? ?? '',
      avatarUrl: row['avatar_url'] as String?,
      coverPath: row['cover_path'] as String?,
      canView: row['is_friend'] as bool? ?? false,
    );
  }

  @override
  Future<MomentsSettings> settings() async {
    final row = await _client
        .from('moments_settings')
        .select('visible_range,cover_path,push_enabled')
        .eq('user_id', _userId)
        .maybeSingle();
    if (row == null) {
      return const MomentsSettings();
    }
    return MomentsSettings(
      range: MomentsRange.fromWire(row['visible_range']),
      coverPath: row['cover_path'] as String?,
      pushEnabled: row['push_enabled'] as bool? ?? true,
    );
  }

  @override
  Future<void> setPushEnabled({required bool enabled}) async {
    await _client.rpc<dynamic>(
      'set_moments_settings',
      params: {'p_push_enabled': enabled},
    );
  }

  @override
  Stream<MomentsSignal> signals() {
    RealtimeChannel? channel;
    late StreamController<MomentsSignal> controller;
    controller = StreamController<MomentsSignal>(
      onListen: () {
        // A private channel of the person's own: the database tells only
        // them, and only about what they may see.
        final live = _client.channel(
          momentsTopic(_userId),
          opts: privateChannelConfig(),
        );
        channel = live;
        for (final kind in [
          MomentsSignalKind.post,
          MomentsSignalKind.postRemoved,
          MomentsSignalKind.reaction,
        ]) {
          live.onBroadcast(
            event: kind.wire,
            callback: (message) {
              final inner = message['payload'];
              final id = inner is Map ? inner['post_id'] : null;
              controller.add(MomentsSignal(kind, id is String ? id : null));
            },
          );
        }
        live.subscribe((status, error) {
          // Anything may have changed while the line was down.
          if (status == RealtimeSubscribeStatus.subscribed) {
            controller.add(const MomentsSignal(MomentsSignalKind.resync));
          }
        });
      },
      onCancel: () async {
        final live = channel;
        if (live != null) {
          await _client.removeChannel(live);
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> setRange(MomentsRange range) async {
    await _client.rpc<dynamic>(
      'set_moments_settings',
      params: {'p_visible_range': range.wire},
    );
  }

  @override
  Future<void> setCover(Uint8List jpeg) async {
    final path = '$_userId/cover-${_randomUuid()}.jpg';
    await _upload(path, jpeg);
    try {
      final freed = await _client.rpc<dynamic>(
        'set_moments_settings',
        params: {'p_cover_path': path},
      );
      if (freed is String) {
        await _remove([freed]);
      }
    } on Object {
      await _remove([path]);
      rethrow;
    }
  }

  @override
  Future<void> clearCover() async {
    final freed = await _client.rpc<dynamic>(
      'set_moments_settings',
      params: {'p_clear_cover': true},
    );
    if (freed is String) {
      await _remove([freed]);
    }
  }

  @override
  Future<List<MomentsFriendPref>> friendPrefs() async {
    final rows = _rows(await _client.rpc<dynamic>('list_moments_friend_prefs'));
    return [
      for (final row in rows)
        MomentsFriendPref(
          friendId: row['friend_id'] as String,
          name: row['display_name'] as String? ?? '',
          avatarUrl: row['avatar_url'] as String?,
          hideMine: row['hide_mine'] as bool? ?? false,
          hideTheirs: row['hide_theirs'] as bool? ?? false,
        ),
    ];
  }

  @override
  Future<void> setFriendPref(
    String friendId, {
    bool? hideMine,
    bool? hideTheirs,
  }) async {
    await _client.rpc<dynamic>(
      'set_moments_friend_pref',
      params: {
        'p_friend_id': friendId,
        'p_hide_mine': hideMine,
        'p_hide_theirs': hideTheirs,
      },
    );
  }

  @override
  Future<MomentsUnseen> unseen() async {
    final rows = _rows(await _client.rpc<dynamic>('moments_unseen_summary'));
    if (rows.isEmpty) {
      return MomentsUnseen.none;
    }
    final row = rows.first;
    return MomentsUnseen(
      count: (row['new_count'] as num?)?.toInt() ?? 0,
      latestAuthorId: row['latest_author_id'] as String?,
      latestAuthorName: row['latest_author_name'] as String?,
      latestAuthorAvatarUrl: row['latest_author_avatar_url'] as String?,
    );
  }

  @override
  Future<void> markSeen() async {
    await _client.rpc<dynamic>('mark_moments_seen');
  }

  @override
  Future<List<MomentNotification>> notifications({int limit = 50}) async {
    final rows = _rows(
      await _client.rpc<dynamic>(
        'list_moments_notifications',
        params: {'p_limit': limit},
      ),
    );
    return [for (final row in rows) MomentNotification.fromJson(row)];
  }

  @override
  Future<void> markNotificationsRead([List<String>? ids]) async {
    await _client.rpc<dynamic>(
      'mark_moments_notifications_read',
      params: {'p_ids': ids},
    );
  }

  @override
  Future<String> signedUrl(String path) {
    return _client.storage.from(momentsBucket).createSignedUrl(path, 3600);
  }

  @override
  Future<MomentCardInfo?> momentCard(String postId) async {
    final rows = _rows(
      await _client.rpc<dynamic>(
        'get_moment_card',
        params: {'p_post_id': postId},
      ),
    );
    return rows.isEmpty ? null : MomentCardInfo.fromJson(rows.first);
  }

  @override
  Future<String> sendMomentCard({
    required String conversationId,
    required String postId,
  }) async {
    final Object? created;
    try {
      created = await _client.rpc<Object?>(
        'send_moment_card',
        params: {'target_conversation_id': conversationId, 'p_post_id': postId},
      );
    } on PostgrestException catch (error) {
      final refused = SendRefusedException.fromPostgrest(error);
      if (refused != null) {
        throw refused;
      }
      rethrow;
    }
    if (created is! String) {
      throw const AutoModBlockedException();
    }
    await _onSent?.call(created);
    return created;
  }
}

/// A random version 4 UUID, for a cover's file name.
String _randomUuid() {
  final random = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int from, int to) => [
    for (var i = from; i < to; i++) bytes[i].toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// A random id for a new Moment (its pictures are named after it).
String newMomentId() => _randomUuid();

/// Stands in before Supabase is set up (tests): nothing to show, nothing is
/// stored.
class UninitializedMomentsRepository implements MomentsRepository {
  const UninitializedMomentsRepository();

  static StateError _unavailable() =>
      StateError('Supabase must be initialized to use Moments.');

  @override
  Future<List<MomentPost>> feed({
    int limit = 20,
    DateTime? beforeAt,
    String? beforeId,
    String? authorId,
    String? tag,
  }) async => const [];

  @override
  Future<List<MomentTopic>> topics({int limit = 20}) async => const [];

  @override
  Future<MomentPost?> post(String id) async => null;

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
  }) => throw _unavailable();

  @override
  Future<void> deletePost(String id) => throw _unavailable();

  @override
  Future<void> setPinned(String id, {required bool pinned}) =>
      throw _unavailable();

  @override
  Future<void> setLiked(String postId, {required bool liked}) =>
      throw _unavailable();

  @override
  Future<void> comment({
    required String postId,
    required String body,
    String? replyToCommentId,
    MomentCommentPicture? picture,
  }) => throw _unavailable();

  @override
  Future<void> deleteComment(String commentId, {String? imagePath}) =>
      throw _unavailable();

  @override
  Future<MomentsProfile?> profile(String userId) async => null;

  @override
  Future<MomentsSettings> settings() async => const MomentsSettings();

  @override
  Future<void> setRange(MomentsRange range) => throw _unavailable();

  @override
  Future<void> setPushEnabled({required bool enabled}) => throw _unavailable();

  @override
  Stream<MomentsSignal> signals() => const Stream.empty();

  @override
  Future<void> setCover(Uint8List jpeg) => throw _unavailable();

  @override
  Future<void> clearCover() => throw _unavailable();

  @override
  Future<List<MomentsFriendPref>> friendPrefs() async => const [];

  @override
  Future<void> setFriendPref(
    String friendId, {
    bool? hideMine,
    bool? hideTheirs,
  }) => throw _unavailable();

  @override
  Future<MomentsUnseen> unseen() async => MomentsUnseen.none;

  @override
  Future<void> markSeen() async {}

  @override
  Future<List<MomentNotification>> notifications({int limit = 50}) async =>
      const [];

  @override
  Future<void> markNotificationsRead([List<String>? ids]) async {}

  @override
  Future<String> signedUrl(String path) => throw _unavailable();

  @override
  Future<MomentCardInfo?> momentCard(String postId) async => null;

  @override
  Future<String> sendMomentCard({
    required String conversationId,
    required String postId,
  }) => throw _unavailable();
}

final momentsRepositoryProvider = Provider<MomentsRepository>((ref) {
  try {
    return SupabaseMomentsRepository(
      ref.watch(supabaseClientProvider),
      ref.watch(chatMediaUploaderProvider),
      ref.watch(pushRepositoryProvider).notifySent,
    );
  } on ProviderException {
    return const UninitializedMomentsRepository();
  }
});
