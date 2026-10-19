// The Daily (B1), for the accessibility guard (guidelines_test.dart) and the
// accessibility screenshot tool: the friends row with rings and the Daily
// tile, watching a friend's daily (with the reply bar), watching my own
// (who viewed, the menu), reporting one, posting one (the sources, the
// composer, who can see it, close friends), a reply in a chat, and the
// desktop sidebar.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/stories/stories_models.dart';

import '../features/moments/moments_fakes.dart' show sampleVideo;
import '../features/stories/stories_fakes.dart';
import '../features/wallpapers/wallpaper_fakes.dart' show settleWithImages;
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// A server with a few friends' dailies, mine, and a reply.
FakeStoriesRepository _server() {
  final repository = FakeStoriesRepository()
    ..tray_ = [
      entry('user-1', name: 'Ada Lovelace', isMe: true, stories: 2, unseen: 0),
      entry('user-2', name: 'Bart the Bold', stories: 3, unseen: 2),
      entry('user-3', name: 'Grace Hopper', stories: 1, unseen: 1),
      entry('user-4', name: 'Linus', stories: 2, unseen: 0),
    ]
    ..stories['user-2'] = [
      story('b1', viewed: true, caption: 'Early start', minutesAgo: 300),
      story(
        'b2',
        caption: 'North lot at sunrise. Worth the 5 am alarm.',
        minutesAgo: 95,
      ),
      story('b3', caption: 'Coffee first', minutesAgo: 20),
    ]
    ..stories['user-1'] = [
      story(
        'm1',
        authorId: 'user-1',
        caption: 'Sunday hike',
        viewCount: 12,
        reactionCount: 3,
        minutesAgo: 140,
      ),
      story(
        'm2',
        authorId: 'user-1',
        kind: StoryMediaKind.video,
        viewCount: 4,
        minutesAgo: 30,
      ),
    ]
    ..viewersList = [
      StoryViewerEntry(
        viewerId: 'user-2',
        name: 'Bart the Bold',
        viewedAt: DateTime.now().subtract(const Duration(minutes: 8)),
        emoji: '🔥',
      ),
      StoryViewerEntry(
        viewerId: 'user-3',
        name: 'Grace Hopper',
        viewedAt: DateTime.now().subtract(const Duration(hours: 1)),
        emoji: '❤️',
      ),
      StoryViewerEntry(
        viewerId: 'user-4',
        name: 'Linus',
        viewedAt: DateTime.now().subtract(const Duration(hours: 3)),
      ),
    ]
    ..closeFriendIds = {'user-2'}
    ..refs['reply-story'] = const StoryRefInfo(
      storyId: 'reply-story',
      authorId: 'user-1',
      kind: StoryMediaKind.photo,
      thumbPath: 'user-1/reply-story-t.jpg',
    );
  return repository;
}

List<Override> _overrides({FakeStoryMediaPicker? picker}) =>
    storiesOverrides(repository: _server(), picker: picker);

Future<void> _openHome(
  WidgetTester tester,
  PhoneWorld world, {
  FakeStoryMediaPicker? picker,
}) async {
  world.extraOverrides = _overrides(picker: picker);
  await world.open(tester, '/home');
  await settleWithImages(tester);
}

/// Scrolls the friends row to the friend [key].
Future<void> _scrollToFriend(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    120,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('phone-friends-row')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await settle(tester);
}

/// The viewer on Bart's dailies.
Future<void> _openViewer(WidgetTester tester, PhoneWorld world) async {
  await _openHome(tester, world);
  await _scrollToFriend(tester, 'phone-friend-user-2');
  await tester.tap(find.byKey(const ValueKey('phone-friend-user-2')));
  await settleWithImages(tester);
}

/// The viewer on my own dailies.
Future<void> _openOwnViewer(WidgetTester tester, PhoneWorld world) async {
  await _openHome(tester, world);
  await _scrollToFriend(tester, 'phone-home-daily');
  await tester.tap(find.byKey(const ValueKey('phone-home-daily')));
  await settleWithImages(tester);
}

