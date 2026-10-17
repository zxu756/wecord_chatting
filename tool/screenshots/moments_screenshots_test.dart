// Renders Moments, tags and starred friends: the feed with its cover, the
// composer, the visibility picker, a post with comments, a friend's page,
// Settings -> Moments, the Tags page and its editor, the friends list with
// stars and tag chips, a profile, Notifications and the Home entries. Writes
// PNGs for eyeballing. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/moments_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=build/moments/phone-light
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme and
// --dart-define=MOMENTS_DESKTOP=true for the 1440x900 desktop.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_settings_screen.dart';

import '../../test/features/moments/moments_fakes.dart';
import '../../test/features/wallpapers/wallpaper_fakes.dart'
    show samplePhotoBytes, settleWithImages;
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/moments/phone-light',
);
const _desktop = bool.fromEnvironment('MOMENTS_DESKTOP');

const _phone = PhoneViewport(
  name: 'phone',
  size: Size(390, 844),
  devicePixelRatio: 2,
  topInset: 47,
  bottomInset: 34,
);
const _wide = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
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
      debugDefaultTargetPlatformOverride = _desktop
          ? TargetPlatform.macOS
          : TargetPlatform.iOS;
      try {
        usePhoneViewport(tester, _desktop ? _wide : _phone);
        await body(tester);
        await shoot(tester, name);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 4));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  // The people: friends of Ada with short names, so the cards read well.
  final bart = phoneProfile('user-2', 'bart', 'Bart Simmons');
  final grace = phoneProfile('user-3', 'grace', 'Grace Hopper');
  final linus = phoneProfile('user-4', 'linus', 'Linus Pauling');
  final mae = phoneProfile('user-5', 'mae', 'Mae Jemison');
  final people = [bart, grace, linus, mae];

  FakeMomentsRepository server() {
    final repository = FakeMomentsRepository();
    String bucketPhoto(String path, {int w = 480, int h = 320}) {
      repository.bucket[path] = samplePhotoBytes(width: w, height: h);
      return path;
    }

    List<MomentPhoto> pics(String author, String id, int count) => [
      for (var i = 0; i < count; i++)
        MomentPhoto(
          path: bucketPhoto(
            '$author/$id-$i.jpg',
            w: i.isOdd ? 320 : 480,
            h: i.isOdd ? 480 : 320,
          ),
          thumb: bucketPhoto(
            '$author/$id-$i-t.jpg',
            w: i.isOdd ? 107 : 160,
            h: i.isOdd ? 160 : 107,
          ),
          width: i.isOdd ? 320 : 480,
          height: i.isOdd ? 480 : 320,
        ),
    ];

    repository.posts = [
      post(
        'm1',
        authorId: 'user-3',
        authorName: 'Grace Hopper',
        body: 'Found the first bug of the day, and it was an actual moth.',
        minutesAgo: 12,
        likes: const [
          MomentLiker(userId: 'user-2', name: 'Bart Simmons'),
          MomentLiker(userId: 'user-4', name: 'Linus Pauling'),
          MomentLiker(userId: 'user-1', name: 'Ada Lovelace'),
        ],
        likedByMe: true,
        comments: [
          comment('c1', 'user-2', 'Bart Simmons', 'Frame it!', minutesAgo: 9),
          comment(
            'c2',
            'user-3',
            'Grace Hopper',
            'Already taped it into the log book',
            replyToId: 'c1',
            replyToUserId: 'user-2',
            replyToName: 'Bart Simmons',
            minutesAgo: 4,
          ),
        ],
      ),
      post(
        'm2',
        authorId: 'user-2',
        authorName: 'Bart Simmons',
        body: 'North lot at sunrise. Worth the 5 am alarm.',
        photos: pics('user-2', 'm2', 3),
        location: 'Serra da Estrela',
        minutesAgo: 95,
        likes: const [
          MomentLiker(userId: 'user-3', name: 'Grace Hopper'),
          MomentLiker(userId: 'user-5', name: 'Mae Jemison'),
        ],
        comments: [
          comment(
            'c3',
            'user-5',
            'Mae Jemison',
            'Gorgeous light',
            minutesAgo: 60,
          ),
        ],
      ),
      post(
        'm3',
        authorId: 'user-1',
        authorName: 'Ada Lovelace',
        body: 'Notes on the engine, version 2.',
        photos: pics('user-1', 'm3', 4),
        minutesAgo: 60 * 5,
        visibility: MomentVisibility.only,
      ),
      post(
        'm4',
        authorId: 'user-5',
        authorName: 'Mae Jemison',
        body: 'Reading list for the long flight.',
        linkUrl: 'https://example.com/reading-list',
        minutesAgo: 60 * 26,
      ),
      post(
        'm5',
        authorId: 'user-4',
        authorName: 'Linus Pauling',
        body: 'Nine shots from the weekend.',
        photos: pics('user-4', 'm5', 9),
        minutesAgo: 60 * 50,
      ),
    ];
    return repository;
  }

  FakeFriendTagsRepository tags() => FakeFriendTagsRepository(
    const FriendTagsData(
      tags: [
        FriendTag(id: 'tag-family', name: 'Family'),
        FriendTag(id: 'tag-work', name: 'Work'),
        FriendTag(id: 'tag-climb', name: 'Climbing'),
      ],
      members: {
        'tag-family': {'user-2'},
        'tag-work': {'user-3', 'user-5'},
        'tag-climb': {'user-2', 'user-4', 'user-5'},
      },
      starred: {'user-3', 'user-4'},
    ),
  );

  PhoneWorld world(
    FakeMomentsRepository repository, {
    FakeFriendTagsRepository? friendTags,
    FakeMomentPhotoPicker? picker,
  }) {
    final w = PhoneWorld()
      ..extraOverrides = momentsOverrides(
        repository: repository,
        tags: friendTags ?? tags(),
        picker: picker,
      );
    w.contacts.friends = people;
    return w;
  }

  Future<void> open(WidgetTester tester, PhoneWorld w, String location) async {
    await w.open(tester, location);
    await settleWithImages(tester);
  }

  screen('m1-feed', (tester) async {
    final repository = server()
      ..settingsValue = const MomentsSettings(coverPath: 'user-1/cover.jpg');
    repository.bucket['user-1/cover.jpg'] = samplePhotoBytes(
      width: 800,
      height: 320,
    );
    await open(tester, world(repository), '/moments');
  });

  screen('m2-feed-scrolled', (tester) async {
    await open(tester, world(server()), '/moments');
    await tester.drag(
      find.byKey(const ValueKey('moments-list')),
      const Offset(0, -520),
    );
    await settleWithImages(tester);
  });

  screen('m3-feed-empty', (tester) async {
    await open(tester, world(FakeMomentsRepository()), '/moments');
  });

  screen('m4-composer-empty', (tester) async {
    await open(tester, world(FakeMomentsRepository()), '/moments/compose');
  });

  screen('m5-composer-filled', (tester) async {
    final w = world(
      FakeMomentsRepository(),
      picker: FakeMomentPhotoPicker(available: 5),
    );
    await open(tester, w, '/moments/compose');
    await tester.enterText(
      find.byKey(const ValueKey('moment-text')),
      'Sunday hike with the whole crew. Cold start, warm finish.',
    );
    await tester.tap(find.byKey(const ValueKey('moment-add-photos')));
    await settleWithImages(tester);
    await tester.tap(find.byKey(const ValueKey('moment-add-location')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('moment-location-field')),
      'Serra da Estrela',
    );
    await tester.pump();
  });

  screen('m6-audience', (tester) async {
    await open(tester, world(FakeMomentsRepository()), '/moments/compose');
    await tester.tap(find.byKey(const ValueKey('moment-audience')));
    await settle(tester);
  });

  screen('m7-audience-only-share-with', (tester) async {
    await open(tester, world(FakeMomentsRepository()), '/moments/compose');
    await tester.tap(find.byKey(const ValueKey('moment-audience')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('audience-only')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('audience-tag-tag-family')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('audience-friend-user-4')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('audience-friend-user-4')));
    await settle(tester);
  });

  screen('m8-audience-dont-share-with', (tester) async {
    await open(tester, world(FakeMomentsRepository()), '/moments/compose');
    await tester.tap(find.byKey(const ValueKey('moment-audience')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('audience-except')));
    await settle(tester);
  });

  screen('m9-post-detail', (tester) async {
    final repository = server();
    await open(tester, world(repository), '/moments/m2?reply=c3');
  });

  screen('m10-friend-page', (tester) async {
    final repository = server()
      ..profiles['user-4'] = const MomentsProfile(
        userId: 'user-4',
        name: 'Linus Pauling',
      );
    await open(tester, world(repository), '/moments/of/user-4');
  });

  screen('m11-settings-moments', (tester) async {
    final repository = server()
      ..settingsValue = const MomentsSettings(range: MomentsRange.sixMonths)
      ..prefs = const [
        MomentsFriendPref(
          friendId: 'user-2',
          name: 'Bart Simmons',
          hideMine: true,
        ),
        MomentsFriendPref(
          friendId: 'user-4',
          name: 'Linus Pauling',
          hideTheirs: true,
        ),
        MomentsFriendPref(
          friendId: 'user-5',
          name: 'Mae Jemison',
          hideMine: true,
        ),
      ];
    final w = world(repository);
    await pumpStandalone(tester, w, const MomentsSettingsScreen());
  });

  screen('m12-visible-range', (tester) async {
    final w = world(server());
    await pumpStandalone(tester, w, const MomentsSettingsScreen());
    await tester.tap(find.byKey(const ValueKey('moments-range-row')));
    await settle(tester);
  });

  screen('m13-tags', (tester) async {
    await open(tester, world(server()), '/tags');
  });

  screen('m14-tag-editor', (tester) async {
    await open(tester, world(server()), '/tags');
    await tester.tap(find.byKey(const ValueKey('tag-row-tag-climb')));
    await settle(tester);
  });

  screen('m15-friends-starred-and-tags', (tester) async {
    await open(tester, world(server()), '/contacts');
  });

  screen('m16-friends-filtered-by-tag', (tester) async {
    await open(tester, world(server()), '/contacts');
    await tester.tap(find.byKey(const ValueKey('friends-filter-tag-tag-work')));
    await settle(tester);
  });

  screen('m17-profile-star-tags', (tester) async {
    await open(tester, world(server()), '/profile/user-2');
  });

  screen('m18-profile-tags-picker', (tester) async {
    await open(tester, world(server()), '/profile/user-2');
    await tester.tap(find.byKey(const ValueKey('profile-tags')));
    await settle(tester);
  });

  screen('m19-notifications-moments', (tester) async {
    final repository = server()
      ..notificationList = [
        MomentNotification(
          id: 'n1',
          kind: MomentNotificationKind.like,
          postId: 'm3',
          actorId: 'user-3',
          actorName: 'Grace Hopper',
          createdAt: DateTime.now().toUtc().subtract(
            const Duration(minutes: 7),
          ),
          isUnread: true,
          postThumb: 'user-1/m3-0-t.jpg',
        ),
        MomentNotification(
          id: 'n2',
          kind: MomentNotificationKind.comment,
          postId: 'm3',
          actorId: 'user-2',
          actorName: 'Bart Simmons',
          snippet: 'Is that the analytical engine? Send the schematics.',
          createdAt: DateTime.now().toUtc().subtract(
            const Duration(minutes: 40),
          ),
          isUnread: true,
          postThumb: 'user-1/m3-0-t.jpg',
        ),
        MomentNotification(
          id: 'n3',
          kind: MomentNotificationKind.reply,
          postId: 'm4',
          actorId: 'user-5',
          actorName: 'Mae Jemison',
          snippet: 'Same here, adding it to my list.',
          postExcerpt: 'Reading list for the long flight.',
          createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 5)),
          isUnread: false,
        ),
      ];
    repository.bucket['user-1/m3-0-t.jpg'] = samplePhotoBytes(
      width: 160,
      height: 107,
    );
    await open(tester, world(repository), '/notifications');
    await tester.ensureVisible(
      find.byKey(const ValueKey('inbox-filter-moments')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('inbox-filter-moments')));
    await settleWithImages(tester);
  });

  screen('m20-home-moments-entry', (tester) async {
    final repository = server()
      ..unseenValue = const MomentsUnseen(
        count: 2,
        latestAuthorId: 'user-3',
        latestAuthorName: 'Grace Hopper',
      );
    await open(tester, world(repository), '/');
  });

  screen('m21-comment-menu', (tester) async {
    final repository = server();
    await open(tester, world(repository), '/moments/m2');
    await tester.longPress(find.byKey(const ValueKey('moment-comment-c3')));
    await settle(tester);
  });
}
