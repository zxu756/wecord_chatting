import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/moments/moment_photos.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/features/stories/stories_providers.dart';
import 'package:wecord/features/stories/stories_repository.dart';
import 'package:wecord/features/stories/story_media_picker.dart';
import 'package:wecord/shared/models/report_reason.dart';

import '../wallpapers/wallpaper_fakes.dart' show samplePhotoBytes;

/// A daily posted through [FakeStoriesRepository.create].
class CreatedStory {
  CreatedStory({
    required this.id,
    required this.caption,
    required this.audience,
    this.photo,
    this.video,
  });

  final String id;
  final String caption;
  final MomentAudience audience;
  final MomentPhotoDraft? photo;
  final MomentVideoDraft? video;
}

/// The Daily server in memory. It does not apply the visibility rules (the
/// database does, see test/supabase/stories_behaviour.sql): [tray] and
/// [stories] already hold what the signed-in person may see.
class FakeStoriesRepository implements StoriesRepository {
  FakeStoriesRepository({this.me = 'user-1'});

  final String me;

  List<StoryTrayEntry> tray_ = [];
  final stories = <String, List<Story>>{};
  var viewersList = <StoryViewerEntry>[];
  var closeFriendIds = <String>{};
  final refs = <String, StoryRefInfo?>{};

  final created = <CreatedStory>[];
  final deleted = <String>[];
  final viewed = <String>[];
  final reactions = <(String, String?)>[];
  final replies = <(String id, String body)>[];
  final reports =
      <(String id, ReportReason reason, String details, bool block)>[];
  final savedCloseFriends = <Set<String>>[];
  var trayCalls = 0;

  final _signals = StreamController<StorySignal>.broadcast();

  /// Makes the next write fail.
  Object? failNext;

  void _maybeFail() {
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
  }

  void signal(StorySignal signal) => _signals.add(signal);

  @override
  Future<List<StoryTrayEntry>> tray() async {
    trayCalls += 1;
    return List.of(tray_);
  }

  @override
  Future<List<Story>> storiesOf(String authorId) async =>
      List.of(stories[authorId] ?? const []);

  @override
  Future<void> create({
    required String id,
    MomentPhotoDraft? photo,
    MomentVideoDraft? video,
    String caption = '',
    MomentAudience audience = MomentAudience.everyone,
    void Function(double? progress)? onUploadProgress,
  }) async {
    _maybeFail();
    if (video != null) {
      onUploadProgress?.call(0.5);
      onUploadProgress?.call(1);
    }
    created.add(
      CreatedStory(
        id: id,
        caption: caption,
        audience: audience,
        photo: photo,
        video: video,
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    _maybeFail();
    deleted.add(id);
    for (final list in stories.values) {
      list.removeWhere((story) => story.id == id);
    }
  }

  @override
  Future<void> markViewed(String id) async => viewed.add(id);

  @override
  Future<List<StoryViewerEntry>> viewers(String id) async => viewersList;

  @override
  Future<void> react(String id, String? emoji) async {
    _maybeFail();
    reactions.add((id, emoji));
  }

  @override
  Future<void> reply(String id, String body, {String? clientId}) async {
    _maybeFail();
    replies.add((id, body));
  }

  @override
  Future<StoryRefInfo?> refOf(String id) async => refs[id];

  @override
  Future<Set<String>> closeFriends() async => {...closeFriendIds};

  @override
  Future<void> setCloseFriends(Set<String> ids) async {
    _maybeFail();
    closeFriendIds = {...ids};
    savedCloseFriends.add({...ids});
  }

  @override
  Future<void> report(
    String id, {
    required ReportReason reason,
    String details = '',
    bool alsoBlock = false,
  }) async {
    _maybeFail();
    reports.add((id, reason, details, alsoBlock));
  }

  @override
  Future<String> signedUrl(String path) async => 'fake://$path';

  @override
  Stream<StorySignal> signals() => _signals.stream;
}

/// Picks nothing from the device: [photo] / [video] are what the person
/// "chooses".
class FakeStoryMediaPicker implements StoryMediaPicker {
  FakeStoryMediaPicker({this.hasCamera = false});

  @override
  bool hasCamera;

  PickedStoryPhoto? photo;
  MomentVideoDraft? video;
  MomentVideoProblem? videoProblem;
  final picks = <String>[];

  @override
  Future<PickedStoryPhoto?> pickPhoto({required bool camera}) async {
    picks.add(camera ? 'camera-photo' : 'photo');
    return photo;
  }

  @override
  Future<MomentVideoDraft?> pickVideo({required bool camera}) async {
    picks.add(camera ? 'camera-video' : 'video');
    final problem = videoProblem;
    if (problem != null) {
      throw MomentVideoException(problem);
    }
    return video;
  }
}

/// A photo to "pick": a gradient picture.
PickedStoryPhoto samplePickedPhoto() => PickedStoryPhoto(
  bytes: samplePhotoBytes(width: 360, height: 640),
  fileName: 'sunrise.jpg',
);

/// The overrides that put the Daily in memory; files of the fake bucket show
/// as a sample picture.
List<Override> storiesOverrides({
  required FakeStoriesRepository repository,
  StoryMediaPicker? picker,
}) {
  final picture = samplePhotoBytes(width: 180, height: 320);
  return [
    storiesRepositoryProvider.overrideWithValue(repository),
    ?(picker == null
        ? null
        : storyMediaPickerProvider.overrideWithValue(picker)),
    storyImageProviderFactory.overrideWithValue((url) => MemoryImage(picture)),
  ];
}

// ---- Sample data.

StoryTrayEntry entry(
  String id, {
  String name = 'Bart the Bold',
  int stories = 1,
  int unseen = 1,
  bool isMe = false,
  int minutesAgo = 30,
}) {
  return StoryTrayEntry(
    authorId: id,
    name: name,
    isMe: isMe,
    storyCount: stories,
    unseenCount: unseen,
    latestAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
  );
}

Story story(
  String id, {
  String authorId = 'user-2',
  StoryMediaKind kind = StoryMediaKind.photo,
  String caption = '',
  bool viewed = false,
  String? myReaction,
  int viewCount = 0,
  int reactionCount = 0,
  int minutesAgo = 30,
  int hoursLeft = 23,
  Duration? duration,
}) {
  final now = DateTime.now();
  return Story(
    id: id,
    authorId: authorId,
    kind: kind,
    mediaPath:
        '$authorId/$id${kind == StoryMediaKind.video ? '-v.mp4' : '.jpg'}',
    posterPath: kind == StoryMediaKind.video ? '$authorId/$id.jpg' : null,
    thumbPath: '$authorId/$id-t.jpg',
    width: 360,
    height: 640,
    duration: kind == StoryMediaKind.video
        ? duration ?? const Duration(seconds: 9)
        : null,
    caption: caption,
    createdAt: now.subtract(Duration(minutes: minutesAgo)),
    expiresAt: now.add(Duration(hours: hoursLeft)),
    viewed: viewed,
    myReaction: myReaction,
    viewCount: viewCount,
    reactionCount: reactionCount,
  );
}

Uint8List noBytes() => Uint8List(0);
