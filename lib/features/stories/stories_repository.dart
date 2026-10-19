import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/report_reason.dart';
import 'package:wecord/shared/realtime/private_channels.dart';

/// Everything the Daily pages need from the server. The rules (who sees what,
/// the 24 hours, who may see the viewers) live in the database (migrations
/// 202610240200 to 202610240250); the answers here are already only what the
/// signed-in person may see.
abstract interface class StoriesRepository {
  /// Who has dailies for me: mine first, then friends with something new.
  Future<List<StoryTrayEntry>> tray();

  /// One person's dailies I may see, oldest first.
  Future<List<Story>> storiesOf(String authorId);

  /// Uploads the files and posts the daily under [id]. Posting the same id
  /// again changes nothing, so a retry after a lost answer is safe. A photo
  /// is [photo]; a video is [video] (its poster frame goes up with it).
  Future<void> create({
    required String id,
    MomentPhotoDraft? photo,
    MomentVideoDraft? video,
    String caption = '',
    MomentAudience audience = MomentAudience.everyone,
    void Function(double? progress)? onUploadProgress,
  });

  Future<void> delete(String id);

  /// I opened it.
  Future<void> markViewed(String id);

  /// Who viewed one of my dailies (the author only).
  Future<List<StoryViewerEntry>> viewers(String id);

  /// A quick emoji; null takes it back.
  Future<void> react(String id, String? emoji);

  /// Replies in the private chat with the author.
  Future<void> reply(String id, String body, {String? clientId});

  /// The card of a reply: null once the daily has ended or I may not see it.
  Future<StoryRefInfo?> refOf(String id);

  Future<Set<String>> closeFriends();

  Future<void> setCloseFriends(Set<String> ids);

  Future<void> report(
    String id, {
    required ReportReason reason,
    String details = '',
    bool alsoBlock = false,
  });

  /// A temporary link to a file in the bucket.
  Future<String> signedUrl(String path);

  /// Signals that the row of dailies changed, as long as someone listens;
  /// [StorySignalKind.resync] after every (re)connection. They carry no
  /// content (see migration 202610240240).
  Stream<StorySignal> signals();
}

class SupabaseStoriesRepository implements StoriesRepository {
  const SupabaseStoriesRepository(this._client, [this._uploader]);

  final SupabaseClient _client;

