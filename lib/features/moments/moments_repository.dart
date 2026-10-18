import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/realtime/private_channels.dart';

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
  });

  final String id;
  final Uint8List full;
  final Uint8List thumb;
  final int width;
  final int height;
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
  Future<List<MomentPost>> feed({
    int limit = 20,
    DateTime? beforeAt,
    String? beforeId,
    String? authorId,
  });

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
    void Function(double? progress)? onUploadProgress,
  });

  Future<void> deletePost(String id);

  Future<void> setLiked(String postId, {required bool liked});

  Future<void> comment({
    required String postId,
    required String body,
    String? replyToCommentId,
  });

  Future<void> deleteComment(String commentId);

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
}

class SupabaseMomentsRepository implements MomentsRepository {
  const SupabaseMomentsRepository(this._client, [this._uploader]);

  final SupabaseClient _client;

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
  }) async {
    final rows = await _client.rpc<dynamic>(
      'moments_feed',
      params: {
        'p_limit': limit,
        'p_before_at': beforeAt?.toUtc().toIso8601String(),
        'p_before_id': beforeId,
        'p_author_id': authorId,
      },
    );
    return [for (final row in _rows(rows)) MomentPost.fromJson(row)];
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
        },
      );
    } on PostgrestException {
      // The server refused the post: the pictures are not needed. (After a
      // lost connection they stay, since the post may have been made.)
      await _remove(uploaded);
      rethrow;
    }
  }

  /// Stores [bytes] at [path]. The same file already being there (an earlier
  /// try got through before the answer was lost) is fine.
  Future<void> _upload(String path, Uint8List bytes) async {
    try {
      await _client.storage
          .from(momentsBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
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
  }) async {
    await _client.from('moments_comments').insert({
      'post_id': postId,
      'author_id': _userId,
      'body': body,
      'reply_to_comment_id': ?replyToCommentId,
    });
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
  Future<void> deleteComment(String commentId) async {
    await _client.from('moments_comments').delete().eq('id', commentId);
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
  }) async => const [];

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
    void Function(double? progress)? onUploadProgress,
  }) => throw _unavailable();

  @override
  Future<void> deletePost(String id) => throw _unavailable();

  @override
  Future<void> setLiked(String postId, {required bool liked}) =>
      throw _unavailable();

  @override
  Future<void> comment({
    required String postId,
    required String body,
    String? replyToCommentId,
  }) => throw _unavailable();

  @override
  Future<void> deleteComment(String commentId) => throw _unavailable();

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
}

final momentsRepositoryProvider = Provider<MomentsRepository>((ref) {
  try {
    return SupabaseMomentsRepository(
      ref.watch(supabaseClientProvider),
      ref.watch(chatMediaUploaderProvider),
    );
  } on ProviderException {
    return const UninitializedMomentsRepository();
  }
});
