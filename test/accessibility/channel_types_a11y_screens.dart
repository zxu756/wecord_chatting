// Media channels and Q&A channels (C9), for the accessibility guard
// (guidelines_test.dart) and the screenshot tools: the picture wall (with its
// tile menu and the empty wall), the new picture form, the Q&A list with its
// solved filter and marks, a question's page (the answer menu, the accepted
// answer), the channel sheet with the two new kinds, and the desktop circle,
// at large text, narrow and with Care mode on.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/circles/channel_types_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

const _galleryExtra = ChatThreadRouteExtra(
  title: 'photo-wall',
  type: ConversationType.channel,
  circleId: 'circle-1',
);
const _askExtra = ChatThreadRouteExtra(
  title: 'ask-the-group',
  type: ConversationType.channel,
  circleId: 'circle-1',
);
const _postExtra = ChatThreadRouteExtra(
  title: 'Why do my night photos come out so grainy?',
  type: ConversationType.thread,
  circleId: 'circle-1',
);

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

Future<QaRpc> _wall(
  WidgetTester tester,
  PhoneWorld world, {
  bool empty = false,
}) async {
  final qa = addChannelTypes(world);
  if (empty) {
    world.circles.forumPosts = [
      for (final post in world.circles.forumPosts)
        if (post.channelId != galleryChannelId) post,
    ];
  }
  await world.open(
    tester,
    '/circles/circle-1/channels/$galleryConversationId',
    extra: _galleryExtra,
  );
  return qa;
}

Future<QaRpc> _questions(
  WidgetTester tester,
  PhoneWorld world, {
  List<Map<String, dynamic>>? posts,
}) async {
  final qa = addChannelTypes(world, rpc: QaRpc(posts: posts));
  await world.open(
    tester,
    '/circles/circle-1/channels/$askConversationId',
    extra: _askExtra,
  );
  return qa;
}

Future<QaRpc> _post(
  WidgetTester tester,
  PhoneWorld world, {
  bool solved = false,
}) async {
  final qa = addChannelTypes(world);
  if (solved) {
    qa
      ..solved = true
      ..answerMessageId = askAnswerId;
  }
  await world.open(
    tester,
    '/circles/circle-1/channels/$askPostConversationId',
    extra: _postExtra,
  );
  return qa;
}

Future<void> _tileMenu(WidgetTester tester, PhoneWorld world) async {
  await _wall(tester, world);
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('media-post-pic-1')),
      matching: find.byKey(const ValueKey('media-wall-options')),
    ),
  );
  await settle(tester);
}

Future<void> _newPicture(
  WidgetTester tester,
  PhoneWorld world, {
  bool describe = true,
}) async {
  world.imagePicker.nextImage = ChatImageUpload(
    bytes: Uint8List.fromList(const [1, 2, 3]),
    fileName: 'kite.png',
    mimeType: 'image/png',
  );
  await _wall(tester, world);
  await tester.tap(find.byKey(const ValueKey('forum-new-post')));
  await settle(tester);
  await tester.enterText(
    find.byKey(const ValueKey('forum-post-title-field')),
    'Kite day at the pier',
  );
  await tester.ensureVisible(
    find.byKey(const ValueKey('forum-post-add-image')),
  );
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('forum-post-add-image')));
  await settle(tester);
  if (describe) {
    await tester.ensureVisible(
      find.byKey(const ValueKey('forum-post-image-alt-field')),
    );
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('forum-post-image-alt-field')),
      'A red kite over the pier',
    );
  }
  await tester.pump();
}

Future<void> _questionForm(WidgetTester tester, PhoneWorld world) async {
  await _questions(tester, world);
  await tester.tap(find.byKey(const ValueKey('forum-new-post')));
  await settle(tester);
}

Future<void> _answerMenu(WidgetTester tester, PhoneWorld world) async {
  await _post(tester, world);
  await tester.longPress(find.textContaining('Try ISO 3200'));
  await settle(tester);
}

