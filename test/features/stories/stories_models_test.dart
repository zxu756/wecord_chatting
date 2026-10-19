import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/features/stories/story_media_picker.dart';
import 'package:wecord/features/moments/moment_photos.dart';
import 'package:wecord/shared/realtime/private_channels.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'dart:typed_data';

void main() {
  group('the row of dailies', () {
    test('reads the tray from the server', () {
      final entry = StoryTrayEntry.fromJson({
        'author_id': 'u2',
        'display_name': 'Ada',
        'avatar_url': 'a/b.png',
        'is_me': false,
        'story_count': 3,
        'unseen_count': 2,
        'latest_at': '2026-10-24T08:00:00Z',
      });
      expect(entry.authorId, 'u2');
      expect(entry.name, 'Ada');
      expect(entry.storyCount, 3);
      expect(entry.hasUnseen, isTrue);
      expect(entry.latestAt, DateTime.utc(2026, 10, 24, 8).toLocal());
      expect(
        StoryTrayEntry.fromJson({
          'author_id': 'u3',
          'display_name': 'Cy',
          'story_count': 1,
          'unseen_count': 0,
          'latest_at': '2026-10-24T08:00:00Z',
        }).hasUnseen,
        isFalse,
      );
    });
  });

  group('a daily', () {
    Map<String, dynamic> json({String kind = 'photo', int? ms}) => {
      'id': 's1',
      'author_id': 'u2',
      'media_kind': kind,
      'media_path': 'u2/s1.jpg',
      'poster_path': kind == 'video' ? 'u2/s1.jpg' : null,
      'thumb_path': 'u2/s1-t.jpg',
      'width': 720,
      'height': 1280,
      'duration_ms': ms,
      'caption': 'Hello',
      'visibility': 'close',
      'created_at': '2026-10-24T08:00:00Z',
      'expires_at': '2026-10-25T08:00:00Z',
      'viewed': true,
      'my_reaction': '🔥',
      'view_count': 4,
      'reaction_count': 1,
    };

    test('reads a photo', () {
      final story = Story.fromJson(json());
      expect(story.isVideo, isFalse);
      expect(story.visibility, 'close');
      expect(story.viewed, isTrue);
      expect(story.myReaction, '🔥');
      expect(story.viewCount, 4);
      expect(story.screenTime, storyPhotoDuration);
    });

    test('a video stays as long as it plays', () {
      final story = Story.fromJson(json(kind: 'video', ms: 9500));
      expect(story.isVideo, isTrue);
      expect(story.duration, const Duration(milliseconds: 9500));
      expect(story.screenTime, const Duration(milliseconds: 9500));
    });

    test('it ends at its time', () {
      final story = Story.fromJson(json());
      expect(
        story.hasEndedAt(story.expiresAt.subtract(const Duration(minutes: 1))),
        isFalse,
      );
      expect(story.hasEndedAt(story.expiresAt), isTrue);
    });

    test('taking a reaction back is not the same as leaving it', () {
      final story = Story.fromJson(json());
      expect(story.copyWith(viewed: false).myReaction, '🔥');
      expect(story.copyWith(myReaction: null).myReaction, isNull);
      expect(story.copyWith(myReaction: '😂').myReaction, '😂');
    });
  });

  group('words', () {
    final now = DateTime.utc(2026, 10, 24, 12);

    test('how old a daily is', () {
      expect(
        storyAgeLabel(now.subtract(const Duration(seconds: 20)), now),
        'Just now',
      );
      expect(
        storyAgeLabel(now.subtract(const Duration(minutes: 5)), now),
        '5m ago',
      );
      expect(
        storyAgeLabel(now.subtract(const Duration(hours: 3, minutes: 20)), now),
        '3h ago',
      );
    });

    test('how long my own daily has left', () {
      expect(
        storyRemainingLabel(now.add(const Duration(seconds: 20)), now),
        'Ends soon',
      );
      expect(
        storyRemainingLabel(now.add(const Duration(minutes: 40)), now),
        'Ends in 40m',
      );
      expect(
        storyRemainingLabel(
          now.add(const Duration(hours: 5, minutes: 10)),
          now,
        ),
        'Ends in 5h',
      );
    });
  });

  group('limits', () {
    test('a daily is 24 hours, 15 seconds and 20 MB', () {
      expect(storyLifetime, const Duration(hours: 24));
      expect(
        maxStoryVideoDuration,
        const Duration(seconds: 15, milliseconds: 500),
      );
      expect(maxStoryVideoBytes, 20 * 1024 * 1024);
      expect(maxStoryCaption, 200);
    });

    test('there are six quick emojis, none of them empty', () {
      expect(storyQuickEmojis, hasLength(6));
      expect(storyQuickEmojis.every((e) => e.isNotEmpty), isTrue);
    });

    test('the live topic is a private one of the person\'s own', () {
      expect(storiesTopic('u1'), 'stories:u1');
      expect(storiesTopic('u1'), isNot(momentsTopic('u1')));
    });
  });

  group('close friends in the audience', () {
    test('is its own audience, not one of the lists', () {
      const audience = MomentAudience(visibility: MomentVisibility.close);
      expect(audience.usesLists, isFalse);
      expect(audience.isComplete, isTrue);
      expect(MomentVisibility.close.wire, 'close');
      expect(MomentVisibility.fromWire('close'), MomentVisibility.close);
      expect(momentAudienceLabel(audience), 'Close friends');
    });
  });

  group('picking a video', () {
    XFile file(String name) => XFile.fromData(Uint8List(8), name: name);

    Future<Uint8List?> poster(XFile file) async => null;
    Future<Duration?> length(XFile file) async => const Duration(seconds: 9);

    test('only mp4, mov and webm', () async {
      await expectLater(
        prepareStoryVideo(
          file('clip.avi'),
          videoPoster: poster,
          videoDuration: length,
        ),
        throwsA(
          isA<MomentVideoException>().having(
            (e) => e.problem,
            'problem',
            MomentVideoProblem.unsupported,
          ),
        ),
      );
    });
  });
}
