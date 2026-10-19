// Onboarding 2.0, for the accessibility guard (guidelines_test.dart) and the
// accessibility screenshot tool: the guide card on a circle, the guide page,
// the questions, and the editor in Onboarding settings, on a phone and on a
// desktop window.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/features/circles/circle_onboarding.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/models/circle_emoji.dart';

import '../features/circles/circle_onboarding_test.dart'
    show FakeOnboardingDataSource;
import '../features/circles/onboarding_guide_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// The fakes behind the guide. [needsAnswers] opens the questions on their
/// own, as for a member who just joined.
List<Override> guideOverrides({bool needsAnswers = false}) {
  final rpc = GuideRpc()
    ..answer(
      'get_circle_guide',
      guideJson(
        needsAnswers: needsAnswers,
        prompts: [
          guidePromptJson(required: true),
          guidePromptJson(
            id: 'prompt-2',
            title: 'Where do you play?',
            singleSelect: true,
            options: [
              guideOptionJson(id: 'opt-pc', label: 'PC', emoji: '💻'),
              guideOptionJson(id: 'opt-mobile', label: 'Mobile', emoji: '📱'),
            ],
          ),
        ],
      ),
    )
    ..answer('get_circle_guide_config', guideConfigJson());
  return [
    circleRpcProvider.overrideWithValue(rpc.call),
    circleOnboardingRepositoryProvider.overrideWithValue(
      CircleOnboardingRepository(
        FakeOnboardingDataSource({
          'enabled': false,
          'rules': <String>[],
          'needs_acceptance': false,
        }),
      ),
    ),
    circleEmojisProvider('circle-1').overrideWith(
      (ref) async => [
        CircleEmoji(
          id: 'sticker-wave',
          circleId: 'circle-1',
          name: 'wave',
          kind: CircleEmojiKind.sticker,
          storagePath: 'x/wave.png',
          mimeType: 'image/png',
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      ],
    ),
  ];
}

Future<void> _openCircle(
  WidgetTester tester,
  PhoneWorld world, {
  bool needsAnswers = false,
}) async {
  world.extraOverrides = guideOverrides(needsAnswers: needsAnswers);
  await world.open(tester, '/circles/circle-1');
  await settle(tester);
}

Future<void> _openGuidePage(WidgetTester tester, PhoneWorld world) async {
  await _openCircle(tester, world);
  await tester.tap(find.byKey(const ValueKey('circle-guide-bar')));
  await settle(tester);
}

Future<void> _openEditor(WidgetTester tester, PhoneWorld world) async {
  await _openCircle(tester, world);
  await tester.tap(find.byTooltip('Circle menu'));
  await settle(tester);
  final entry = find.text('Onboarding').last;
  await tester.ensureVisible(entry);
  await settle(tester);
  await tester.tap(entry);
  await settle(tester);
  final row = find.byKey(const ValueKey('onboarding-open-guide'));
  await tester.scrollUntilVisible(
    row,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(row);
  await settle(tester);
  await tester.tap(row);
  await settle(tester);
}

/// The editor on a desktop window, scrolled to its tasks and greeting so
/// that what the window shows is whole.
Future<void> _openEditorDown(WidgetTester tester, PhoneWorld world) async {
  await _openEditor(tester, world);
  await tester.drag(find.byType(ListView).last, const Offset(0, -2000));
  await settle(tester);
}

final onboardingGuideA11yScreens = <A11yScreen>[
  A11yScreen('guide-card-on-circle', _openCircle),
  A11yScreen('guide-page', _openGuidePage),
  A11yScreen(
    'guide-questions',
    (tester, world) => _openCircle(tester, world, needsAnswers: true),
  ),
  A11yScreen('guide-editor', _openEditor),
  A11yScreen(
    'desktop-guide-page',
    _openGuidePage,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-guide-editor',
    _openEditorDown,
    viewport: desktopViewport,
    desktop: true,
  ),
];
