// Group chains and voice input, for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chain/chain_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/features/voice_input/voice_input_settings.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/chain/chain_fakes.dart';
import '../features/voice_input/fake_voice_recognizer.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// A group chain with a few lines, as the chat shows it.
FakeChainRepository sampleChain({bool closed = false, bool mine = false}) {
  final repository = FakeChainRepository(
    conversationId: 'group-1',
    description: 'Meet at the gate at 8. Bring water.',
    example: '1. Ada +1',
    maxEntries: 12,
    deadline: DateTime.now().add(const Duration(days: 1, hours: 3)),
    closed: closed,
  );
  repository
    ..add('user-2', 'Bart the Bold', 'bringing snacks')
    ..add('user-3', 'Grace', '+1')
    ..add('user-4', 'Linus');
  if (mine) {
    repository.add('user-1', 'Me', 'driving, 3 seats');
  }
  return repository;
}

List<Override> _chainOverrides(FakeChainRepository repository) => [
  chainRepositoryProvider.overrideWithValue(repository),
];

List<Override> _voiceOverrides(FakeVoiceRecognizer recognizer) => [
  voiceRecognizerProvider.overrideWithValue(recognizer),
  voiceInputStoreProvider.overrideWithValue(InMemoryVoiceInputStore()),
];

Future<void> _openGroupWithChain(
  WidgetTester tester,
  PhoneWorld world,
  FakeChainRepository repository,
) async {
  world.extraOverrides = _chainOverrides(repository);
  world.chats.messages = [
    ...richMessages().take(3),
    phoneMessage(
      'chain-card',
      bart,
      '\u{1F517} Saturday hike sign-up',
      minutesAgo: 6,
      conversationId: 'group-1',
      attachment: const {
        'kind': 'chain',
        'chain_id': 'chain-1',
        'title': 'Saturday hike sign-up',
      },
    ),
  ];
  await world.open(
    tester,
    '${ChatsScreen.path}/group-1',
    extra: ChatThreadRouteExtra(
      title: groupDetail.title,
      type: ConversationType.group,
    ),
  );
  await settle(tester);
}

Future<void> _openDirect(
  WidgetTester tester,
  PhoneWorld world,
  FakeVoiceRecognizer recognizer,
) async {
  world.extraOverrides = _voiceOverrides(recognizer);
  world.chats.messages = richMessages();
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
  await settle(tester);
}

Future<void> _startVoice(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('composer-voice-input-button')));
  await settle(tester);
}

final voiceChainA11yScreens = <A11yScreen>[
  A11yScreen('chain-card', (tester, world) async {
    await _openGroupWithChain(tester, world, sampleChain(mine: true));
  }),
  A11yScreen('chain-card-closed', (tester, world) async {
    await _openGroupWithChain(tester, world, sampleChain(closed: true));
  }),
  A11yScreen('chain-sheet', (tester, world) async {
    await _openGroupWithChain(tester, world, sampleChain(mine: true));
    await tester.tap(find.byKey(const ValueKey('chain-card-chain-1')));
    await settle(tester);
  }),
  A11yScreen('chain-sheet-manager', (tester, world) async {
    final repository = sampleChain(mine: true)..canManage = true;
    await _openGroupWithChain(tester, world, repository);
    await tester.tap(find.byKey(const ValueKey('chain-card-chain-1')));
    await settle(tester);
  }),
  A11yScreen('chain-join-sheet', (tester, world) async {
    await _openGroupWithChain(tester, world, sampleChain());
    await tester.tap(find.byKey(const ValueKey('chain-join-chain-1')));
    await settle(tester);
  }),
  A11yScreen('chain-create-sheet', (tester, world) async {
    await _openGroupWithChain(tester, world, sampleChain());
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('composer-chain-entry')));
    await settle(tester);
  }),
  A11yScreen('voice-input-listening', (tester, world) async {
    final recognizer = FakeVoiceRecognizer();
    await _openDirect(tester, world, recognizer);
    await _startVoice(tester);
    final session = recognizer.session;
    for (final level in [0.1, 0.3, 0.7, 0.5, 0.9, 0.4, 0.2, 0.6, 0.8, 0.3]) {
      session.level(level);
    }
    session.say('see you at the gate at eight');
    await settle(tester);
  }),
  A11yScreen('voice-input-consent', (tester, world) async {
    final recognizer = FakeVoiceRecognizer(
      engine: VoiceInputEngine.appleServer,
    );
    await _openDirect(tester, world, recognizer);
    await _startVoice(tester);
  }),
  A11yScreen('voice-input-error', (tester, world) async {
    final recognizer = FakeVoiceRecognizer()
      ..startError = const VoiceInputException(VoiceInputFailure.micDenied);
    await _openDirect(tester, world, recognizer);
    await _startVoice(tester);
  }),
  A11yScreen('voice-input-settings', (tester, world) async {
    world.extraOverrides = _voiceOverrides(FakeVoiceRecognizer());
    await world.open(tester, '/me');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('voice-input-switch')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }),
  A11yScreen(
    'desktop-voice-input',
    (tester, world) async {
      final recognizer = FakeVoiceRecognizer();
      await _openDirect(tester, world, recognizer);
      await _startVoice(tester);
      recognizer.session
        ..level(0.4)
        ..level(0.8)
        ..say('把这个发给大家');
      await settle(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-chain-card',
    (tester, world) async {
      await _openGroupWithChain(tester, world, sampleChain(mine: true));
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
