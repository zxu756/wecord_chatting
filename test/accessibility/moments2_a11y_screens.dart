// Moments 2.0 (B2) for the accessibility guard (guidelines_test.dart) and the
// accessibility screenshot tool: reminding friends to read a Moment, pinned
// Moments, described photos, a picture or sticker on a comment, a Moment sent
// to a chat as a card, and the reminders in Notifications.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/accessibility/image_alt_sheet.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/moments/moment_card_view.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/moments/moments_fakes.dart';
import '../features/wallpapers/wallpaper_fakes.dart'
    show samplePhotoBytes, settleWithImages;
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

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
  ),
);

/// The photos of [postId] with a description on the first.
List<MomentPhoto> _described(
  FakeMomentsRepository repository,
  String postId,
  int count, {
  String authorId = 'user-1',
}) {
  return [
    for (var i = 0; i < count; i++)
      () {
        final path = '$authorId/$postId-$i.jpg';
        final thumb = '$authorId/$postId-$i-t.jpg';
        repository.bucket[path] = samplePhotoBytes(width: 480, height: 320);
        repository.bucket[thumb] = samplePhotoBytes(width: 160, height: 107);
        return MomentPhoto(
          path: path,
          thumb: thumb,
          width: 480,
          height: 320,
          alt: i == 0 ? 'Two hikers on the ridge at sunrise' : null,
        );
      }(),
  ];
}

FakeMomentsRepository _server() {
  final repository = FakeMomentsRepository(posts: []);
  repository.bucket['user-3/c-c1.png'] = samplePhotoBytes(
    width: 200,
    height: 200,
  );
  repository.bucket['user-2/c-c2.jpg'] = samplePhotoBytes(
    width: 240,
    height: 180,
  );
  repository.posts = [
    post(
      'm1',
      authorId: 'user-2',
      authorName: 'Bart Simmons',
      body:
          'Dinner at ours on Friday, bring a friend or two and something to drink.',
      minutesAgo: 14,
      mentionedMe: true,
      comments: [
        comment(
          'c1',
          'user-3',
          'Grace Hopper',
          '',
          image: const MomentCommentImage(
            path: 'user-3/c-c1.png',
            width: 200,
            height: 200,
            alt: 'A cat giving a thumbs up',
          ),
        ),
        comment('c3', 'user-1', 'Ada Lovelace', 'Count me in'),
      ],
    ),
    post(
      'm2',
      authorId: 'user-1',
      authorName: 'Ada Lovelace',
      body:
          'North lot at sunrise. Worth the 5 am alarm, the cold hands and the long walk back down.',
      photos: _described(repository, 'm2', 3),
      location: 'Serra da Estrela',
      minutesAgo: 95,
      pinnedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      mentions: const [
        MomentMention(userId: 'user-2', name: 'Bart Simmons'),
        MomentMention(userId: 'user-3', name: 'Grace Hopper'),
        MomentMention(userId: 'user-4', name: 'Linus'),
      ],
      comments: [
        comment(
          'c2',
          'user-2',
          'Bart Simmons',
          'Stunning',
          image: const MomentCommentImage(
            path: 'user-2/c-c2.jpg',
            width: 240,
            height: 180,
          ),
        ),
      ],
    ),
    post(
      'm3',
      authorId: 'user-1',
      authorName: 'Ada Lovelace',
      body:
          'Notes on the engine, with the second and third pages still to write up before Thursday.',
      minutesAgo: 600,
    ),
  ];
  repository.cardInfos['m2'] = const MomentCardInfo(
    postId: 'm2',
    authorId: 'user-1',
    authorName: 'Ada Lovelace',
    kind: MomentKind.photos,
    excerpt: 'North lot at sunrise. Worth the 5 am alarm.',
    thumb: 'user-1/m2-0-t.jpg',
    photoCount: 3,
  );
  repository.notificationList = [
    MomentNotification(
      id: 'n1',
      kind: MomentNotificationKind.mention,
      postId: 'm1',
      actorId: 'user-2',
      actorName: 'Bart Simmons',
      createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 14)),
      isUnread: true,
      postExcerpt: 'Dinner at ours on Friday, bring a friend.',
    ),
    MomentNotification(
      id: 'n2',
      kind: MomentNotificationKind.comment,
      postId: 'm2',
      actorId: 'user-2',
      actorName: 'Bart Simmons',
      createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 40)),
      isUnread: false,
      hasImage: true,
      postExcerpt: 'North lot at sunrise.',
    ),
  ];
  return repository;
}

