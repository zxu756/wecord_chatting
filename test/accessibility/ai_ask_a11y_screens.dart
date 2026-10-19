// Ask AI in Search (F1, stage 1), for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool: the switch and
// what it will look in, an answer with the messages it used (and a long one),
// no answer, and a failure.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/ask/ask_models.dart';
import 'package:wecord/features/ai/ask/ask_repository.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/ai/ai_fakes.dart';
import '../features/ai/ask_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// A place whose name is too long for a card.
const _longGroup = SearchPlace(
  id: 'conv-trail',
  type: ConversationType.group,
  title: 'Saturday morning trail runners and early breakfast club',
);

List<Override> _askOverrides(FakeAskRepository ask) => [
  askRepositoryProvider.overrideWithValue(ask),
  aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
  aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
];

/// An answer that fills a phone screen: a long reply and long messages from
/// places with long names.
AskAnswer _longAnswer() {
  return AskAnswer(
    found: true,
    answer:
        'Cy said the team dinner is at Haidilao on Friday at 7pm [1]. Ada '
        'confirmed the time and asked everyone to bring cash for the split [2]. '
        'Later Omar said he could only come after 8pm because of the late '
        'train, and Priya offered to save him a seat [3][4]. Nobody has '
        'said who is booking the table yet [1].',
    sources: [
      sampleSource(1),
      sampleSource(
        2,
        id: 'm2',
        sender: 'Ada Lovelace',
        snippet:
            '7pm works for me, bring cash please because the restaurant only '
            'takes cash at the weekend and we are splitting the bill evenly',
        place: sampleChannel,
      ),
      sampleSource(
        3,
        id: 'm3',
        sender: 'Omar Abdelrahman-Okonkwo',
        snippet: 'I can only come after 8pm, my train is late',
        place: _longGroup,
      ),
      sampleSource(
        4,
        id: 'm4',
        sender: 'Priya',
        snippet: "I'll save you a seat",
        place: _longGroup,
      ),
    ],
  );
}

Future<void> _ask(
  WidgetTester tester,
  PhoneWorld world,
  FakeAskRepository ask, {
  String? question = 'Where is the team dinner?',
  String path = GlobalMessageSearchScreen.path,
}) async {
  world.extraOverrides = _askOverrides(ask);
  await world.open(tester, path);
  await tester.tap(find.byKey(const ValueKey('search-mode-ask')));
  await settle(tester);
  if (question != null) {
    await tester.enterText(
      find.byKey(const ValueKey('message-search-field')),
      question,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ask-submit')));
    await settle(tester);
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
}

final aiAskA11yScreens = <A11yScreen>[
  A11yScreen(
    'ask-ai-intro',
    (tester, world) => _ask(tester, world, FakeAskRepository(), question: null),
  ),
  A11yScreen(
    'ask-ai-intro-desktop',
    (tester, world) => _ask(tester, world, FakeAskRepository(), question: null),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'ask-ai-answer',
    (tester, world) => _ask(tester, world, FakeAskRepository()),
  ),
  A11yScreen(
    'ask-ai-answer-desktop',
    (tester, world) => _ask(tester, world, FakeAskRepository()),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'ask-ai-answer-long',
    (tester, world) =>
        _ask(tester, world, FakeAskRepository(answers: [_longAnswer()])),
  ),
  A11yScreen(
    'ask-ai-in-a-chat',
    (tester, world) => _ask(
      tester,
      world,
      FakeAskRepository(),
      question: null,
      path: GlobalMessageSearchScreen.location(
        conversationId: 'conv-plan',
        conversationTitle: 'Weekend plan with the whole climbing group',
      ),
    ),
  ),
  A11yScreen(
    'ask-ai-not-found',
    (tester, world) => _ask(
      tester,
      world,
      FakeAskRepository(
        answers: const [AskAnswer.notFound(AskNotFoundReason.noMatches)],
      ),
      path: GlobalMessageSearchScreen.location(
        conversationId: 'conv-plan',
        conversationTitle: 'Weekend plan',
      ),
    ),
  ),
  A11yScreen(
    'ask-ai-failed',
    (tester, world) => _ask(
      tester,
      world,
      FakeAskRepository()..error = const AiBusyException(),
    ),
  ),
];
