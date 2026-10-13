// Renders the main screens at 390x844 with real fonts and writes PNGs, for
// eyeballing the phone layout. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/phone_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=/some/output/dir
//
// Without PHONE_SCREENS_DIR the PNGs go to build/phone-screens.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../test/mobile/phone_test_support.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/phone-screens',
);

void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    await settle(tester);
    // The root render view paints the whole screen, sheets and dialogs
    // included, already scaled to physical pixels.
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

  void screen(
    String name,
    Future<void> Function(WidgetTester tester, PhoneWorld world) open, {
    PhoneViewport viewport = notchedPhone,
  }) {
    testWidgets(name, (tester) async {
      usePhoneViewport(tester, viewport);
      final world = PhoneWorld();
      await open(tester, world);
      await shoot(tester, name);
    });
  }

  Future<void> openThread(
    WidgetTester tester,
    PhoneWorld world, {
    String id = 'dm-1',
    String? title,
    ConversationType type = ConversationType.direct,
    bool withThread = false,
  }) async {
    world.chats.messages = richMessages(withThread: withThread);
    await world.open(
      tester,
      '${ChatsScreen.path}/$id',
      extra: ChatThreadRouteExtra(title: title ?? bart.displayName, type: type),
    );
  }

  Future<void> openChannel(
    WidgetTester tester,
    PhoneWorld world, {
    String conversationId = 'conv-general',
    String title = '# general',
    ConversationType type = ConversationType.channel,
  }) async {
    world.chats.messages = richMessages(withThread: true);
    await world.open(
      tester,
      '/circles/circle-1/channels/$conversationId',
      extra: ChatThreadRouteExtra(
        title: title,
        type: type,
        circleId: 'circle-1',
      ),
    );
  }

  Future<void> scrollThreadUp(WidgetTester tester, double distance) async {
    await tester.drag(
      find.byKey(const ValueKey('chat-message-list')),
      Offset(0, distance),
    );
    await settle(tester);
  }

  screen('01-chats-list', (tester, world) async {
    await world.open(tester, ChatsScreen.path);
  });

  screen('01b-chats-list-small', (tester, world) async {
    await world.open(tester, ChatsScreen.path);
  }, viewport: smallPhone);

  screen('02-direct-thread', (tester, world) async {
    await openThread(tester, world);
  });

  screen('02b-direct-thread-reactions', (tester, world) async {
    await openThread(tester, world);
    await scrollThreadUp(tester, 520);
  });

  screen('02c-direct-thread-more-menu', (tester, world) async {
    await openThread(tester, world);
    await tester.tap(find.byTooltip('More'));
  });

  screen('02d-direct-thread-small-large-text', (tester, world) async {
    await openThread(tester, world);
    await scrollThreadUp(tester, 300);
  }, viewport: smallPhone);

  screen('03-group-thread', (tester, world) async {
    await openThread(
      tester,
      world,
      id: 'group-1',
      title: groupDetail.title,
      type: ConversationType.group,
      withThread: true,
    );
    await scrollThreadUp(tester, 420);
  });

  screen('04-long-press-menu', (tester, world) async {
    await openThread(tester, world);
    await tester.longPress(
      find.textContaining('Also this', findRichText: true).first,
    );
  });

  screen('05-emoji-picker', (tester, world) async {
    await openThread(tester, world);
    await tester.longPress(
      find.textContaining('Also this', findRichText: true).first,
    );
    await settle(tester);
    await tester.tap(find.byTooltip('More reactions'));
  });

  screen('06-composer-reply-keyboard', (tester, world) async {
    await openThread(tester, world);
    await tester.longPress(
      find.textContaining('Also this', findRichText: true).first,
    );
    await settle(tester);
    await tester.tap(find.text('Reply'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextField, 'Message'));
    await showKeyboard(tester, notchedPhone);
  });

  screen('07-pinned-sheet', (tester, world) async {
    await openThread(tester, world);
    await tester.tap(find.byTooltip('Pinned messages'));
  });

  screen('08-circle-mobile-home', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
  });

  screen('09-circle-channel-thread', (tester, world) async {
    await openChannel(tester, world);
    await scrollThreadUp(tester, 420);
  });

  screen('10-members-drawer', (tester, world) async {
    await openChannel(tester, world);
    await tester.tap(find.byTooltip('Show member list'));
  });

  screen('11-circle-thread', (tester, world) async {
    await openChannel(
      tester,
      world,
      conversationId: 'thread-conv-1',
      title: 'Planning the extremely long weekend trip to Yosemite Valley',
      type: ConversationType.thread,
    );
  });

  screen('12-me-settings', (tester, world) async {
    await world.open(tester, '/me');
  });

  screen('13-status-sheet', (tester, world) async {
    await world.open(tester, '/me');
    await tester.tap(find.text('Brewing ideas'));
  });

  screen('14-circles-list', (tester, world) async {
    await world.open(tester, '/circles');
  });

  screen('15-circle-feed', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.text('Feed'));
  });

  screen('16-circle-invite-sheet', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip('Circle menu'));
    await settle(tester);
    await tester.tap(find.text('Invite friends'));
  });

  screen('17-contacts', (tester, world) async {
    await world.open(tester, '/contacts');
  });

  screen('18-user-profile', (tester, world) async {
    await world.open(tester, '/profile/user-2');
  });

  screen('19-global-search', (tester, world) async {
    await world.open(tester, '/search/messages');
    await tester.enterText(find.byType(TextField), 'release');
    await tester.pump(const Duration(milliseconds: 500));
  });

  screen('20-notification-settings', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip('Circle menu'));
    await settle(tester);
    await tester.tap(find.text('Notification settings'));
  });

  screen('21-forum-posts', (tester, world) async {
    await openChannel(
      tester,
      world,
      conversationId: 'conv-help',
      title: 'help-and-questions',
    );
  });

  screen('21b-forum-posts-small', (tester, world) async {
    await openChannel(
      tester,
      world,
      conversationId: 'conv-help',
      title: 'help-and-questions',
    );
  }, viewport: smallPhone);

  screen('22-forum-new-post-keyboard', (tester, world) async {
    await openChannel(
      tester,
      world,
      conversationId: 'conv-help',
      title: 'help-and-questions',
    );
    await tester.tap(find.byKey(const ValueKey('forum-new-post')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('forum-post-title-field')),
      'Best sunrise spot near Tunnel View?',
    );
    await tester.tap(find.byKey(const ValueKey('forum-tag-choice-tag-q')));
    await tester.tap(find.byKey(const ValueKey('forum-post-body-field')));
    await showKeyboard(tester, notchedPhone);
  });

  screen('23-forum-post', (tester, world) async {
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
    world.chats.messages = forumPostMessages();
    await settle(tester);
  });

  screen('24-forum-settings', (tester, world) async {
    await openChannel(
      tester,
      world,
      conversationId: 'conv-help',
      title: 'help-and-questions',
    );
    await tester.tap(find.byTooltip('Channel settings'));
    await settle(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
  });

  screen('25-create-forum-channel', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip('Circle menu'));
    await settle(tester);
    await tester.tap(find.text('Create channel'));
    await settle(tester);
    await tester.tap(find.text('Forum'));
  });

  Future<void> openEvents(WidgetTester tester, PhoneWorld world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byKey(const ValueKey('circle-events-entry')));
    await settle(tester);
  }

  screen('26-circle-events', (tester, world) async {
    await openEvents(tester, world);
  });

  screen('26b-circle-events-small', (tester, world) async {
    await openEvents(tester, world);
  }, viewport: smallPhone);

  screen('27-circle-event-detail', (tester, world) async {
    await openEvents(tester, world);
    await tester.tap(find.text('Golden hour photo walk along the Embarcadero'));
  });

  screen('28-create-event-keyboard', (tester, world) async {
    await openEvents(tester, world);
    await tester.tap(find.byKey(const ValueKey('circle-events-create')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('event-title-field')),
      'Picnic in Dolores Park',
    );
    await showKeyboard(tester, notchedPhone);
  });

  screen('28b-create-event-elsewhere', (tester, world) async {
    await openEvents(tester, world);
    await tester.tap(find.byKey(const ValueKey('circle-events-create')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('event-title-field')),
      'Picnic in Dolores Park',
    );
    await tester.tap(find.text('Elsewhere'));
    await tester.tap(find.byKey(const ValueKey('event-end-switch')));
  });

  Future<void> openPolls(WidgetTester tester, PhoneWorld world) async {
    world.chats.messages = pollMessages();
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-general',
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
  }

  screen('29-poll-bubbles', (tester, world) async {
    await openPolls(tester, world);
    await scrollThreadUp(tester, 260);
  });

  screen('29b-poll-bubbles-small', (tester, world) async {
    await openPolls(tester, world);
  }, viewport: smallPhone);

  screen('30-poll-composer-keyboard', (tester, world) async {
    await openPolls(tester, world);
    await tester.tap(find.byTooltip('Attach'));
    await settle(tester);
    await tester.tap(find.text('Create poll'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('poll-question-field')),
      'Which day works best for the retro?',
    );
    await tester.enterText(
      find.byKey(const ValueKey('poll-option-field-0')),
      'Monday',
    );
    await showKeyboard(tester, notchedPhone);
  });

  screen('32-webhook-messages', (tester, world) async {
    world.chats.messages = webhookMessages();
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-general',
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
  });

  screen('33-channel-integrations', (tester, world) async {
    world.circles.webhooks = channelWebhooks();
    await openChannel(tester, world);
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Channel settings'));
    await settle(tester);
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('webhook-create-button')),
    );
  });

  screen('33b-webhook-url', (tester, world) async {
    await openChannel(tester, world);
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Channel settings'));
    await settle(tester);
    final create = find.byKey(const ValueKey('webhook-create-button'));
    await scrollIntoView(tester, create);
    await tester.tap(create);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('webhook-name-submit')));
  });

  screen('31-slash-commands', (tester, world) async {
    await openChannel(tester, world);
    final composer = find.widgetWithText(TextField, 'Message');
    await tester.tap(composer);
    await tester.enterText(composer, '/');
    await showKeyboard(tester, notchedPhone);
  });
}

