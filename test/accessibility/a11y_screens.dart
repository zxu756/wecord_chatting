// The main screens the accessibility guard and the accessibility
// screenshot tool (tool/screenshots/a11y_screenshots_test.dart) walk
// through: sign in, home, chat threads with their menus, circles, voice,
// settings, notifications, contacts, search, profile and discovery.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/later/reminders_repository.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/features/later/scheduled_messages_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/voice/call_links/call_links.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/features/search/message_search_controller.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';

import '../features/chats/emoji_fixtures.dart';
import '../features/circles/ai_guard_fakes.dart';
import '../features/ai/ai_fakes.dart';
import '../features/transcribe/transcribe_fakes.dart';
import '../features/discovery/discovery_fakes.dart';
import '../features/file_preview/file_preview_fakes.dart';
import '../features/later/later_fakes.dart';
import 'voice_chain_a11y_screens.dart';
import 'multi_select_a11y_screens.dart';
import 'photo_editor_a11y_screens.dart';
import 'location_a11y_screens.dart';
import 'qr_pat_a11y_screens.dart';
import 'moments_a11y_screens.dart';
import 'quiet_hours_a11y_screens.dart';
import 'chat_folders_a11y_screens.dart';
import 'chat_polish_a11y_screens.dart';
import 'privacy2_a11y_screens.dart';
import 'reports_legal_a11y_screens.dart';
import 'admin_a11y_screens.dart';
import 'agenda_a11y_screens.dart';
import 'edit_history_a11y_screens.dart';
import 'join_requests_a11y_screens.dart';
import 'read_status_a11y_screens.dart';
import 'auto_translate_a11y_screens.dart';
import 'stickers_a11y_screens.dart';
import 'insights_a11y_screens.dart';
import 'forms_a11y_screens.dart';
import 'admin_ops_a11y_screens.dart';
import 'ops_metrics_a11y_screens.dart';
import 'ai_assistant_a11y_screens.dart';
import 'onboarding_guide_a11y_screens.dart';
import 'digest_a11y_screens.dart';
import 'profile_extras_a11y_screens.dart';
import 'stories_a11y_screens.dart';
import 'mod_tools_a11y_screens.dart';
import 'urgent_a11y_screens.dart';
import 'captions_a11y_screens.dart';
import 'ai_ask_a11y_screens.dart';
import 'platforms_a11y_screens.dart';
import 'workspace_a11y_screens.dart';
import 'notes2_a11y_screens.dart';
import 'favorites2_a11y_screens.dart';
import 'public_circle_a11y_screens.dart';
import 'storage_a11y_screens.dart';
import 'moments2_a11y_screens.dart';
import 'guard2_a11y_screens.dart';
import 'app_lock_a11y_screens.dart';
import 'care_mode_a11y_screens.dart';
import 'developer_a11y_screens.dart';
import 'interactions_a11y_screens.dart';
import 'knowledge_base_a11y_screens.dart';
import 'member_honors_a11y_screens.dart';
import 'channel_types_a11y_screens.dart';
import 'events2_a11y_screens.dart';
import 'account_security_a11y_screens.dart';
import 'group_checkin_tabs_a11y_screens.dart';
import 'scheduled_calls_a11y_screens.dart';
import 'group_space_a11y_screens.dart';
import 'chat_privacy_a11y_screens.dart';
import '../features/voice/call_links_fakes.dart';
import '../features/wallpapers/wallpaper_fakes.dart';
import '../features/privacy/privacy_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'tasks2_a11y_screens.dart';

/// One screen to check: how to reach it and the screen it needs.
class A11yScreen {
  const A11yScreen(
    this.name,
    this.open, {
    this.viewport = notchedPhone,
    this.desktop = false,
  });

  final String name;
  final Future<void> Function(WidgetTester tester, PhoneWorld world) open;
  final PhoneViewport viewport;

  /// Laid out for a mouse and keyboard (macOS), not touch.
  final bool desktop;
}

const desktopViewport = PhoneViewport(
  name: '1280x800',
  size: Size(1280, 800),
  devicePixelRatio: 1,
);

