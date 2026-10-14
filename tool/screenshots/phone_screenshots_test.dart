// Renders the main screens at 390x844 with real fonts and writes PNGs, for
// eyeballing the phone layout. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/phone_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=/some/output/dir
//
// Without PHONE_SCREENS_DIR the PNGs go to build/phone-screens.
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/voice.dart';

import '../../test/features/voice/voice_fakes.dart';
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
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Pinned messages'));
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

  screen('14-home', (tester, world) async {
    await world.open(tester, '/home');
  });

  screen('14b-messages', (tester, world) async {
    await world.open(tester, '/chats');
  });

  screen('14c-notifications', (tester, world) async {
    await world.open(tester, '/notifications');
  });

  screen('14d-add-circle', (tester, world) async {
    await world.open(tester, '/home');
    await tester.tap(find.byKey(const ValueKey('circle-rail-add')));
  });

  // The desktop layout, for comparison.
  const desktop = PhoneViewport(
    name: 'desktop',
    size: Size(1280, 800),
    devicePixelRatio: 1,
  );

  screen('w1-home', viewport: desktop, (tester, world) async {
    await world.open(tester, '/home');
  });

  screen('w2-direct-message', viewport: desktop, (tester, world) async {
    await world.open(tester, '/chats/dm-1');
  });

  screen('w3-circle', viewport: desktop, (tester, world) async {
    await world.open(tester, '/circles/circle-1');
  });

  screen('w4-notifications', viewport: desktop, (tester, world) async {
    await world.open(tester, '/notifications');
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

  // Decodes the emoji and sticker images on screen; decoding needs real
  // async work, which pumping alone does not do.
  Future<void> loadImages(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = element.widget as Image;
        await precacheImage(image.image, element);
      }
    });
    await settle(tester);
  }

  Future<void> openEmojiChannel(WidgetTester tester, PhoneWorld world) async {
    world.chats.messages = emojiMessages();
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-general',
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
    await loadImages(tester);
  }

  screen('34-custom-emoji-and-stickers', (tester, world) async {
    await openEmojiChannel(tester, world);
  });

  screen('34b-custom-emoji-older', (tester, world) async {
    await openEmojiChannel(tester, world);
    await scrollThreadUp(tester, 360);
    await loadImages(tester);
  });

  screen('34c-sticker-picker', (tester, world) async {
    await openEmojiChannel(tester, world);
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await settle(tester);
    await tester.tap(find.text('Send sticker'));
    await settle(tester);
    await loadImages(tester);
  });

  screen('34d-emoji-suggestions', (tester, world) async {
    await openEmojiChannel(tester, world);
    final composer = find.byKey(const ValueKey('chat-composer-field'));
    await tester.tap(composer);
    await tester.enterText(composer, 'Trip :pa');
    await showKeyboard(tester, notchedPhone);
    await loadImages(tester);
  });

  screen('34e-reaction-picker-custom', (tester, world) async {
    await openEmojiChannel(tester, world);
    await tester.longPress(
      find.byKey(
        const ValueKey('sticker-image-00000000-0000-4000-8000-000000000005'),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('More reactions'));
    await settle(tester);
    await loadImages(tester);
  });

  Future<void> openEmojiPage(WidgetTester tester, PhoneWorld world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip('Circle menu'));
    await settle(tester);
    await tester.ensureVisible(find.text('Emoji & stickers'));
    await settle(tester);
    await tester.tap(find.text('Emoji & stickers'));
    await settle(tester);
    await loadImages(tester);
  }

  screen('35-emoji-management', (tester, world) async {
    await openEmojiPage(tester, world);
  });

  screen('35b-sticker-management', (tester, world) async {
    await openEmojiPage(tester, world);
    await tester.tap(find.text('Stickers'));
    await settle(tester);
    await loadImages(tester);
  });

  screen('35c-emoji-management-small', (tester, world) async {
    await openEmojiPage(tester, world);
  }, viewport: smallPhone);

  void withVoice(PhoneWorld world, {bool remotes = true}) {
    world.circles.detail = circleDetailWithVoice();
    world.voice.states['circle-1'] = [
      voiceMember(
        userId: bart.id,
        name: bart.displayName,
        nickname: 'Bart the Bold',
        roleColor: 0x3498DB,
        selfMute: true,
      ),
      voiceMember(
        userId: grace.id,
        name: grace.displayName,
        roleColor: 0xE67E22,
        video: true,
        screen: true,
      ),
      voiceMember(userId: linus.id, name: 'Linus', selfDeaf: true),
    ];
    if (remotes) {
      world.voiceCalls.prepare = (call) {
        call.remotes = [
          VoiceCallParticipant(userId: bart.id, name: 'Bart the Bold'),
          VoiceCallParticipant(
            userId: grace.id,
            name: grace.displayName,
            isSpeaking: true,
            microphoneEnabled: true,
            cameraEnabled: true,
            cameraView: (context) => const ColoredBox(
              color: Color(0xFF35506B),
              child: Center(
                child: Icon(Icons.person, size: 64, color: Colors.white54),
              ),
            ),
            screenShareEnabled: true,
            screenView: (context) => const ColoredBox(
              color: Color(0xFF1E1F22),
              child: Center(
                child: Text(
                  'Trip slides',
                  style: TextStyle(color: Colors.white70, fontSize: 24),
                ),
              ),
            ),
          ),
          VoiceCallParticipant(userId: linus.id, name: 'Linus'),
        ];
      };
    }
  }

  Future<void> scrollToLounge(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await settle(tester);
  }

  screen('36-voice-channel-members', (tester, world) async {
    withVoice(world);
    await world.open(tester, '/circles/circle-1');
    await scrollToLounge(tester);
  });

  screen('36b-voice-call', (tester, world) async {
    withVoice(world);
    await world.open(tester, '/circles/circle-1');
    await scrollToLounge(tester);
    await tester.tap(
      find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('voice-control-mic')));
  });

  screen('36c-voice-panel-in-chats', (tester, world) async {
    withVoice(world);
    await world.open(tester, '/circles/circle-1');
    await scrollToLounge(tester);
    await tester.tap(
      find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
    );
    await settle(tester);
    world.router.go(ChatsScreen.path);
  });

  screen('36d-voice-not-configured', (tester, world) async {
    withVoice(world, remotes: false);
    world.voice.tokenError = const VoiceNotConfiguredException();
    await world.open(tester, '/circles/circle-1');
    await scrollToLounge(tester);
    await tester.tap(
      find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
    );
  });

  screen('36e-voice-before-joining', (tester, world) async {
    withVoice(world, remotes: false);
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-lounge',
      extra: const ChatThreadRouteExtra(
        title: 'Lounge',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
  });

  screen('36f-create-voice-channel', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip('Circle menu'));
    await settle(tester);
    await tester.tap(find.text('Create channel'));
    await settle(tester);
    await tester.tap(find.text('Voice'));
  });

  screen('36g-voice-call-small', (tester, world) async {
    withVoice(world);
    await world.open(tester, '/circles/circle-1');
    await scrollToLounge(tester);
    await tester.tap(
      find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('voice-control-camera')));
  }, viewport: smallPhone);

  DirectCall bartCall({bool ringing = false}) => DirectCall(
    callId: 'call-1',
    conversationId: 'dm-1',
    startedBy: bart.id,
    createdAt: DateTime.now().toUtc(),
    ringing: ringing,
    participants: [
      DirectCallParticipant(
        userId: bart.id,
        username: bart.username,
        displayName: bart.displayName,
      ),
    ],
  );

  screen('37-direct-call', (tester, world) async {
    world.voice.calls = [bartCall()];
    world.voiceCalls.prepare = (call) {
      call.remotes = [
        VoiceCallParticipant(
          userId: bart.id,
          name: bart.displayName,
          isSpeaking: true,
          microphoneEnabled: true,
        ),
      ];
    };
    await openThread(tester, world);
    await tester.tap(find.byTooltip('Start voice call'));
  });

  screen('37b-direct-call-join-bar', (tester, world) async {
    world.voice.calls = [bartCall()];
    await openThread(tester, world);
  });

  screen('37c-incoming-call', (tester, world) async {
    world.voice.calls = [bartCall(ringing: true)];
    await world.open(tester, ChatsScreen.path);
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
