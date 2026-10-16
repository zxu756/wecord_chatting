import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/forum.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';

/// Forum channels in the full app, with the phone fakes' circle (whose
/// `help-and-questions` channel is a forum).
void main() {
  const forumPath = '/circles/circle-1/channels/conv-help';
  const forumExtra = ChatThreadRouteExtra(
    title: 'help-and-questions',
    type: ConversationType.channel,
    circleId: 'circle-1',
  );

  void useWideScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<PhoneWorld> openForum(WidgetTester tester, {PhoneWorld? world}) async {
    world ??= PhoneWorld();
    await world.open(tester, forumPath, extra: forumExtra);
    return world;
  }

  String cardTitle(WidgetTester tester, int index) {
    final cards = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('forum-post-') &&
          widget is WeCordPressable,
    );
    final card = cards.at(index);
    return tester
        .widgetList<Text>(
          find.descendant(of: card, matching: find.byType(Text)),
        )
        .map((text) => text.data)
        .whereType<String>()
        .firstWhere((text) => text != 'Pinned');
  }

  testWidgets('wide forums list posts, sort, filter and open posts', (
    tester,
  ) async {
    useWideScreen(tester);
    final world = PhoneWorld();
    world.chats.messages = forumPostMessages();
    await world.open(tester, '/circles/circle-1');

    final forumRow = find.byKey(const ValueKey('circle-channel-row-ch-help'));
    expect(
      find.descendant(
        of: forumRow,
        matching: find.byIcon(Icons.forum_outlined),
      ),
      findsOneWidget,
    );
    await tester.tap(forumRow);
    await settle(tester);

    expect(find.byKey(const ValueKey('forum-post-list')), findsOneWidget);
    expect(cardTitle(tester, 0), 'Read me first: how this forum works');
    expect(find.byKey(const ValueKey('forum-post-pinned')), findsOneWidget);
    expect(find.text('14 replies · 12m ago'), findsOneWidget);
    expect(find.byKey(const ValueKey('forum-post-thumbnail')), findsOneWidget);
    expect(world.circles.forumListCalls.last.sort, ForumPostSort.activity);

    await tester.tap(find.byKey(const ValueKey('forum-sort-button')));
    await settle(tester);
    await tester.tap(find.text('Newest').last);
    await settle(tester);
    expect(world.circles.forumListCalls.last.sort, ForumPostSort.created);
    // Pinned stays first, then newest first.
    expect(cardTitle(tester, 1), forumPostTitle);
    expect(cardTitle(tester, 2), 'Carpool from the South Bay?');

    await tester.tap(find.byKey(const ValueKey('forum-tag-filter-tag-solved')));
    await settle(tester);
    expect(world.circles.forumListCalls.last.tagId, 'tag-solved');
    expect(find.text('Bear canister rental'), findsOneWidget);
    expect(find.text('Carpool from the South Bay?'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('forum-tag-filter-tag-solved')));
    await settle(tester);
    expect(world.circles.forumListCalls.last.tagId, isNull);

    await tester.tap(find.text(forumPostTitle));
    await settle(tester);
    expect(find.byKey(const ValueKey('forum-opening-post')), findsOneWidget);
    expect(find.text('2 replies'), findsOneWidget);
    expect(find.byKey(const ValueKey('forum-post-list')), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.byKey(const ValueKey('forum-post-list')), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('forum posts stay out of the sidebar and mark the forum unread', (
    tester,
  ) async {
    useWideScreen(tester);
    final world = PhoneWorld();
    await world.open(tester, '/circles/circle-1');

    expect(
      find.byKey(const ValueKey('circle-thread-post-conv-1')),
      findsNothing,
    );
    final forumRow = find.byKey(const ValueKey('circle-channel-row-ch-help'));
    expect(
      find.descendant(
        of: forumRow,
        matching: find.byKey(const ValueKey('channel-unread-pill')),
      ),
      findsOneWidget,
    );
    await world.close(tester);
  });

  testWidgets('new posts are created with tags and then opened', (
    tester,
  ) async {
    final world = PhoneWorld();
    world.imagePicker.nextImage = ChatImageUpload(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      fileName: 'sunrise.png',
      mimeType: 'image/png',
    );
    await openForum(tester, world: world);

    await tester.tap(find.byKey(const ValueKey('forum-new-post')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('forum-post-submit')));
    await settle(tester);
    expect(find.text('Give your post a title.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('forum-post-title-field')),
      'Sunrise spots',
    );
    await tester.tap(find.byKey(const ValueKey('forum-post-submit')));
    await settle(tester);
    expect(find.text('Write something or add an image.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('forum-post-body-field')),
      'Where do you go?',
    );
    await tester.tap(find.byKey(const ValueKey('forum-tag-choice-tag-trip')));
    await tester.tap(find.byKey(const ValueKey('forum-tag-choice-tag-q')));
    await tester.tap(find.byKey(const ValueKey('forum-post-add-image')));
    await settle(tester);
    expect(find.byKey(const ValueKey('forum-post-image')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('forum-post-submit')));
    await tester.tap(find.byKey(const ValueKey('forum-post-submit')));
    await settle(tester);

    final created = world.circles.createdForumPosts.single;
    expect(created.title, 'Sunrise spots');
    expect(created.body, 'Where do you go?');
    // In the forum's tag order.
    expect(created.tagIds, ['tag-q', 'tag-trip']);
    expect(created.hasImage, isTrue);
    expect(world.circles.forumCalls.single, 'upload conv-help sunrise.png');
    // The new post opens.
    expect(find.byKey(const ValueKey('forum-post-list')), findsNothing);
    expect(find.widgetWithText(AppBar, 'Sunrise spots'), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('new posts mention members picked from the forum', (
    tester,
  ) async {
    final world = await openForum(tester);

    await tester.tap(find.byKey(const ValueKey('forum-new-post')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('forum-post-title-field')),
      'Tripod advice',
    );
    final body = find.byKey(const ValueKey('forum-post-body-field'));
    await tester.enterText(body, 'Thanks @gra');
    await settle(tester);
    expect(
      find.byKey(const ValueKey('forum-post-mention-candidates')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('mention-candidate-user-3')));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('forum-post-mention-candidates')),
      findsNothing,
    );
    final field = tester.widget<TextField>(body);
    expect(field.controller!.text, 'Thanks @grace ');
    await tester.enterText(body, 'Thanks @grace for the tips');
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('forum-post-submit')));
    await tester.tap(find.byKey(const ValueKey('forum-post-submit')));
    await settle(tester);

    final mention = world.circles.createdForumPosts.single.mentions.single;
    expect(mention.userId, 'user-3');
    expect(mention.displayName, 'Amazing Grace');
    expect((mention.start, mention.end), (7, 13));
    await world.close(tester);
  });

  Future<PhoneWorld> openLongPost(
    WidgetTester tester, {
    String? lastReadMessageId,
  }) async {
    final world = PhoneWorld();
    world.chats
      ..messages = [
        forumPostMessages().first,
        for (var index = 0; index < 30; index++)
          phoneMessage(
            'reply-$index',
            index.isEven ? bart : linus,
            'Reply number $index with a few words so it wraps a little.',
            minutesAgo: 200 - index,
            conversationId: 'post-conv-1',
          ),
      ]
      ..readMarkers = [
        if (lastReadMessageId != null)
          ConversationReadMarker(
            userId: 'user-1',
            lastReadMessageId: lastReadMessageId,
          ),
      ];
    await world.open(
      tester,
      '/circles/circle-1/channels/post-conv-1',
      extra: const ChatThreadRouteExtra(
        title: forumPostTitle,
        type: ConversationType.thread,
        circleId: 'circle-1',
      ),
    );
    return world;
  }

  testWidgets('forum posts open at the opening post', (tester) async {
    final world = await openLongPost(tester, lastReadMessageId: 'reply-29');

    expectFullyVisible(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('forum-opening-post')),
        matching: find.text(forumPostTitle),
      ),
    );
    expect(
      find.text(
        'Reply number 29 with a few words so it wraps a little.',
        findRichText: true,
      ),
      findsNothing,
    );
    // Everything was read: nothing to jump to.
    expect(
      find.byKey(const ValueKey('forum-jump-to-new-replies')),
      findsNothing,
    );
    await world.close(tester);
  });

  testWidgets('unread replies offer a jump instead of scrolling there', (
    tester,
  ) async {
    final world = await openLongPost(tester, lastReadMessageId: 'reply-24');

    expectFullyVisible(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('forum-opening-post')),
        matching: find.text(forumPostTitle),
      ),
    );
    final jump = find.byKey(const ValueKey('forum-jump-to-new-replies'));
    expect(jump, findsOneWidget);
    expect(find.text('Jump to new replies'), findsOneWidget);

    await tester.tap(jump);
    // The jump looks for the reply a screen at a time, one per frame.
    for (var round = 0; round < 4; round++) {
      await settle(tester);
    }
    expect(
      find.text(
        'Reply number 25 with a few words so it wraps a little.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('NEW'), findsOneWidget);
    expect(jump, findsNothing);
    await world.close(tester);
  });

  testWidgets('read-only forums offer no new post', (tester) async {
    final world = PhoneWorld();
    world.circles.detail = circleDetailWith(
      channelId: 'ch-help',
      permissions: CirclePermission.viewChannel.bit,
    );
    await openForum(tester, world: world);

    expect(find.byKey(const ValueKey('forum-new-post')), findsNothing);
    expect(find.text('You cannot post in this forum.'), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('scrolling loads older posts', (tester) async {
    final world = PhoneWorld();
    world.circles.forumPosts = [
      for (var index = 0; index < 40; index++)
        ForumPost(
          id: 'p$index',
          conversationId: 'p$index-conv',
          channelId: 'ch-help',
          title: 'Post number $index',
          createdAt: minutesAgo(index * 10),
          lastActivityAt: minutesAgo(index * 10),
        ),
    ];
    await openForum(tester, world: world);

    expect(world.circles.forumListCalls, hasLength(1));
    await tester.scrollUntilVisible(
      find.text('Post number 39'),
      400,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('forum-post-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await settle(tester);
    expect(world.circles.forumListCalls.length, greaterThanOrEqualTo(2));
    expect(world.circles.forumListCalls[1].beforeId, 'p24');
    await world.close(tester);
  });

  testWidgets('post options pin, tag and archive', (tester) async {
    final world = await openForum(tester);

    final card = find.byKey(const ValueKey('forum-post-post-2'));
    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('Post options')),
    );
    await settle(tester);
    await tester.tap(find.text('Pin post'));
    await settle(tester);
    expect(world.circles.forumCalls, ['pin post-2 true']);

    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('Post options')),
    );
    await settle(tester);
    await tester.tap(find.text('Edit tags'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('forum-tag-choice-tag-solved')));
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(world.circles.forumCalls.last, 'tags post-2 tag-trip,tag-solved');

    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('Post options')),
    );
    await settle(tester);
    await tester.tap(find.text('Archive post'));
    await settle(tester);
    expect(world.chats.archiveCalls.last, ('post-2', true));
    await world.close(tester);
  });

  testWidgets('forum posts open full screen with the opening post', (
    tester,
  ) async {
    final world = PhoneWorld();
    world.chats.messages = forumPostMessages();
    await world.open(
      tester,
      '/circles/circle-1/channels/post-conv-1',
      extra: const ChatThreadRouteExtra(
        title: forumPostTitle,
        type: ConversationType.thread,
        circleId: 'circle-1',
      ),
    );

    expect(find.byKey(const ValueKey('forum-opening-post')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('forum-opening-post')),
        matching: find.text(forumPostTitle),
      ),
      findsOneWidget,
    );
    expect(find.text('2 replies'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Archive thread'), findsNothing);
    await world.close(tester);
  });

  testWidgets('forum tags are managed in channel settings', (tester) async {
    final world = await openForum(tester);

    await tester.tap(find.byTooltip('Channel settings'));
    await settle(tester);
    expect(find.text('Forum tags'), findsOneWidget);
    expect(find.text('Slowmode'), findsNothing);

    final gear = find.byKey(const ValueKey('forum-tag-tag-gear'));
    await tester.tap(
      find.descendant(of: gear, matching: find.byTooltip('Edit tag')),
    );
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('forum-tag-name-field')),
      'Equipment',
    );
    // The dialog's Save comes after the overview form's.
    await tester.tap(find.widgetWithText(WeCordButton, 'Save').last);
    await settle(tester);
    expect(world.circles.forumCalls.last, 'update tag tag-gear Equipment -');

    await tester.tap(
      find.descendant(of: gear, matching: find.byTooltip('Delete tag')),
    );
    await settle(tester);
    await tester.tap(find.widgetWithText(WeCordButton, 'Delete'));
    await settle(tester);
    expect(world.circles.forumCalls.last, 'delete tag tag-gear');

    await scrollIntoView(tester, find.byKey(const ValueKey('forum-add-tag')));
    await tester.tap(find.byKey(const ValueKey('forum-add-tag')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('forum-tag-name-field')),
      ' Beta ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('forum-tag-emoji-field')),
      '🧪',
    );
    await tester.tap(find.widgetWithText(WeCordButton, 'Add'));
    await settle(tester);
    expect(world.circles.forumCalls.last, 'create tag ch-help Beta 🧪');

    await world.close(tester);
  });

  testWidgets('the create channel sheet makes forums', (tester) async {
    final world = PhoneWorld();
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip('Circle menu'));
    await settle(tester);
    await tester.tap(find.text('Create channel'));
    await settle(tester);

    // Text, voice and forum channels can be created.
    expect(find.text('Voice'), findsOneWidget);
    await tester.tap(find.text('Forum'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(WeCordTextField, 'Channel name'),
      'qa',
    );
    await tester.tap(find.widgetWithText(WeCordButton, 'Create'));
    await settle(tester);

    expect(world.circles.createdChannelName, 'qa');
    expect(world.circles.createdChannelKind, CircleChannelKind.forum);
    await world.close(tester);
  });
}
