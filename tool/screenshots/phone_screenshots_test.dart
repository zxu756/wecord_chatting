// Renders the main screens at 390x844 with real fonts and writes PNGs, for
// eyeballing the phone layout. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/phone_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=/some/output/dir
//
// Without PHONE_SCREENS_DIR the PNGs go to build/phone-screens.
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme.
// Add --dart-define=PHONE_SCREENS_ZH=true for the Chinese interface.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/auth/set_new_password_screen.dart';
import 'package:wecord/features/auth/two_factor_challenge_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/models/voice.dart';

import '../../test/features/voice/voice_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/phone-screens',
);

void main() {
  setUpAll(loadScreenshotFonts);

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

  screen('00-sign-in', (tester, world) async {
    world.auth.user = null;
    await pumpStandalone(tester, world, const AuthScreen());
  });

  screen('00b-create-account', (tester, world) async {
    world.auth.user = null;
    await pumpStandalone(tester, world, const AuthScreen());
    final toggle = find.byKey(const ValueKey('auth-toggle-mode'));
    await tester.ensureVisible(toggle);
    await settle(tester);
    await tester.tap(toggle);
    await settle(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
  });

  screen('00c-two-step-code', (tester, world) async {
    await pumpStandalone(tester, world, const TwoFactorChallengeScreen());
    FocusManager.instance.primaryFocus?.unfocus();
  });

  screen('00d-new-password', (tester, world) async {
    await pumpStandalone(tester, world, const SetNewPasswordScreen());
  });

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
    await tester.tap(_tooltip('More'));
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
    await tester.tap(_tooltip('More reactions'));
  });

  screen('06-composer-reply-keyboard', (tester, world) async {
    await openThread(tester, world);
    await tester.longPress(
      find.textContaining('Also this', findRichText: true).first,
    );
    await settle(tester);
    await tester.tap(_text('Reply'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextField, tr('Message')));
    await showKeyboard(tester, notchedPhone);
  });

  screen('07-pinned-sheet', (tester, world) async {
    await openThread(tester, world);
    await tester.tap(_tooltip('More'));
    await settle(tester);
    await tester.tap(_text('Pinned messages'));
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
    await tester.tap(_tooltip('Show member list'));
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
    await tester.tap(_text('Brewing ideas'));
  });

  screen('14-home', (tester, world) async {
    await world.open(tester, '/home');
  });

  screen('14b-home-small', (tester, world) async {
    await world.open(tester, '/home');
  }, viewport: smallPhone);

  screen('14b2-home-large-text', (tester, world) async {
    await world.open(tester, '/home');
  }, viewport: notchedPhoneLargeText);

  screen('14b3-home-scrolled', (tester, world) async {
    await world.open(tester, '/home');
    await tester.drag(
      find.byKey(const ValueKey('phone-messages-list')),
      const Offset(0, -600),
    );
  });

  screen('14b4-new-message-menu', (tester, world) async {
    await world.open(tester, '/home');
    await tester.tap(find.byKey(const ValueKey('phone-home-new')));
  });

  screen('14b5-home-drafts-and-statuses', (tester, world) async {
    world.presenceStatuses = {
      bart.id: PresenceStatus.doNotDisturb,
      grace.id: PresenceStatus.idle,
    };
    world.circles.onlineUserIds = {...world.circles.onlineUserIds, grace.id};
    world.draftStore.drafts[me.id] = {
      'group-1': const ComposerDraft(text: 'Bring the long lens and a tripod'),
    };
    await world.open(tester, '/home');
  });

  screen('08b-circle-mobile-home-small', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
  }, viewport: smallPhone);

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
    await tester.tap(_text('Feed'));
  });

  screen('16-circle-invite-sheet', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(_tooltip('Circle menu'));
    await settle(tester);
    await tester.tap(_text('Invite friends'));
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
    await tester.tap(_tooltip('Circle menu'));
    await settle(tester);
    await tester.tap(_text('Notification settings'));
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
    await tester.tap(_tooltip('Channel settings'));
    await settle(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
  });

  screen('25-create-forum-channel', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(_tooltip('Circle menu'));
    await settle(tester);
    await tester.tap(_text('Create channel'));
    await settle(tester);
    await tester.tap(_text('Forum'));
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
    await tester.tap(_text('Golden hour photo walk along the Embarcadero'));
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
    await tester.tap(_text('Elsewhere'));
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
    await tester.tap(_tooltip('Attach'));
    await settle(tester);
    await tester.tap(_text('Create poll'));
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
    await tester.tap(_tooltip('More'));
    await settle(tester);
    await tester.tap(_text('Channel settings'));
    await settle(tester);
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('webhook-create-button')),
    );
  });

  screen('33b-webhook-url', (tester, world) async {
    await openChannel(tester, world);
    await tester.tap(_tooltip('More'));
    await settle(tester);
    await tester.tap(_text('Channel settings'));
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
    await tester.tap(_text('Send sticker'));
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
    await tester.tap(_tooltip('More reactions'));
    await settle(tester);
    await loadImages(tester);
  });

  Future<void> openEmojiPage(WidgetTester tester, PhoneWorld world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(_tooltip('Circle menu'));
    await settle(tester);
    await tester.ensureVisible(_text('Emoji & stickers'));
    await settle(tester);
    await tester.tap(_text('Emoji & stickers'));
    await settle(tester);
    await loadImages(tester);
  }

  screen('35-emoji-management', (tester, world) async {
    await openEmojiPage(tester, world);
  });

  screen('35b-sticker-management', (tester, world) async {
    await openEmojiPage(tester, world);
    await tester.tap(_text('Stickers'));
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
    await tester.tap(_tooltip('Circle menu'));
    await settle(tester);
    await tester.tap(_text('Create channel'));
    await settle(tester);
    await tester.tap(_text('Voice'));
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
    await tester.tap(_tooltip('Start voice call'));
  });

  screen('37b-direct-call-join-bar', (tester, world) async {
    world.voice.calls = [bartCall()];
    await openThread(tester, world);
  });

  screen('37c-incoming-call', (tester, world) async {
    world.voice.calls = [bartCall(ringing: true)];
    await world.open(tester, ChatsScreen.path);
  });

  screen('38-file-messages', (tester, world) async {
    world.chats.messages = [
      phoneMessage(
        'f1',
        bart,
        '',
        minutesAgo: 30,
        type: MessageType.file,
        attachment: const {
          'kind': 'file',
          'bucket': 'chat-files',
          'path': 'dm-1/seed-yosemite-permit-application-2026.pdf',
          'name': 'Yosemite permit application 2026.pdf',
          'mime_type': 'application/pdf',
          'size': 1843200,
        },
      ),
      phoneMessage(
        'f2',
        me,
        '',
        minutesAgo: 20,
        type: MessageType.file,
        attachment: const {
          'kind': 'video',
          'bucket': 'chat-files',
          'path': 'dm-1/seed-trailhead.mp4',
          'name': 'trailhead.mp4',
          'mime_type': 'video/mp4',
          'size': 24117248,
        },
      ),
      phoneMessage(
        'f3',
        bart,
        '',
        minutesAgo: 10,
        type: MessageType.file,
        attachment: const {
          'kind': 'file',
          'bucket': 'chat-files',
          'path': 'dm-1/seed-gear.zip',
          'name': 'gear-list.zip',
          'mime_type': 'application/zip',
          'size': 88064,
        },
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
  });

  screen('31-slash-commands', (tester, world) async {
    await openChannel(tester, world);
    final composer = find.widgetWithText(TextField, tr('Message'));
    await tester.tap(composer);
    await tester.enterText(composer, '/');
    await showKeyboard(tester, notchedPhone);
  });

  // Redesign: inbox, friends, groups, search.
  const desktopWide = PhoneViewport(
    name: '1440x900',
    size: Size(1440, 900),
    devicePixelRatio: 1,
  );

  screen('r2-inbox', (tester, world) async {
    await world.open(tester, '/notifications');
  });

  screen('r2-inbox-mentions', (tester, world) async {
    await world.open(tester, '/notifications');
    await tester.tap(find.byKey(const ValueKey('inbox-filter-mentions')));
  });

  screen('r2-friends', (tester, world) async {
    await world.open(tester, '/contacts');
  });

  screen('r2-friends-search', (tester, world) async {
    await world.open(tester, '/contacts');
    await tester.enterText(find.byType(TextField).first, 'member');
  });

  screen('r2-new-group', (tester, world) async {
    await world.open(tester, '/contacts');
    await tester.tap(find.byKey(const ValueKey('contacts-new-group')));
  });

  screen('r2-group-details', (tester, world) async {
    await openThread(
      tester,
      world,
      id: 'group-1',
      title: groupDetail.title,
      type: ConversationType.group,
    );
    await tester.tap(_tooltip('Group details'));
  });

  screen('r2-search', (tester, world) async {
    await world.open(tester, '/search/messages');
    await tester.enterText(find.byType(TextField), 'release');
    await tester.pump(const Duration(milliseconds: 500));
  });

  screen('r2-w-inbox', viewport: desktopWide, (tester, world) async {
    await world.open(tester, '/notifications');
  });

  screen('r2-w-friends', viewport: desktopWide, (tester, world) async {
    await world.open(tester, '/contacts');
  });
  // Redesign: settings and profile.
  Future<void> openSettingsWindow(
    WidgetTester tester,
    PhoneWorld world, [
    String? section,
  ]) async {
    await world.open(tester, '/me');
    await settle(tester);
    if (section != null) {
      await tester.tap(find.byKey(ValueKey('settings-nav-$section')));
    }
  }

  void desktopScreen(
    String name,
    Future<void> Function(WidgetTester tester, PhoneWorld world) open,
  ) {
    testWidgets(name, (tester) async {
      // Desktop platform, so keyboard-only parts (shortcuts) show.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        usePhoneViewport(tester, desktopWide);
        final world = PhoneWorld();
        await open(tester, world);
        await shoot(tester, name);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  screen('r1-settings', (tester, world) async {
    await world.open(tester, '/me');
  });

  screen('r1-settings-scrolled', (tester, world) async {
    await world.open(tester, '/me');
    await tester.drag(
      find.byKey(const ValueKey('settings-page-list')),
      const Offset(0, -700),
    );
  });

  screen('r1-settings-bottom', (tester, world) async {
    await world.open(tester, '/me');
    await tester.drag(
      find.byKey(const ValueKey('settings-page-list')),
      const Offset(0, -3000),
    );
  });

  screen('r1-profile-edit', (tester, world) async {
    await world.open(tester, '/me');
    await tester.tap(find.byKey(const ValueKey('settings-account-card')));
  });

  screen('r1-status-sheet', (tester, world) async {
    await world.open(tester, '/me');
    await tester.tap(find.byKey(const ValueKey('presence-status-tile')));
  });

  screen('r1-custom-status-sheet', (tester, world) async {
    await world.open(tester, '/me');
    await tester.tap(_text('Brewing ideas'));
  });

  screen('r1-language-sheet', (tester, world) async {
    await world.open(tester, '/me');
    await tester.tap(find.byKey(const ValueKey('app-language-row')));
  });

  screen('r1-two-factor', (tester, world) async {
    await world.open(tester, '/me');
    final tile = find.byKey(const ValueKey('two-factor-settings-tile'));
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await tester.tap(tile);
  });

  screen('r1-profile-page', (tester, world) async {
    await world.open(tester, '/profile/user-2');
  });

  screen('r1-profile-sheet', (tester, world) async {
    await world.open(tester, '/contacts');
    showUserProfileSheet(tester.element(find.byType(Scaffold).first), 'user-2');
  });

  screen('r1-profile-more', (tester, world) async {
    await world.open(tester, '/profile/user-2');
    await tester.tap(_tooltip('More'));
  });

  desktopScreen('r1-w-settings', (tester, world) async {
    await openSettingsWindow(tester, world);
  });

  desktopScreen('r1-w-settings-profile', (tester, world) async {
    await openSettingsWindow(tester, world, 'profile');
  });

  desktopScreen('r1-w-settings-privacy', (tester, world) async {
    await openSettingsWindow(tester, world, 'privacy');
  });

  desktopScreen('r1-w-settings-notifications', (tester, world) async {
    await openSettingsWindow(tester, world, 'notifications');
  });

  desktopScreen('r1-w-settings-shortcuts', (tester, world) async {
    await openSettingsWindow(tester, world, 'shortcuts');
  });

  desktopScreen('r1-w-settings-language', (tester, world) async {
    await openSettingsWindow(tester, world, 'language');
  });

  desktopScreen('r1-w-profile', (tester, world) async {
    await world.open(tester, '/profile/user-2');
  });
}

// With PHONE_SCREENS_ZH the app shows Chinese, so look the English labels
// up through tr() (data such as names and messages stays as it is).
Finder _text(String text) => find.text(tr(text));

Finder _tooltip(String message) => find.byTooltip(tr(message));