/// Loads Roboto and the Material icons from the Flutter SDK, so text is not
/// drawn as boxes, plus the system emoji font where there is one.
Future<void> _loadFonts() async {
  final fonts = _materialFontsDir();
  final roboto = FontLoader('Roboto');
  for (final weight in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
    roboto.addFont(_fontData('${fonts.path}/Roboto-$weight.ttf'));
  }
  roboto.addFont(_fontData('${fonts.path}/Roboto-Italic.ttf'));
  await roboto.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(_fontData('${fonts.path}/MaterialIcons-Regular.otf'));
  await icons.load();

  // Code blocks ask for "monospace"; borrow a system mono font.
  const monoFont = '/System/Library/Fonts/Supplemental/Courier New.ttf';
  if (File(monoFont).existsSync()) {
    final mono = FontLoader('monospace')..addFont(_fontData(monoFont));
    await mono.load();
  }

  const emojiFont = '/System/Library/Fonts/Apple Color Emoji.ttc';
  if (File(emojiFont).existsSync()) {
    final emoji = FontLoader('Apple Color Emoji')
      ..addFont(_fontData(emojiFont));
    await emoji.load();
  }
}

Future<ByteData> _fontData(String path) async {
  final bytes = File(path).readAsBytesSync();
  return ByteData.sublistView(bytes);
}

Directory _materialFontsDir() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final dir = Directory('$flutterRoot/bin/cache/artifacts/material_fonts');
    if (dir.existsSync()) {
      return dir;
    }
  }
  // flutter_tester lives under bin/cache/artifacts/engine/<platform>/.
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.path != dir.parent.path) {
    final candidate = Directory('${dir.path}/material_fonts');
    if (candidate.existsSync()) {
      return candidate;
    }
    dir = dir.parent;
  }
  throw StateError('Could not find the Flutter SDK material fonts.');
}
