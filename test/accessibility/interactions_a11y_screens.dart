// Interactive components and interaction callbacks (I1), for the accessibility
// guard (guidelines_test.dart) and the screenshot tools: a bot's message with
// buttons, a link and lists; the waiting and the problem notes; the choice
// sheets, the form and the link question; a private reply; and the callback
// address dialog of a bot - at large text, narrow and with Care mode on.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_bot_widgets.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/interactions/interactions_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message_components.dart';

import '../features/interactions/interactions_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

Future<FakeInteractionsRepository> _open(
  WidgetTester tester,
  PhoneWorld world, {
  bool care = false,
  bool privateReply = false,
  Object? components,
  bool alone = false,
}) async {
  if (care) {
    _care(world);
  }
  final fake = FakeInteractionsRepository();
  if (privateReply) {
    fake.ephemeral = [
      EphemeralReply(
        id: 'e1',
        messageId: 'bm1',
        botName: 'Helper',
        body: 'You approved **the budget**. Nobody else sees this message.',
        createdAt: DateTime.now(),
        components: MessageComponents.maybeFromJson([
          [
            {'type': 'button', 'id': 'undo', 'label': 'Undo my approval'},
          ],
        ]),
      ),
    ];
  }
  world.chats.messages = [
    if (!alone)
      phoneMessage('m0', bart, 'Morning! Anything for review?', minutesAgo: 30),
    botMessage(
      'bm1',
      components: components ?? sampleComponentsJson(),
      body: 'The **budget** for next month is ready for review.',
      minutesAgo: 10,
    ),
  ];
  world.extraOverrides = [
    interactionsRepositoryProvider.overrideWithValue(fake),
    interactionWaitProvider.overrideWithValue((
      limit: const Duration(seconds: 3),
      every: const Duration(seconds: 1),
    )),
  ];
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
  return fake;
}

/// Brings [finder] clear of the composer (the list scrolls under it) and taps.
Future<void> _tapClear(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await settle(tester);
  final view = tester.view.physicalSize / tester.view.devicePixelRatio;
  final overlap = tester.getRect(finder).bottom - (view.height - 120);
  if (overlap > 0) {
    await tester.drag(find.byType(Scrollable).first, Offset(0, -overlap - 24));
    await settle(tester);
  }
  await tester.tap(finder);
  await settle(tester);
}

Future<void> _tap(WidgetTester tester, String key) =>
    _tapClear(tester, find.byKey(ValueKey(key)));

Future<void> _waiting(WidgetTester tester, PhoneWorld world) async {
  await _open(tester, world);
  await _tap(tester, 'component-approve');
}

Future<void> _problem(WidgetTester tester, PhoneWorld world) async {
  final fake = await _open(tester, world);
  fake.failWith = const InteractionException(InteractionFailure.tooFast);
  await _tap(tester, 'component-reject');
}

Future<void> _selectSheet(WidgetTester tester, PhoneWorld world) async {
  await _open(tester, world);
  await _tap(tester, 'component-pick');
}

Future<void> _multiSheet(WidgetTester tester, PhoneWorld world) async {
  await _open(
    tester,
    world,
    components: [
      [
        {
          'type': 'select',
          'id': 'many',
          'placeholder': 'Which days can you come?',
          'options': [
            {'label': 'Saturday morning', 'value': 'sat-am', 'default': true},
            {'label': 'Saturday afternoon', 'value': 'sat-pm'},
            {'label': 'Sunday morning', 'value': 'sun-am'},
            {'label': 'Sunday afternoon', 'value': 'sun-pm'},
          ],
          'min_values': 1,
          'max_values': 3,
        },
      ],
    ],
  );
  await _tap(tester, 'component-many');
}

Future<void> _formSheet(WidgetTester tester, PhoneWorld world) async {
  await _open(tester, world);
  await _tap(tester, 'component-note');
}

Future<void> _formError(WidgetTester tester, PhoneWorld world) async {
  await _formSheet(tester, world);
  final send = find.byKey(const ValueKey('component-form-send'));
  await tester.ensureVisible(send);
  await settle(tester);
  await tester.tap(send);
  await settle(tester);
}