/// The desktop window with the text at the largest size people set (2.0x):
/// sidebar rows must grow with it instead of clipping.
const desktopLargeTextViewport = PhoneViewport(
  name: '1280x800 at 2.0x text',
  size: Size(1280, 800),
  devicePixelRatio: 1,
  textScale: 2,
);

Future<void> _openThread(
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

Future<void> _openChannel(WidgetTester tester, PhoneWorld world) async {
  world.chats.messages = richMessages(withThread: true);
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

void _withVoice(PhoneWorld world) {
  world.circles.detail = circleDetailWithVoice();
  world.voiceCalls.prepare = (call) {
    call.remotes = [
      VoiceCallParticipant(userId: bart.id, name: 'Bart the Bold'),
      VoiceCallParticipant(
        userId: grace.id,
        name: grace.displayName,
        isSpeaking: true,
        microphoneEnabled: true,
      ),
    ];
  };
}

/// Joins the Lounge voice channel from the circle's page.
Future<void> _joinLounge(WidgetTester tester, PhoneWorld world) async {
  await world.open(tester, '/circles/circle-1');
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  // Clear of the floating user panel.
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('circle-channel-row-ch-lounge')));
  await settle(tester);
}

/// The screens, in the order of the main flows.
final a11yScreens = <A11yScreen>[
  A11yScreen('sign-in', (tester, world) async {
    world.auth.user = null;
    await pumpStandalone(tester, world, const AuthScreen());
  }),
  A11yScreen('home', (tester, world) async {
    await world.open(tester, '/home');
  }),
  A11yScreen('chats-list', (tester, world) async {
    await world.open(tester, ChatsScreen.path);
  }),
  A11yScreen('direct-thread', (tester, world) async {
    await _openThread(tester, world);
  }),
  A11yScreen('group-thread', (tester, world) async {
    await _openThread(
      tester,
      world,
      id: 'group-1',
      title: groupDetail.title,
      type: ConversationType.group,
      withThread: true,
    );
  }),
  A11yScreen('message-menu', (tester, world) async {
    await _openThread(tester, world);
    await tester.longPress(
      find.textContaining('Also this', findRichText: true).first,
    );
  }),
  A11yScreen('thread-more-menu', (tester, world) async {
    await _openThread(tester, world);
    await tester.tap(find.byTooltip(tr('More')));
  }),
  A11yScreen('circle-home', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
  }),
  A11yScreen('channel-thread', (tester, world) async {
    await _openChannel(tester, world);
  }),
  A11yScreen('voice-before-joining', (tester, world) async {
    _withVoice(world);
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-lounge',
      extra: const ChatThreadRouteExtra(
        title: 'Lounge',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
  }),
  A11yScreen('settings', (tester, world) async {
    await world.open(tester, '/me');
  }),
  A11yScreen('notifications', (tester, world) async {
    await world.open(tester, '/notifications');
  }),
  A11yScreen('contacts', (tester, world) async {
    await world.open(tester, '/contacts');
  }),
  A11yScreen('profile', (tester, world) async {
    await world.open(tester, '/profile/user-2');
  }),
  A11yScreen(
    'desktop-home',
    (tester, world) async {
      await world.open(tester, '/home');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-direct-thread',
    (tester, world) async {
      await world.open(tester, '/chats/dm-1');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-circle',
    (tester, world) async {
      await world.open(tester, '/circles/circle-1');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];

/// The desktop sidebars at 2.0x text, which the screenshot tool and the
/// guideline guard visit whatever text size they are run at.
final desktopLargeTextScreens = <A11yScreen>[
  A11yScreen(
    'desktop-home-2x-text',
    (tester, world) async {
      await world.open(tester, '/home');
    },
    viewport: desktopLargeTextViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-circle-2x-text',
    (tester, world) async {
      await world.open(tester, '/circles/circle-1');
    },
    viewport: desktopLargeTextViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-direct-thread-2x-text',
    (tester, world) async {
      await world.open(tester, '/chats/dm-1');
    },
    viewport: desktopLargeTextViewport,
    desktop: true,
  ),
];

// Screens that need a little more set up.

Future<Object?> _discoveryRpc(String name, Map<String, dynamic> params) async {
  switch (name) {
    case 'list_discoverable_circles':
      return [
        for (final (index, circle) in sampleDiscoverableCircles.indexed)
          discoverableJson(
            circle.id,
            name: circle.name,
            category: circle.category?.value ?? 'gaming',
            members: circle.memberCount,
            online: circle.onlineCount,
            tags: circle.tags,
            description: circle.description,
            isMember: index == 1,
          ),
      ];
  }
  throw StateError('Supabase must be initialized first.');
}

// The file viewer: a text file, a picture and a download still running.

PreviewFile _previewFile(String name, String mime) {
  return PreviewFile(
    bucket: 'chat-files',
    path: 'conversation-1/$name',
    name: name,
    mimeType: mime,
    size: 2048,
    messageId: 'message-$name',
    conversationId: 'conversation-1',
    senderName: 'Bart the Bold',
    sentAt: DateTime.utc(2026, 10, 14, 9, 30),
  );
}

/// Opens [file] in the viewer on top of the home screen, with [fetcher]
/// serving it.
Future<void> _openPreview(
  WidgetTester tester,
  PhoneWorld world,
  PreviewFile file,
  FakeFileFetcher fetcher,
) async {
  world.filePreview = filePreviewOverrides(fetcher: fetcher);
  await world.open(tester, '/home');
  final context = tester.element(find.byType(Scaffold).first);
  unawaited(openFilePreview(context, file: file));
  await settle(tester);
}

/// A [FakeFileFetcher] that "downloads" a real picture from disk.
class _PictureFetcher extends FakeFileFetcher {
  _PictureFetcher(this.path) : super(contents: const {});

  final String path;

  @override
  Future<String> download(
    PreviewFile file, {
    required Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async => path;
}

final moreA11yScreens = <A11yScreen>[
  A11yScreen('discovery', (tester, world) async {
    world.extraOverrides = [circleRpcProvider.overrideWithValue(_discoveryRpc)];
    await world.open(tester, '/discover');
  }),
  A11yScreen('message-search', (tester, world) async {
    await world.open(tester, GlobalMessageSearchScreen.path);
    await tester.enterText(
      find.byKey(const ValueKey('message-search-field')),
      'launch',
    );
    await tester.pump(MessageSearchController.debounce);
    await settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
  }),
  A11yScreen('emoji-picker', (tester, world) async {
    await _openThread(tester, world);
    await tester.longPress(
      find.textContaining('Also this', findRichText: true).first,
    );
    await settle(tester);
    await tester.tap(find.byTooltip(tr('More reactions')));
  }),
  A11yScreen('devices', (tester, world) async {
    world.extraOverrides = deviceOverrides();
    await world.open(tester, '/me');
    final tile = find.byKey(const ValueKey('devices-tile'));
    await scrollIntoView(tester, tile);
    await tester.tap(tile);
  }),
  A11yScreen('status-sheet', (tester, world) async {
    await world.open(tester, '/me');
    await tester.tap(find.byKey(const ValueKey('presence-status-tile')));
  }),
  A11yScreen('circle-menu', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip(tr('Circle menu')));
  }),
  A11yScreen('forum-posts', (tester, world) async {
    world.chats.messages = richMessages(withThread: true);
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-help',
      extra: const ChatThreadRouteExtra(
        title: 'help-and-questions',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
  }),
  A11yScreen('voice-call', (tester, world) async {
    _withVoice(world);
    world.circles.detail = circleDetailWithVoice();
    await world.open(tester, '/circles/circle-1');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(
      find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
    );
    await settle(tester);
  }),
  A11yScreen('file-preview-text', (tester, world) async {
    await _openPreview(
      tester,
      world,
      _previewFile('notes.txt', 'text/plain'),
      FakeFileFetcher(
        contents: {
          'conversation-1/notes.txt':
              'Trailhead moves to 8:30.\nBring water and a jacket.\n',
        },
      ),
    );
  }),
  A11yScreen('file-preview-picture', (tester, world) async {
    final directory = Directory.systemTemp.createTempSync('wecord_a11y_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final picture = File('${directory.path}/photo.png')
      ..writeAsBytesSync(partyParrotPng);
    await _openPreview(
      tester,
      world,
      _previewFile('photo.png', 'image/png'),
      _PictureFetcher(picture.path),
    );
    // Reading and decoding the file take real time.
    for (var round = 0; round < 6; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }),
  A11yScreen('file-preview-loading', (tester, world) async {
    await _openPreview(
      tester,
      world,
      _previewFile('big.txt', 'text/plain'),
      // The download never finishes: the progress state stays up.
      FakeFileFetcher(contents: {'conversation-1/big.txt': 'x'})
        ..gate = Completer<void>(),
    );
  }),
  A11yScreen('scheduled-messages', (tester, world) async {
    world.extraOverrides = [
      scheduledMessagesRepositoryProvider.overrideWithValue(
        FakeScheduledMessagesRepository([
          ScheduledMessage(
            id: 's1',
            conversationId: 'dm-1',
            body: 'Happy birthday, Bart!',
            sendAt: DateTime.now().add(const Duration(hours: 5)).toUtc(),
          ),
          ScheduledMessage(
            id: 's2',
            conversationId: 'dm-1',
            body: 'Standup notes',
            sendAt: DateTime.now().subtract(const Duration(minutes: 9)).toUtc(),
            status: ScheduledMessageStatus.failed,
            lastError: 'automod:Spam',
          ),
        ]),
      ),
    ];
    await _openThread(tester, world);
    await tester.tap(find.byKey(const ValueKey('scheduled-banner')));
    await settle(tester);
  }),
  A11yScreen('reminders', (tester, world) async {
    world.extraOverrides = [
      remindersRepositoryProvider.overrideWithValue(
        FakeRemindersRepository([
          MessageReminder(
            id: 'r1',
            conversationId: 'dm-1',
            messageId: 'm1',
            remindAt: DateTime.now().subtract(const Duration(minutes: 4)),
            senderName: 'Bart the Bold',
            body: 'Bring the tripod',
          ),
          MessageReminder(
            id: 'r2',
            conversationId: 'dm-1',
            remindAt: DateTime.now().add(const Duration(hours: 3)),
            senderName: 'Bart the Bold',
            body: 'Send Grace the photos',
            messageId: 'm2',
          ),
        ]),
      ),
    ];
    await world.open(tester, '/notifications');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('inbox-filter-reminders')));
    await settle(tester);
  }),
  A11yScreen('saved-messages', (tester, world) async {
    world.extraOverrides = [
      savedMessagesRepositoryProvider.overrideWithValue(
        FakeSavedMessagesRepository([
          SavedMessage(
            id: 'a',
            messageId: 'm1',
            conversationId: 'dm-1',
            savedAt: DateTime.now().subtract(const Duration(hours: 2)),
            senderName: 'Bart the Bold',
            body: 'Bring the tripod',
          ),
          SavedMessage(
            id: 'b',
            conversationId: 'dm-1',
            savedAt: DateTime.now().subtract(const Duration(days: 2)),
            available: false,
          ),
        ]),
      ),
    ];
    await world.open(tester, '/saved');
    await settle(tester);
  }),
  A11yScreen('call-link-sheet', (tester, world) async {
    _withVoice(world);
    final links = FakeCallLinksRepository();
    await links.create(
      const CallLinkTarget.channel('ch-lounge'),
      CallLinkExpiry.week,
    );
    world.extraOverrides = [
      callLinksRepositoryProvider.overrideWithValue(links),
    ];
    await _joinLounge(tester, world);
    await tester.tap(find.byKey(const ValueKey('voice-call-link-button')));
  }),
  A11yScreen('call-link-no-access', (tester, world) async {
    final links = FakeCallLinksRepository();
    links.resolutions['abcd2345efgh'] = const CallLinkResolution.problem(
      CallLinkProblem.noAccess,
    );
    world.extraOverrides = [
      callLinksRepositoryProvider.overrideWithValue(links),
    ];
    await world.open(tester, '/call/abcd2345efgh');
  }),
  A11yScreen(
    'desktop-settings',
    (tester, world) async {
      await world.open(tester, '/me');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-search',
    (tester, world) async {
      await world.open(tester, GlobalMessageSearchScreen.path);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('ai-rewrite-sheet', (tester, world) async {
    world.extraOverrides = _aiOverrides();
    await _openThread(tester, world);
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'helo wrld, how are u',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-ai-button')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ai-rewrite-fix')));
    await settle(tester);
  }),
  A11yScreen('ai-settings', (tester, world) async {
    world.extraOverrides = [
      ..._aiOverrides(),
      ...transcribeOverrides(FakeVoiceTranscriber()),
    ];
    await world.open(tester, '/me');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ai-enabled-switch')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }),
  A11yScreen('ai-translation', (tester, world) async {
    world.extraOverrides = _aiOverrides();
    await _openThread(tester, world);
    await tester.longPress(
      find.textContaining('Also this', findRichText: true).first,
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('message-translate')));
    await settle(tester);
  }),
  A11yScreen('voice-transcript', (tester, world) async {
    world.extraOverrides = transcribeOverrides(FakeVoiceTranscriber());
    await _openThread(tester, world);
    await tester.tap(find.byTooltip(tr('Transcribe')).first);
    await settle(tester);
  }),
  A11yScreen('voice-transcript-error', (tester, world) async {
    world.extraOverrides = transcribeOverrides(
      FakeVoiceTranscriber()
        ..error = const TranscribeException(TranscribeFailureKind.failed),
    );
    await _openThread(tester, world);
    await tester.tap(find.byTooltip(tr('Transcribe')).first);
    await settle(tester);
  }),
  A11yScreen('ai-guard-settings', (tester, world) async {
    world.extraOverrides = _aiGuardOverrides();
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip(tr('Circle menu')));
    await settle(tester);
    await tester.tap(find.text(tr('AI guard')));
    await settle(tester);
  }),
  A11yScreen('ai-guard-review', (tester, world) async {
    world.extraOverrides = _aiGuardOverrides();
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip(tr('Circle menu')));
    await settle(tester);
    await tester.tap(find.text(tr('Review')));
    await settle(tester);
  }),
  A11yScreen('ai-guard-author-state', (tester, world) async {
    world.extraOverrides = _aiGuardOverrides();
    world.chats.messages = [
      phoneMessage('g1', bart, 'Welcome to the circle!', minutesAgo: 30),
      phoneMessage(
        'g2',
        me,
        'Hi all, happy to join',
        minutesAgo: 3,
      ).copyWith(reviewState: MessageReviewState.held),
      phoneMessage(
        'g3',
        me,
        'Any events this week?',
        minutesAgo: 0,
      ).copyWith(reviewState: MessageReviewState.checking),
    ];
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-general',
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
  }),
  A11yScreen('ai-catch-up', (tester, world) async {
    world.extraOverrides = _aiOverrides();
    await _openThread(tester, world);
    await tester.tap(find.byTooltip(tr('More')));
    await settle(tester);
    await tester.tap(find.text(tr('Summarize')));
    await settle(tester);
  }),
  A11yScreen('wallpaper-picker', (tester, world) async {
    world.extraOverrides = _wallpaperOverrides(
      const WallpaperSettings(defaultWallpaper: ChatWallpaper.preset('dawn')),
    );
    await _openThread(tester, world);
    await tester.tap(find.byTooltip(tr('More')));
    await settle(tester);
    await tester.tap(find.text(tr('Wallpaper')));
    await settleWithImages(tester);
  }),
  A11yScreen('wallpaper-picker-photo', (tester, world) async {
    world.extraOverrides = _wallpaperOverrides(
      const WallpaperSettings(
        chats: {'dm-1': ChatWallpaper.photo(_wallpaperPhotoPath, blur: true)},
      ),
    );
    await _openThread(tester, world);
    await tester.tap(find.byTooltip(tr('More')));
    await settle(tester);
    await tester.tap(find.text(tr('Wallpaper')));
    await settleWithImages(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await settleWithImages(tester);
  }),
  A11yScreen('wallpaper-chat', (tester, world) async {
    world.extraOverrides = _wallpaperOverrides(
      const WallpaperSettings(defaultWallpaper: ChatWallpaper.preset('sage')),
    );
    await _openThread(tester, world);
    await settleWithImages(tester);
  }),
  A11yScreen('wallpaper-chat-photo', (tester, world) async {
    world.extraOverrides = _wallpaperOverrides(
      const WallpaperSettings(
        defaultWallpaper: ChatWallpaper.photo(_wallpaperPhotoPath),
      ),
    );
    await _openThread(tester, world);
    await settleWithImages(tester);
  }),
  A11yScreen('wallpaper-group-thread', (tester, world) async {
    world.extraOverrides = _wallpaperOverrides(
      const WallpaperSettings(defaultWallpaper: ChatWallpaper.preset('dusk')),
    );
    await _openThread(
      tester,
      world,
      id: 'group-1',
      title: groupDetail.title,
      type: ConversationType.group,
      withThread: true,
    );
    await settleWithImages(tester);
  }),
];

const _wallpaperPhotoPath = 'user-1/00000000-0000-4000-8000-00000000f0f0.jpg';

/// A wallpaper choice already on the person's account and this device, with
/// a photo to show.
List<Override> _wallpaperOverrides(WallpaperSettings settings) {
  final stores = WallpaperTestStores(
    repository: FakeWallpaperRepository(settings),
    cache: InMemoryWallpaperSettingsStore({'user-1': settings}),
  );
  stores.photos.photos[_wallpaperPhotoPath] = samplePhotoBytes(
    width: 320,
    height: 480,
  );
  return stores.overrides;
}

List<Override> _aiGuardOverrides() {
  final rpc = FakeGuardRpc()
    ..results['get_circle_ai_guard'] = guardJson(enabled: true)
    ..results['count_message_reviews'] = 2
    ..results['list_message_reviews'] = [
      reviewJson(),
      reviewJson(
        id: 'message-2',
        state: 'flagged',
        verdict: 'scam',
        reason: 'Asks for a password',
        body: 'Send me your password and I will send a prize',
      ),
    ];
  return [
    circleAiGuardRepositoryProvider.overrideWithValue(
      CircleAiGuardRepository(rpc),
    ),
  ];
}

List<Override> _aiOverrides() => [
  aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
  aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
];

/// Every screen the guard and the screenshot tool visit.
final allA11yScreens = <A11yScreen>[
  ...a11yScreens,
  ...moreA11yScreens,
  ...desktopLargeTextScreens,
  ...workspaceA11yScreens,
  ...voiceChainA11yScreens,
  ...multiSelectA11yScreens,
  ...photoEditorA11yScreens,
  ...locationA11yScreens,
  ...qrPatA11yScreens,
  ...momentsA11yScreens,
  ...quietHoursA11yScreens,
  ...chatFoldersA11yScreens,
  ...privacy2A11yScreens,
  ...adminA11yScreens,
  ...agendaA11yScreens,
  ...reportsLegalA11yScreens,
  ...editHistoryA11yScreens,
  ...joinRequestsA11yScreens,
  ...readStatusA11yScreens,
  ...autoTranslateA11yScreens,
  ...stickersA11yScreens,
  ...insightsA11yScreens,
  ...formsA11yScreens,
  ...adminOpsA11yScreens,
  ...aiAssistantA11yScreens,
  ...onboardingGuideA11yScreens,
  ...digestA11yScreens,
  ...profileExtrasA11yScreens,
  ...chatPolishA11yScreens,
  ...notes2A11yScreens,
  ...storiesA11yScreens,
  ...urgentA11yScreens,
  ...captionsA11yScreens,
  ...modToolsA11yScreens,
  ...aiAskA11yScreens,
  ...tasks2A11yScreens,
  ...favoritesA11yScreens,
  ...platformsA11yScreens,
  ...storageA11yScreens,
  ...moments2A11yScreens,
  ...guard2A11yScreens,
  ...opsMetricsA11yScreens,
  ...publicCircleA11yScreens,
  ...appLockA11yScreens,
  ...careModeA11yScreens,
  ...knowledgeBaseA11yScreens,
  ...memberHonorsA11yScreens,
  ...channelTypesA11yScreens,
  ...events2A11yScreens,
  ...accountSecurityA11yScreens,
  ...groupCheckinTabsA11yScreens,
  ...interactionsA11yScreens,
  ...scheduledCallsA11yScreens,
  ...groupSpaceA11yScreens,
  ...chatPrivacyA11yScreens,
  ...developerA11yScreens,
];
