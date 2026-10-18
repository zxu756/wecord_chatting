import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/moments/moment_photos.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_video.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';
import '../wallpapers/wallpaper_fakes.dart' show samplePhotoBytes;
import 'moments_fakes.dart';
import 'moments_screens_test.dart' show openMoments;

MomentPost videoPost(String id, {int seconds = 42}) => MomentPost(
  id: id,
  authorId: 'user-2',
  authorName: 'Bart the Bold',
  body: 'Down the valley',
  kind: MomentKind.video,
  video: MomentVideo(
    path: 'user-2/$id-v.mp4',
    poster: 'user-2/$id-0.jpg',
    thumb: 'user-2/$id-0-t.jpg',
    duration: Duration(seconds: seconds),
    width: 480,
    height: 320,
    size: 3000000,
  ),
  createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
);

void main() {
  group('the model', () {
    test('reads the video of a post and writes its length as m:ss', () {
      final post = MomentPost.fromJson({
        'id': 'p1',
        'author_id': 'user-2',
        'author_name': 'Bart',
        'kind': 'video',
        'photos': <Object>[],
        'video': {
          'path': 'user-2/p1-v.mov',
          'poster': 'user-2/p1-0.jpg',
          'thumb': 'user-2/p1-0-t.jpg',
          'w': 640,
          'h': 360,
          'duration_ms': 61000,
          'size': 123,
          'mime': 'video/quicktime',
        },
        'created_at': '2026-10-18T10:00:00Z',
      });
      expect(post.kind, MomentKind.video);
      expect(post.video!.mimeType, 'video/quicktime');
      expect(post.video!.durationLabel, '1:01');
      expect(post.video!.aspectRatio, closeTo(16 / 9, 0.001));
      expect(post.copyWith(likeCount: 1).video, isNotNull);
    });

    test('a post without a video has none', () {
      expect(post('p2').video, isNull);
    });

    test('the viewer opens the file of the private bucket as a video', () {
      final file = MomentVideoTile(video: videoPost('p3').video!).file;
      expect(file.bucket, 'moments');
      expect(file.path, 'user-2/p3-v.mp4');
      expect(file.kind, PreviewKind.video);
    });
  });

  group('choosing a video', () {
    final temp = Directory.systemTemp.createTempSync('moment-video-test');
    tearDownAll(() => temp.deleteSync(recursive: true));

    /// A real file: XFile.fromData ignores its name outside the web.
    XFile video({
      String name = 'walk.mp4',
      int bytes = 64,
      String mime = 'video/mp4',
    }) {
      final file = File('${temp.path}/$name')..writeAsBytesSync(Uint8List(8));
      if (bytes != 8) {
        final handle = file.openSync(mode: FileMode.append)
          ..setPositionSync(0)
          ..truncateSync(bytes);
        handle.closeSync();
      }
      return XFile(file.path, mimeType: mime);
    }

    Future<Uint8List?> poster(XFile file) async =>
        samplePhotoBytes(width: 480, height: 270);

    Future<Duration?> seconds(int value) async => Duration(seconds: value);

    testWidgets('accepts a short video and makes its poster', (tester) async {
      final draft = await tester.runAsync(
        () => prepareMomentVideo(
          video(),
          videoPoster: poster,
          videoDuration: (file) => seconds(42),
        ),
      );
      expect(draft!.duration, const Duration(seconds: 42));
      expect(draft.mimeType, 'video/mp4');
      expect(draft.extension, 'mp4');
      expect(draft.poster, isNotEmpty);
      expect(draft.posterThumb, isNotEmpty);
      expect(draft.width, greaterThan(0));
    });

    testWidgets('a minute is fine, a little over it is not', (tester) async {
      final ok = await tester.runAsync(
        () => prepareMomentVideo(
          video(),
          videoPoster: poster,
          videoDuration: (file) => seconds(60),
        ),
      );
      expect(ok, isNotNull);

      Future<MomentVideoProblem?> problem(
        XFile file,
        Future<Duration?> Function(XFile) duration,
      ) async {
        try {
          await prepareMomentVideo(
            file,
            videoPoster: poster,
            videoDuration: duration,
          );
        } on MomentVideoException catch (error) {
          return error.problem;
        }
        return null;
      }

      expect(
        await tester.runAsync(() => problem(video(), (f) => seconds(61))),
        MomentVideoProblem.tooLong,
      );
      expect(
        await tester.runAsync(
          () => problem(
            video(name: 'clip.mov', mime: 'video/quicktime'),
            (f) => seconds(600),
          ),
        ),
        MomentVideoProblem.tooLong,
      );
      expect(
        await tester.runAsync(() => problem(video(), (f) async => null)),
        MomentVideoProblem.unreadable,
      );
      expect(
        await tester.runAsync(
          () => problem(
            video(name: 'notes.txt', mime: 'text/plain'),
            (f) => seconds(5),
          ),
        ),
        MomentVideoProblem.unsupported,
      );
      expect(
        await tester.runAsync(
          () => problem(
            video(name: 'clip.avi', mime: 'video/x-msvideo'),
            (f) => seconds(5),
          ),
        ),
        MomentVideoProblem.unsupported,
      );
    });

    testWidgets('a video over 50 MB is refused before it is read', (
      tester,
    ) async {
      var posterCalls = 0;
      final big = video(name: 'big.mp4', bytes: maxMomentVideoBytes + 1);
      Object? caught;
      await tester.runAsync(() async {
        try {
          await prepareMomentVideo(
            big,
            videoPoster: (file) async {
              posterCalls += 1;
              return null;
            },
            videoDuration: (file) => seconds(5),
          );
        } on MomentVideoException catch (error) {
          caught = error.problem;
        }
      });
      expect(caught, MomentVideoProblem.tooBig);
      expect(posterCalls, 0);
    });
  });

  group('the composer', () {
    testWidgets('offers a video while there are no photos and posts it', (
      tester,
    ) async {
      final repository = FakeMomentsRepository();
      final picker = FakeMomentPhotoPicker()..video = sampleVideo();
      await openMoments(
        tester,
        repository,
        location: '/moments/compose',
        picker: picker,
      );
      expect(find.byKey(const ValueKey('moment-add-video')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('moment-add-video')));
      await settle(tester);
      expect(find.byKey(const ValueKey('moment-video-draft')), findsOneWidget);
      expect(find.text('0:42'), findsOneWidget);
      // A video replaces the photos and the link.
      expect(find.byKey(const ValueKey('moment-add-photos')), findsNothing);
      expect(find.byKey(const ValueKey('moment-add-link')), findsNothing);
      // The video alone is enough to post.
      expect(
        tester
            .widget<WeCordButton>(find.byKey(const ValueKey('moment-post')))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);

      final created = repository.created.single;
      expect(created.video, isNotNull);
      expect(created.photoCount, 0);
      final stored = repository.posts.single;
      expect(stored.kind, MomentKind.video);
      expect(stored.video!.duration, const Duration(seconds: 42));
      // Back on the feed with the video's poster and length.
      expect(find.byKey(const ValueKey('moment-video')), findsOneWidget);
    });

    testWidgets('the video can be taken out again', (tester) async {
      final repository = FakeMomentsRepository();
      final picker = FakeMomentPhotoPicker()..video = sampleVideo();
      await openMoments(
        tester,
        repository,
        location: '/moments/compose',
        picker: picker,
      );
      await tester.tap(find.byKey(const ValueKey('moment-add-video')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('moment-video-remove')));
      await settle(tester);

      expect(find.byKey(const ValueKey('moment-video-draft')), findsNothing);
      expect(find.byKey(const ValueKey('moment-add-video')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-add-photos')), findsOneWidget);
    });

    testWidgets('no video can be added once there are photos', (tester) async {
      final repository = FakeMomentsRepository();
      final picker = FakeMomentPhotoPicker(available: 2);
      await openMoments(
        tester,
        repository,
        location: '/moments/compose',
        picker: picker,
      );
      await tester.tap(find.byKey(const ValueKey('moment-add-photos')));
      await settle(tester);

      expect(find.byKey(const ValueKey('moment-add-video')), findsNothing);
    });

    for (final (problem, message) in [
      (
        MomentVideoProblem.tooLong,
        'That video is longer than 1 minute. Choose a shorter one.',
      ),
      (
        MomentVideoProblem.tooBig,
        'That video is bigger than 50 MB. Choose a smaller one.',
      ),
      (MomentVideoProblem.unsupported, 'Choose an MP4, MOV or WebM video.'),
      (
        MomentVideoProblem.unreadable,
        'Could not read that video. Try another.',
      ),
    ]) {
      testWidgets('says why a video was refused: $problem', (tester) async {
        final repository = FakeMomentsRepository();
        final picker = FakeMomentPhotoPicker()..videoProblem = problem;
        await openMoments(
          tester,
          repository,
          location: '/moments/compose',
          picker: picker,
        );
        await tester.tap(find.byKey(const ValueKey('moment-add-video')));
        await settle(tester);

        expect(find.text(message), findsOneWidget);
        expect(find.byKey(const ValueKey('moment-video-draft')), findsNothing);
        expect(repository.created, isEmpty);
      });
    }

    testWidgets('a cancelled choice changes nothing', (tester) async {
      final repository = FakeMomentsRepository();
      final picker = FakeMomentPhotoPicker();
      await openMoments(
        tester,
        repository,
        location: '/moments/compose',
        picker: picker,
      );
      await tester.tap(find.byKey(const ValueKey('moment-add-video')));
      await settle(tester);

      expect(picker.videoPicks, 1);
      expect(find.byKey(const ValueKey('moment-video-draft')), findsNothing);
      expect(find.byKey(const ValueKey('moment-error')), findsNothing);
    });
  });

  group('the feed and the detail', () {
    testWidgets('a video post shows its poster, a play button and length', (
      tester,
    ) async {
      final repository = FakeMomentsRepository(
        posts: [videoPost('v1', seconds: 75)],
      );
      repository.bucket['user-2/v1-0.jpg'] = samplePhotoBytes(
        width: 480,
        height: 320,
      );
      await openMoments(tester, repository);

      expect(find.byKey(const ValueKey('moment-video')), findsOneWidget);
      expect(find.text('1:15'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('Down the valley'), findsOneWidget);
    });

    testWidgets('the same on the detail page', (tester) async {
      final repository = FakeMomentsRepository(posts: [videoPost('v2')]);
      await openMoments(tester, repository, location: '/moments/v2');
      expect(find.byKey(const ValueKey('moment-video')), findsOneWidget);
    });
  });
}
