// The Moments, tags and starred friends screens, for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_settings_screen.dart';

import '../features/moments/moments_fakes.dart';
import '../features/wallpapers/wallpaper_fakes.dart'
    show samplePhotoBytes, settleWithImages;
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

FakeMomentsRepository _server() {
  final repository = FakeMomentsRepository(posts: []);
  final pictures = photos(repository, 'p2', 3);
  repository.posts = [
    post(
      'p1',
      authorId: 'user-3',
      authorName: 'Grace Hopper',
      body: 'Found the first bug of the day, and it was an actual moth.',
      minutesAgo: 12,
      likedByMe: true,
      likes: const [
        MomentLiker(userId: 'user-2', name: 'Bart Simmons'),
        MomentLiker(userId: 'user-1', name: 'Ada Lovelace'),
      ],
      comments: [
        comment('c1', 'user-2', 'Bart Simmons', 'Frame it!'),
        comment(
          'c2',
          'user-3',
          'Grace Hopper',
          'Already taped it into the log book',
          replyToId: 'c1',
          replyToUserId: 'user-2',
          replyToName: 'Bart Simmons',
        ),
      ],
    ),
    post(
      'p2',
      body: 'North lot at sunrise. Worth the 5 am alarm.',
      photos: pictures,
      location: 'Serra da Estrela',
      minutesAgo: 95,
    ),
    post(
      'p3',
      authorId: 'user-1',
      authorName: 'Ada Lovelace',
      body: 'Notes on the engine.',
      minutesAgo: 600,
      visibility: MomentVisibility.private,
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

FakeFriendTagsRepository _tags() => FakeFriendTagsRepository(
  const FriendTagsData(
    tags: [
      FriendTag(id: 'tag-family', name: 'Family'),
      FriendTag(id: 'tag-work', name: 'Work'),
    ],
    members: {
      'tag-family': {'user-2'},
      'tag-work': {'user-3', 'user-4'},
    },
    starred: {'user-3'},
  ),
);

Future<void> _open(
  WidgetTester tester,
  PhoneWorld world,
  String location, {
  FakeMomentPhotoPicker? picker,
}) async {
  world.extraOverrides = momentsOverrides(
    repository: _server(),
    tags: _tags(),
    picker: picker,
  );
  await world.open(tester, location);
  await settleWithImages(tester);
}

final momentsA11yScreens = <A11yScreen>[
  A11yScreen(
    'moments-feed',
    (tester, world) => _open(tester, world, '/moments'),
  ),
  A11yScreen(
    'moments-feed-friend-page',
    (tester, world) => _open(tester, world, '/moments/of/user-3'),
  ),
  A11yScreen('moments-composer', (tester, world) async {
    await _open(
      tester,
      world,
      '/moments/compose',
      picker: FakeMomentPhotoPicker(available: 4),
    );
    await tester.enterText(
      find.byKey(const ValueKey('moment-text')),
      'Sunday hike',
    );
    await tester.tap(find.byKey(const ValueKey('moment-add-photos')));
    await settleWithImages(tester);
  }),
  A11yScreen('moments-audience', (tester, world) async {
    await _open(tester, world, '/moments/compose');
    await tester.tap(find.byKey(const ValueKey('moment-audience')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('audience-only')));
    await settle(tester);
  }),
  A11yScreen(
    'moments-detail',
    (tester, world) => _open(tester, world, '/moments/p1?reply=c1'),
  ),
  A11yScreen('moments-settings', (tester, world) async {
    world.extraOverrides = momentsOverrides(repository: _server());
    await pumpStandalone(tester, world, const MomentsSettingsScreen());
  }),
  A11yScreen('tags', (tester, world) => _open(tester, world, '/tags')),
  A11yScreen('tag-editor', (tester, world) async {
    await _open(tester, world, '/tags');
    await tester.tap(find.byKey(const ValueKey('tag-row-tag-work')));
    await settle(tester);
  }),
  A11yScreen('friends-starred-and-tags', (tester, world) async {
    await _open(tester, world, '/contacts');
  }),
  A11yScreen('profile-star-tags', (tester, world) async {
    await _open(tester, world, '/profile/user-2');
  }),
  A11yScreen(
    'desktop-moments',
    (tester, world) => _open(tester, world, '/moments'),
    viewport: desktopViewport,
    desktop: true,
  ),
];
