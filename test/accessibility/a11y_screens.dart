// The main screens the accessibility guard and the accessibility
// screenshot tool (tool/screenshots/a11y_screenshots_test.dart) walk
// through: sign in, home, chat threads with their menus, circles, voice,
// settings, notifications, contacts, search, profile and discovery.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/features/search/message_search_controller.dart';

import '../features/ai/ai_fakes.dart';
import '../features/discovery/discovery_fakes.dart';
import '../mobile/phone_test_support.dart';

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
  A11yScreen('ai-catch-up', (tester, world) async {
    world.extraOverrides = _aiOverrides();
    await _openThread(tester, world);
    await tester.tap(find.byTooltip(tr('More')));
    await settle(tester);
    await tester.tap(find.text(tr('Summarize')));
    await settle(tester);
  }),
];

List<Override> _aiOverrides() => [
  aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
  aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
];

/// Every screen the guard and the screenshot tool visit.
final allA11yScreens = <A11yScreen>[...a11yScreens, ...moreA11yScreens];