Future<void> _linkSheet(WidgetTester tester, PhoneWorld world) async {
  await _open(tester, world);
  await _tapClear(tester, find.text('Docs'));
}

Future<void> _callbackDialog(
  WidgetTester tester,
  PhoneWorld world, {
  Map<String, dynamic>? current,
}) async {
  Future<Object?> rpc(String name, Map<String, dynamic> params) async {
    return switch (name) {
      'list_circle_bots' => [
        {
          'id': 'bot-1',
          'circle_id': 'circle-1',
          'user_id': 'bot-user',
          'name': 'Helper',
          'username': 'bot_abc',
          'has_token': true,
          'is_member': true,
          'role_names': <String>[],
          'command_count': 2,
          'created_at': '2026-10-16T08:00:00Z',
        },
      ],
      'get_bot_callback' => current ?? {'url': null, 'enabled': false},
      _ => throw StateError('Unexpected $name'),
    };
  }

  await pumpStandalone(
    tester,
    world,
    Scaffold(
      body: SingleChildScrollView(
        child: CircleBotsSection(detail: circleDetail()),
      ),
    ),
    extraOverrides: [circleRpcProvider.overrideWithValue(rpc)],
  );
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('circle-bot-menu-bot-1')));
  await settle(tester);
  await tester.tap(find.text('Callback address'));
  await settle(tester);
}

final interactionsA11yScreens = <A11yScreen>[
  A11yScreen('bot-components', (tester, world) async {
    await _open(tester, world);
  }),
  A11yScreen('bot-components-large-text', (tester, world) async {
    await _open(tester, world, alone: true);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('bot-components-narrow', (tester, world) async {
    await _open(tester, world);
  }, viewport: smallPhone),
  A11yScreen('bot-components-care-mode', (tester, world) async {
    await _open(tester, world, care: true);
  }),
  A11yScreen('bot-components-waiting', _waiting),
  A11yScreen(
    'bot-components-waiting-large-text',
    _waiting,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('bot-components-problem', _problem),
  A11yScreen('bot-select-sheet', _selectSheet),
  A11yScreen(
    'bot-select-sheet-large-text',
    _selectSheet,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('bot-select-multi-sheet', _multiSheet),
  A11yScreen(
    'bot-select-multi-sheet-narrow',
    _multiSheet,
    viewport: smallPhone,
  ),
  A11yScreen('bot-form-sheet', _formSheet),
  A11yScreen(
    'bot-form-sheet-large-text',
    _formSheet,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('bot-form-sheet-narrow', _formError, viewport: smallPhone),
  A11yScreen('bot-form-sheet-error', _formError),
  A11yScreen('bot-link-sheet', _linkSheet),
  A11yScreen(
    'bot-link-sheet-large-text',
    _linkSheet,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('bot-private-reply', (tester, world) async {
    await _open(tester, world, privateReply: true);
  }),
  A11yScreen('bot-private-reply-large-text', (tester, world) async {
    await _open(tester, world, privateReply: true);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('bot-private-reply-care-mode', (tester, world) async {
    await _open(tester, world, privateReply: true, care: true);
  }),
  A11yScreen('bot-callback-dialog', (tester, world) async {
    await _callbackDialog(tester, world);
  }),
  A11yScreen('bot-callback-dialog-large-text', (tester, world) async {
    await _callbackDialog(tester, world);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('bot-callback-dialog-paused', (tester, world) async {
    await _callbackDialog(
      tester,
      world,
      current: {
        'url': 'https://bots.example.com/wecord/hook',
        'enabled': false,
        'consecutive_failures': 20,
        'last_error': 'timeout',
      },
    );
  }),
  A11yScreen('bot-callback-dialog-narrow', (tester, world) async {
    await _callbackDialog(
      tester,
      world,
      current: {
        'url': 'https://bots.example.com/wecord/hook',
        'enabled': true,
        'last_success_at': '2026-10-28T09:00:00Z',
      },
    );
  }, viewport: smallPhone),
  A11yScreen(
    'desktop-bot-components',
    (tester, world) async {
      await _open(tester, world, privateReply: true);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