Future<void> _createSheet(WidgetTester tester, PhoneWorld world) async {
  addChannelTypes(world);
  await world.open(tester, '/circles/circle-1');
  await tester.tap(find.byTooltip(tr('Circle menu')));
  await settle(tester);
  await tester.ensureVisible(find.text(tr('Create channel')));
  await settle(tester);
  await tester.tap(find.text(tr('Create channel')));
  await settle(tester);
}

final channelTypesA11yScreens = <A11yScreen>[
  A11yScreen('media-wall', (tester, world) async {
    await _wall(tester, world);
  }),
  A11yScreen('media-wall-large-text', (tester, world) async {
    await _wall(tester, world);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('media-wall-care-mode', (tester, world) async {
    _care(world);
    await _wall(tester, world);
  }),
  A11yScreen('media-wall-narrow', (tester, world) async {
    await _wall(tester, world);
  }, viewport: smallPhone),
  A11yScreen('media-wall-empty', (tester, world) async {
    await _wall(tester, world, empty: true);
  }),
  A11yScreen('media-wall-tile-menu', _tileMenu),
  A11yScreen('media-new-picture', _newPicture),
  A11yScreen(
    'media-new-picture-large-text',
    _newPicture,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'media-new-picture-narrow',
    (tester, world) => _newPicture(tester, world, describe: false),
    viewport: smallPhone,
  ),
  A11yScreen('qa-list', (tester, world) async {
    await _questions(tester, world);
  }),
  A11yScreen('qa-list-large-text', (tester, world) async {
    await _questions(tester, world);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('qa-list-care-mode', (tester, world) async {
    _care(world);
    await _questions(tester, world);
  }),
  A11yScreen('qa-list-narrow', (tester, world) async {
    await _questions(tester, world);
  }, viewport: smallPhone),
  A11yScreen('qa-list-solved', (tester, world) async {
    await _questions(tester, world);
    await tester.tap(find.byKey(const ValueKey('qa-status-solved')));
    await settle(tester);
  }),
  A11yScreen('qa-list-none-solved', (tester, world) async {
    await _questions(tester, world, posts: const []);
    await tester.tap(find.byKey(const ValueKey('qa-status-solved')));
    await settle(tester);
  }),
  A11yScreen('qa-new-question', _questionForm),
  A11yScreen(
    'qa-new-question-large-text',
    _questionForm,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('qa-post', (tester, world) async {
    await _post(tester, world);
  }),
  A11yScreen('qa-post-accepted', (tester, world) async {
    await _post(tester, world, solved: true);
  }),
  A11yScreen('qa-post-accepted-large-text', (tester, world) async {
    await _post(tester, world, solved: true);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('qa-post-accepted-narrow', (tester, world) async {
    await _post(tester, world, solved: true);
  }, viewport: smallPhone),
  A11yScreen('qa-post-accepted-care-mode', (tester, world) async {
    _care(world);
    await _post(tester, world, solved: true);
  }),
  A11yScreen('qa-post-answer-menu', _answerMenu),
  A11yScreen('qa-create-channel-kinds', _createSheet),
  A11yScreen(
    'qa-create-channel-kinds-large-text',
    _createSheet,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'qa-create-channel-kinds-narrow',
    _createSheet,
    viewport: smallPhone,
  ),
  A11yScreen(
    'desktop-media-wall',
    (tester, world) async {
      addChannelTypes(world);
      await world.open(tester, '/circles/circle-1');
      await tester.tap(
        find.byKey(const ValueKey('circle-channel-row-$galleryChannelId')),
      );
      await settle(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-qa-list',
    (tester, world) async {
      addChannelTypes(world);
      await world.open(tester, '/circles/circle-1');
      await tester.tap(
        find.byKey(const ValueKey('circle-channel-row-$askChannelId')),
      );
      await settle(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-qa-post',
    (tester, world) async {
      addChannelTypes(world);
      await world.open(tester, '/circles/circle-1');
      await tester.tap(
        find.byKey(const ValueKey('circle-channel-row-$askChannelId')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('forum-post-$askPostId')));
      await settle(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
