// Renders the second round of Moments: the "N new posts" pill, a video post
// in the feed and its detail, the composer with a video, Settings -> Moments
// with the notification switch, and the home entry after a live update.
// Writes PNGs for eyeballing. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/moments_more_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=build/moments-more/phone-light
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/moments/moment_photos.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/features/moments/moments_settings_screen.dart';

import '../../test/features/moments/moments_fakes.dart';
import '../../test/features/wallpapers/wallpaper_fakes.dart'
    show samplePhotoBytes, settleWithImages;
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/moments-more/phone-light',
);

const _phone = PhoneViewport(
  name: 'phone',
  size: Size(390, 844),
  devicePixelRatio: 2,
  topInset: 47,
  bottomInset: 34,
);

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    await settleWithImages(tester);
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  void screen(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        usePhoneViewport(tester, _phone);
        await body(tester);
        await shoot(tester, name);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 4));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  MomentPost videoPost(
    FakeMomentsRepository repository,
    String id, {
    String authorId = 'user-2',
    String authorName = 'Bart Simmons',
    int minutesAgo = 25,
    int seconds = 42,
  }) {
    repository.bucket['$authorId/$id-0.jpg'] = samplePhotoBytes(
      width: 480,
      height: 270,
    );
    return MomentPost(
      id: id,
      authorId: authorId,
      authorName: authorName,
      body: 'Down the valley before the fog lifted.',
      kind: MomentKind.video,
      video: MomentVideo(
        path: '$authorId/$id-v.mp4',
        poster: '$authorId/$id-0.jpg',
        thumb: '$authorId/$id-0-t.jpg',
        duration: Duration(seconds: seconds),
        width: 480,
        height: 270,
        size: 12 * 1024 * 1024,
      ),
      createdAt: DateTime.now().toUtc().subtract(Duration(minutes: minutesAgo)),
    );
  }

  FakeMomentsRepository server() {
    final repository = FakeMomentsRepository();
    repository.posts = [
      videoPost(repository, 'v1'),
      post(
        'm1',
        authorId: 'user-3',
        authorName: 'Grace Hopper',
        body: 'Found the first bug of the day, and it was an actual moth.',
        minutesAgo: 90,
        likes: const [MomentLiker(userId: 'user-2', name: 'Bart Simmons')],
      ),
    ];
    repository.bucket['user-1/cover.jpg'] = samplePhotoBytes(
      width: 800,
      height: 320,
    );
    repository.settingsValue = const MomentsSettings(
      coverPath: 'user-1/cover.jpg',
    );
    return repository;
  }

  PhoneWorld world(
    FakeMomentsRepository repository, {
    FakeMomentPhotoPicker? picker,
  }) {
    return PhoneWorld()
      ..extraOverrides = momentsOverrides(
        repository: repository,
        picker: picker,
      );
  }

  Future<void> open(WidgetTester tester, PhoneWorld w, String location) async {
    await w.open(tester, location);
    await settleWithImages(tester);
  }

  screen('l1-feed-new-posts-pill', (tester) async {
    final repository = server();
    await open(tester, world(repository), '/moments');
    repository.posts = [
      post(
        'n1',
        authorId: 'user-3',
        authorName: 'Grace Hopper',
        body: 'Just landed.',
        minutesAgo: 0,
      ),
      post(
        'n2',
        authorId: 'user-4',
        authorName: 'Linus Pauling',
        body: 'Coffee first.',
        minutesAgo: 0,
      ),
      ...repository.posts,
    ];
    repository.emit(MomentsSignalKind.post, 'n1');
    await tester.pump();
    await tester.pump(momentsLiveDelay + const Duration(milliseconds: 100));
  });

  screen('l2-feed-video', (tester) async {
    await open(tester, world(server()), '/moments');
  });

  screen('l3-video-detail', (tester) async {
    await open(tester, world(server()), '/moments/v1');
  });

  screen('l4-composer-video', (tester) async {
    final picker = FakeMomentPhotoPicker()..video = sampleVideo(seconds: 38);
    await open(
      tester,
      world(FakeMomentsRepository(), picker: picker),
      '/moments/compose',
    );
    await tester.enterText(
      find.byKey(const ValueKey('moment-text')),
      'Down the valley before the fog lifted.',
    );
    await tester.tap(find.byKey(const ValueKey('moment-add-video')));
    await settleWithImages(tester);
  });

  screen('l5-composer-add-media', (tester) async {
    await open(tester, world(FakeMomentsRepository()), '/moments/compose');
  });

  screen('l6-composer-video-too-long', (tester) async {
    final picker = FakeMomentPhotoPicker()
      ..videoProblem = MomentVideoProblem.tooLong;
    await open(
      tester,
      world(FakeMomentsRepository(), picker: picker),
      '/moments/compose',
    );
    await tester.tap(find.byKey(const ValueKey('moment-add-video')));
    await settleWithImages(tester);
  });

  screen('l7-settings-notifications', (tester) async {
    final w = world(server());
    await pumpStandalone(tester, w, const MomentsSettingsScreen());
  });

  screen('l8-home-entry-live', (tester) async {
    final repository = server();
    await open(tester, world(repository), '/');
    repository.unseenValue = const MomentsUnseen(
      count: 1,
      latestAuthorId: 'user-3',
      latestAuthorName: 'Grace Hopper',
    );
    repository.emit(MomentsSignalKind.post, 'v1');
    await tester.pump();
    await tester.pump(momentsLiveDelay + const Duration(milliseconds: 100));
  });
}