  /// The chat's streaming uploader, for the video.
  final ChatMediaUploader? _uploader;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Sign in to use the Daily.');
    }
    return id;
  }

  List<Map<String, dynamic>> _rows(dynamic result) => [
    for (final row in result as List) Map<String, dynamic>.from(row as Map),
  ];

  @override
  Future<List<StoryTrayEntry>> tray() async {
    final rows = await _client.rpc<dynamic>('stories_tray');
    return [for (final row in _rows(rows)) StoryTrayEntry.fromJson(row)];
  }

  @override
  Future<List<Story>> storiesOf(String authorId) async {
    final rows = await _client.rpc<dynamic>(
      'list_author_stories',
      params: {'p_author_id': authorId},
    );
    return [for (final row in _rows(rows)) Story.fromJson(row)];
  }

  @override
  Future<void> create({
    required String id,
    MomentPhotoDraft? photo,
    MomentVideoDraft? video,
    String caption = '',
    MomentAudience audience = MomentAudience.everyone,
    void Function(double? progress)? onUploadProgress,
  }) async {
    assert((photo == null) != (video == null), 'a photo or a video');
    final owner = _userId;
    final uploaded = <String>[];
    try {
      final thumbPath = '$owner/$id-t.jpg';
      final mainPath = '$owner/$id.jpg';
      String? videoExtension;
      int? width;
      int? height;
      int? durationMs;
      int size = 0;
      if (photo != null) {
        await Future.wait([
          _uploadImage(mainPath, photo.full),
          _uploadImage(thumbPath, photo.thumb),
        ]);
        uploaded
          ..add(mainPath)
          ..add(thumbPath);
        width = photo.width;
        height = photo.height;
        size = photo.full.length;
      } else if (video != null) {
        final uploader = _uploader;
        if (uploader == null) {
          throw StateError('Uploads are not available');
        }
        // The poster frame is stored like a photo, then the video itself is
        // streamed from disk, as the chat does.
        await Future.wait([
          _uploadImage(mainPath, video.poster),
          _uploadImage(thumbPath, video.posterThumb),
        ]);
        uploaded
          ..add(mainPath)
          ..add(thumbPath);
        videoExtension = video.extension;
        final path = '$owner/$id-v.$videoExtension';
        await uploader.upload(
          bucket: storiesBucket,
          path: path,
          mimeType: video.mimeType,
          length: video.size,
          data: video.file.openRead(),
          onProgress: onUploadProgress,
        );
        uploaded.add(path);
        width = video.width;
        height = video.height;
        durationMs = video.duration.inMilliseconds;
        size = video.size;
      }
      await _client.rpc<dynamic>(
        'create_story',
        params: {
          'p_id': id,
          'p_kind': photo != null ? 'photo' : 'video',
          'p_ext': videoExtension ?? 'mp4',
          'p_caption': caption,
          'p_visibility': audience.visibility.wire,
          'p_friend_ids': audience.usesLists ? audience.friendIds.toList() : [],
          'p_tag_ids': audience.usesLists ? audience.tagIds.toList() : [],
          'p_width': width ?? 0,
          'p_height': height ?? 0,
          'p_duration_ms': durationMs,
          'p_size': size,
        },
      );
    } on PostgrestException {
      // The server refused the daily: the files are not needed. (After a
      // lost connection they stay, since the daily may have been made.)
      await _remove(uploaded);
      rethrow;
    }
  }

  /// Stores [bytes] at [path]. The same file already being there (an earlier
  /// try got through before the answer was lost) is fine.
  Future<void> _uploadImage(String path, Uint8List bytes) async {
    try {
      await _client.storage
          .from(storiesBucket)
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
      await _client.storage.from(storiesBucket).remove(list);
    } on Object {
      // A leftover file is harmless: only its owner can read it, and nothing
      // points at it.
    }
  }

  @override
  Future<void> delete(String id) async {
    await _client.rpc<dynamic>('delete_story', params: {'p_id': id});
  }

  @override
  Future<void> markViewed(String id) async {
    await _client.rpc<dynamic>('mark_story_viewed', params: {'p_story_id': id});
  }

  @override
  Future<List<StoryViewerEntry>> viewers(String id) async {
    final rows = await _client.rpc<dynamic>(
      'list_story_viewers',
      params: {'p_story_id': id},
    );
    return [for (final row in _rows(rows)) StoryViewerEntry.fromJson(row)];
  }

  @override
  Future<void> react(String id, String? emoji) async {
    await _client.rpc<dynamic>(
      'react_to_story',
      params: {'p_story_id': id, 'p_emoji': emoji},
    );
  }

  @override
  Future<void> reply(String id, String body, {String? clientId}) async {
    await _client.rpc<dynamic>(
      'send_story_reply',
      params: {'p_story_id': id, 'p_body': body, 'p_client_id': ?clientId},
    );
  }

  @override
  Future<StoryRefInfo?> refOf(String id) async {
    final rows = _rows(
      await _client.rpc<dynamic>('get_story_ref', params: {'p_story_id': id}),
    );
    return rows.isEmpty ? null : StoryRefInfo.fromJson(rows.first);
  }

  @override
  Future<Set<String>> closeFriends() async {
    final rows = _rows(await _client.rpc<dynamic>('list_close_friends'));
    return {for (final row in rows) row['friend_id'] as String};
  }

  @override
  Future<void> setCloseFriends(Set<String> ids) async {
    await _client.rpc<dynamic>(
      'set_close_friends',
      params: {'p_friend_ids': ids.toList()},
    );
  }

  @override
  Future<void> report(
    String id, {
    required ReportReason reason,
    String details = '',
    bool alsoBlock = false,
  }) async {
    await _client.rpc<dynamic>(
      'report_story',
      params: {
        'p_story_id': id,
        'p_reason': reason.value,
        'p_details': details,
        'p_also_block': alsoBlock,
      },
    );
  }

  @override
  Future<String> signedUrl(String path) {
    return _client.storage.from(storiesBucket).createSignedUrl(path, 3600);
  }

  @override
  Stream<StorySignal> signals() {
    RealtimeChannel? channel;
    late StreamController<StorySignal> controller;
    controller = StreamController<StorySignal>(
      onListen: () {
        // A private channel of the person's own: the database tells only
        // them, and only about what they may see.
        final live = _client.channel(
          storiesTopic(_userId),
          opts: privateChannelConfig(),
        );
        channel = live;
        for (final kind in [
          StorySignalKind.story,
          StorySignalKind.storyRemoved,
        ]) {
          live.onBroadcast(
            event: kind.wire,
            callback: (message) {
              final inner = message['payload'];
              final id = inner is Map ? inner['story_id'] : null;
              controller.add(StorySignal(kind, id is String ? id : null));
            },
          );
        }
        live.subscribe((status, error) {
          // Anything may have changed while the line was down.
          if (status == RealtimeSubscribeStatus.subscribed) {
            controller.add(const StorySignal(StorySignalKind.resync));
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
}

/// A random version 4 UUID, for a new daily's id (its files are named after
/// it).
String newStoryId() {
  final random = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int from, int to) => [
    for (var i = from; i < to; i++) bytes[i].toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// Stands in before Supabase is set up (tests): nothing to show, nothing is
/// stored.
class UninitializedStoriesRepository implements StoriesRepository {
  const UninitializedStoriesRepository();

  static StateError _unavailable() =>
      StateError('Supabase must be initialized to use the Daily.');

  @override
  Future<List<StoryTrayEntry>> tray() async => const [];

  @override
  Future<List<Story>> storiesOf(String authorId) async => const [];

  @override
  Future<void> create({
    required String id,
    MomentPhotoDraft? photo,
    MomentVideoDraft? video,
    String caption = '',
    MomentAudience audience = MomentAudience.everyone,
    void Function(double? progress)? onUploadProgress,
  }) => throw _unavailable();

  @override
  Future<void> delete(String id) => throw _unavailable();

  @override
  Future<void> markViewed(String id) async {}

  @override
  Future<List<StoryViewerEntry>> viewers(String id) async => const [];

  @override
  Future<void> react(String id, String? emoji) => throw _unavailable();

  @override
  Future<void> reply(String id, String body, {String? clientId}) =>
      throw _unavailable();

  @override
  Future<StoryRefInfo?> refOf(String id) async => null;

  @override
  Future<Set<String>> closeFriends() async => const {};

  @override
  Future<void> setCloseFriends(Set<String> ids) => throw _unavailable();

  @override
  Future<void> report(
    String id, {
    required ReportReason reason,
    String details = '',
    bool alsoBlock = false,
  }) => throw _unavailable();

  @override
  Future<String> signedUrl(String path) => throw _unavailable();

  @override
  Stream<StorySignal> signals() => const Stream.empty();
}

final storiesRepositoryProvider = Provider<StoriesRepository>((ref) {
  try {
    return SupabaseStoriesRepository(
      ref.watch(supabaseClientProvider),
      ref.watch(chatMediaUploaderProvider),
    );
  } on ProviderException {
    return const UninitializedStoriesRepository();
  }
});