Future<void> _open(
  WidgetTester tester,
  PhoneWorld world,
  String location, {
  FakeMomentPhotoPicker? picker,
  FakeMomentsRepository? repository,
}) async {
  world.extraOverrides = momentsOverrides(
    repository: repository ?? _server(),
    tags: _tags(),
    picker: picker,
  );
  await world.open(tester, location);
  await settleWithImages(tester);
}

Future<void> _composerWithPhotos(WidgetTester tester, PhoneWorld world) async {
  await _open(
    tester,
    world,
    '/moments/compose',
    picker: FakeMomentPhotoPicker(available: 3),
  );
  await tester.enterText(
    find.byKey(const ValueKey('moment-text')),
    'Sunday hike with the whole crew',
  );
  await tester.tap(find.byKey(const ValueKey('moment-add-photos')));
  await settleWithImages(tester);
}

Future<void> _describeFirstPhoto(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('moment-draft-describe-0')));
  await settle(tester);
  await tester.enterText(
    find.byKey(ImageAltSheet.fieldKey('pick-0')),
    'Two hikers on the ridge at sunrise',
  );
  await tester.tap(find.byKey(ImageAltSheet.saveKey));
  await settleWithImages(tester);
}

Future<void> _chat(
  WidgetTester tester,
  PhoneWorld world,
  List<Map<String, dynamic>> cards,
) async {
  final repository = _server();
  world.extraOverrides = momentsOverrides(repository: repository);
  world.chats.messages = [
    for (final (index, card) in cards.indexed)
      phoneMessage(
        'card-$index',
        bart,
        '[Moment]',
        minutesAgo: 6 - index * 2,
        attachment: card,
      ),
  ];
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
  await settleWithImages(tester);
}

final moments2A11yScreens = <A11yScreen>[
  A11yScreen('moments2-composer', (tester, world) async {
    await _composerWithPhotos(tester, world);
    await _describeFirstPhoto(tester);
    await tester.tap(find.byKey(const ValueKey('moment-mention')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('mention-friend-user-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mention-friend-user-3')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mention-done')));
    await settleWithImages(tester);
  }),
  A11yScreen('moments2-mention-sheet', (tester, world) async {
    await _open(tester, world, '/moments/compose');
    await tester.tap(find.byKey(const ValueKey('moment-mention')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('mention-friend-user-3')));
    await tester.pump();
  }),
  A11yScreen('moments2-describe-sheet', (tester, world) async {
    await _composerWithPhotos(tester, world);
    await tester.tap(find.byKey(const ValueKey('moment-describe')));
    await settleWithImages(tester);
  }),
  A11yScreen('moments2-feed', (tester, world) async {
    await _open(tester, world, '/moments');
  }),
  A11yScreen('moments2-person-page', (tester, world) async {
    await _open(tester, world, '/moments/of/user-1');
  }),
  A11yScreen(
    'moments2-person-page-small',
    (tester, world) => _open(tester, world, '/moments/of/user-1'),
    viewport: smallPhone,
  ),
  A11yScreen('moments2-detail-comment-pictures', (tester, world) async {
    final picker = FakeMomentPhotoPicker()
      ..commentPhoto = MomentCommentPicture(
        bytes: samplePhotoBytes(width: 240, height: 180),
        extension: 'jpg',
        width: 240,
        height: 180,
        alt: 'A cat waving hello',
      );
    await _open(tester, world, '/moments/m1', picker: picker);
    await tester.tap(find.byKey(const ValueKey('moment-comment-attach')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('comment-attach-photo')));
    await settleWithImages(tester);
  }),
  A11yScreen('moments2-attach-choice', (tester, world) async {
    await _open(tester, world, '/moments/m1');
    await tester.tap(find.byKey(const ValueKey('moment-comment-attach')));
    await settle(tester);
  }),
  A11yScreen('moments2-share-picker', (tester, world) async {
    await _open(tester, world, '/moments');
    await tester.tap(find.byKey(const ValueKey('moment-share-m1')));
    await settle(tester);
  }),
  A11yScreen('moments2-photo-viewer-alt', (tester, world) async {
    await _open(tester, world, '/moments/of/user-1');
    await tester.tap(find.byKey(const ValueKey('moment-photo-0')));
    await settleWithImages(tester);
  }),
  A11yScreen('moments2-chat-cards', (tester, world) async {
    await _chat(tester, world, [
      {'kind': momentCardKind, 'post_id': 'm2'},
      // The reader may not see this one.
      {'kind': momentCardKind, 'post_id': 'm-gone'},
    ]);
  }),
  A11yScreen('moments2-notifications', (tester, world) async {
    await _open(tester, world, '/notifications');
  }),
  A11yScreen(
    'desktop-moments2',
    (tester, world) => _open(tester, world, '/moments/of/user-1'),
    viewport: desktopViewport,
    desktop: true,
  ),
];