Future<void> _openComposer(WidgetTester tester, PhoneWorld world) async {
  final picker = FakeStoryMediaPicker()..video = sampleVideo(seconds: 11);
  await _openHome(tester, world, picker: picker);
  await _scrollToFriend(tester, 'phone-home-daily');
  await tester.longPress(find.byKey(const ValueKey('phone-home-daily')));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('story-source-video')));
  await settleWithImages(tester);
}

final storiesA11yScreens = <A11yScreen>[
  A11yScreen('stories-home-row', (tester, world) async {
    await _openHome(tester, world);
    // Scrolled to the friends with a ring.
    await _scrollToFriend(tester, 'phone-friend-user-3');
  }),
  A11yScreen('stories-source-sheet', (tester, world) async {
    await _openHome(tester, world, picker: FakeStoryMediaPicker());
    // A long press posts another when some are up.
    await _scrollToFriend(tester, 'phone-home-daily');
    await tester.longPress(find.byKey(const ValueKey('phone-home-daily')));
    await settle(tester);
  }),
  A11yScreen('stories-viewer', _openViewer),
  A11yScreen('stories-viewer-typing', (tester, world) async {
    await _openViewer(tester, world);
    await tester.tap(find.byKey(const ValueKey('story-reply-field')));
    await tester.enterText(
      find.byKey(const ValueKey('story-reply-field')),
      'That light!',
    );
    await settleWithImages(tester);
  }),
  A11yScreen('stories-viewer-menu', (tester, world) async {
    await _openViewer(tester, world);
    await tester.tap(find.byKey(const ValueKey('story-menu')));
    await settle(tester);
  }),
  A11yScreen('stories-report-sheet', (tester, world) async {
    await _openViewer(tester, world);
    await tester.tap(find.byKey(const ValueKey('story-menu')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('story-menu-report')));
    await settle(tester);
  }),
  A11yScreen('stories-viewer-own', _openOwnViewer),
  A11yScreen('stories-viewers-sheet', (tester, world) async {
    await _openOwnViewer(tester, world);
    await tester.tap(find.byKey(const ValueKey('story-views-button')));
    await settleWithImages(tester);
  }),
  A11yScreen('stories-composer', _openComposer),
  A11yScreen('stories-audience', (tester, world) async {
    await _openComposer(tester, world);
    await tester.tap(find.byKey(const ValueKey('story-audience')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('audience-close')));
    await settle(tester);
  }),
  A11yScreen('stories-close-friends', (tester, world) async {
    await _openComposer(tester, world);
    await tester.tap(find.byKey(const ValueKey('story-audience')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('audience-close')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('audience-edit-close-friends')));
    await settle(tester);
  }),
  A11yScreen('stories-chat-reply', (tester, world) async {
    world.extraOverrides = _overrides();
    world.chats.messages = [
      phoneMessage('r0', bart, 'How was the hike?', minutesAgo: 20),
      phoneMessage(
        'r1',
        bart,
        'Love this one!',
        minutesAgo: 9,
        attachment: const {
          'kind': 'story_ref',
          'story_id': 'reply-story',
          'owner_id': 'user-1',
          'media_kind': 'photo',
        },
      ),
      phoneMessage('r2', me, 'Thanks, it was windy up there', minutesAgo: 6),
      phoneMessage(
        'r3',
        me,
        'This is the one that ended already',
        minutesAgo: 4,
        attachment: const {
          'kind': 'story_ref',
          'story_id': 'gone-story',
          'owner_id': 'user-2',
          'media_kind': 'video',
        },
      ),
    ];
    await world.open(tester, '/chats/dm-1');
    await settleWithImages(tester);
  }),
  A11yScreen(
    'desktop-stories-sidebar',
    (tester, world) async {
      world.extraOverrides = _overrides();
      await world.open(tester, '/moments');
      await settleWithImages(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
