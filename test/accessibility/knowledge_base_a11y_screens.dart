// The circle knowledge base (D6), for the accessibility guard
// (guidelines_test.dart) and the screenshot tools: the tree for a manager and
// for a member, an empty one, a page open with its menu, a row's options, the
// sheets (who can read and edit, locked by a higher role, move to), a new
// page, a search, the newcomer guide with a required page and its editor, and
// the wide layout, at large text and with Care mode on.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/circles/circle_onboarding.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/onboarding/guide_editor_screen.dart';
import 'package:wecord/features/circles/onboarding/guide_models.dart';
import 'package:wecord/features/circles/onboarding/guide_page.dart';
import 'package:wecord/features/knowledge_base/kb_models.dart';
import 'package:wecord/features/knowledge_base/kb_screen.dart';

import '../features/circles/circle_onboarding_test.dart'
    show FakeOnboardingDataSource;
import '../features/circles/onboarding_guide_fakes.dart';
import '../features/knowledge_base/kb_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

Future<KbWorld> _open(
  WidgetTester tester,
  PhoneWorld world, {
  bool manager = true,
  String? pageId,
  void Function(KbWorld world)? prepare,
}) async {
  final kb = KbWorld(world: world, manager: manager);
  prepare?.call(kb);
  kb.install();
  await pumpStandalone(
    tester,
    world,
    KnowledgeBaseScreen(circleId: 'circle-1', initialPageId: pageId),
  );
  // The editor opens a moment after the page.
  await tester.pump(const Duration(milliseconds: 600));
  return kb;
}

Future<void> _menuOf(WidgetTester tester, String pageId) async {
  final button = find.byKey(ValueKey('kb-more-$pageId'));
  if (button.evaluate().isEmpty) {
    await _scrollTo(tester, button);
  }
  await tester.tap(button);
  await settle(tester);
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await settle(tester);
}

/// The guide page with two required pages among the tasks.
Future<void> _guide(WidgetTester tester, PhoneWorld world) async {
  KbWorld(world: world).install();
  final rpc = GuideRpc()
    ..answer(
      'get_circle_guide',
      guideJson(
        prompts: const [],
        tasks: [
          guideTaskJson(
              id: 'task-welcome',
              title: 'Read the welcome page',
              action: 'read_page',
              done: true,
            )
            ..['page_id'] = 'p-welcome'
            ..['page_title'] = 'Welcome',
          guideTaskJson(
              id: 'task-rules',
              title: 'Read the rules before you post',
              action: 'read_page',
            )
            ..['page_id'] = 'p-rules'
            ..['page_title'] = 'Rules',
          guideTaskJson(
            id: 'task-avatar',
            title: 'Add a profile picture',
            action: 'set_avatar',
          ),
        ],
      ),
    );
  world.extraOverrides = [
    ...world.extraOverrides,
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
  ];
  await pumpStandalone(
    tester,
    world,
    const CircleGuidePage(circleId: 'circle-1', circleName: 'Hikers'),
  );
}

/// The guide editor with a task that reads a page, and the page picked.
Future<void> _guideEditor(WidgetTester tester, PhoneWorld world) async {
  KbWorld(world: world).install();
  world.extraOverrides = [
    ...world.extraOverrides,
    circleRpcProvider.overrideWithValue(GuideRpc().call),
  ];
  await pumpStandalone(
    tester,
    world,
    GuideEditor(
      detail: circleDetail(),
      initial: CircleGuideConfig.fromJson(
        guideConfigJson(
          prompts: const [],
          tasks: [
            {
              'id': 'task-rules',
              'title': 'Read the rules before you post',
              'action': 'read_page',
              'channel_id': null,
              'page_id': 'p-rules',
              'page_title': 'Rules',
            },
          ],
        ),
      ),
    ),
  );
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
  await settle(tester);
}

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

final knowledgeBaseA11yScreens = <A11yScreen>[
  A11yScreen('kb-tree', (tester, world) async {
    await _open(tester, world);
  }),
  A11yScreen('kb-tree-member', (tester, world) async {
    await _open(tester, world, manager: false);
  }),
  A11yScreen('kb-tree-large-text', (tester, world) async {
    await _open(tester, world);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('kb-tree-care-mode', (tester, world) async {
    _care(world);
    await _open(tester, world);
  }),
  A11yScreen('kb-tree-narrow', (tester, world) async {
    await _open(tester, world);
  }, viewport: smallPhone),
  A11yScreen('kb-empty', (tester, world) async {
    await _open(tester, world, prepare: (w) => w.knowledge.pages = []);
  }),
  A11yScreen('kb-page', (tester, world) async {
    await _open(tester, world, pageId: 'p-rules');
  }),
  A11yScreen('kb-page-menu', (tester, world) async {
    await _open(tester, world, pageId: 'p-rules');
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
  }),
  A11yScreen('kb-row-menu', (tester, world) async {
    await _open(tester, world);
    await _menuOf(tester, 'p-rules');
  }),
  A11yScreen('kb-access-sheet', (tester, world) async {
    await _open(tester, world);
    await _menuOf(tester, 'p-rules');
    await tester.tap(find.text('Who can read and edit…'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('kb-view-roles')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('kb-view-role-role-mod')));
    await settle(tester);
  }),
  A11yScreen('kb-access-locked', (tester, world) async {
    await _open(
      tester,
      world,
      prepare: (w) => w.knowledge.access = const KbPageAccess(
        viewRoleIds: ['role-mod'],
        locked: true,
        roles: [
          KbRole(id: 'role-mod', name: 'Moderators', color: 0x3366FF),
          KbRole(id: 'role-crew', name: 'Crew'),
        ],
      ),
    );
    await _menuOf(tester, 'p-rules');
    await tester.tap(find.text('Who can read and edit…'));
    await settle(tester);
  }),
  A11yScreen('kb-move-sheet', (tester, world) async {
    await _open(tester, world);
    await _menuOf(tester, 'p-guides');
    await tester.tap(find.text('Move to…'));
    await settle(tester);
  }),
  A11yScreen('kb-new-page', (tester, world) async {
    await _open(tester, world);
    await tester.tap(find.byKey(const ValueKey('kb-add-button')));
    await settle(tester);
  }),
  A11yScreen('kb-search', (tester, world) async {
    await _open(
      tester,
      world,
      prepare: (w) => w.knowledge.hits = const [
        KbSearchHit(
          id: 'p-rules',
          title: 'Rules',
          icon: '\u{1F4DC}',
          snippet:
              'Be kind. No spam or selling. Questions about the budget go to the finance room.',
        ),
        KbSearchHit(id: 'p-guides', title: 'Guides', icon: '\u{1F4DA}'),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('kb-search-button')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('kb-search-field')),
      'budget',
    );
    await tester.pump(const Duration(milliseconds: 500));
  }),
  A11yScreen('kb-guide-reading', _guide),
  A11yScreen('kb-guide-editor-page', _guideEditor),
  A11yScreen(
    'desktop-kb-pick',
    (tester, world) async {
      await _open(tester, world);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-kb-page',
    (tester, world) async {
      await _open(tester, world);
      await tester.tap(find.text('Welcome'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-kb-access',
    (tester, world) async {
      await _open(tester, world);
      await _menuOf(tester, 'p-rules');
      await tester.tap(find.text('Who can read and edit…'));
      await settle(tester);
      await _scrollTo(tester, find.byKey(const ValueKey('kb-access-save')));
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
