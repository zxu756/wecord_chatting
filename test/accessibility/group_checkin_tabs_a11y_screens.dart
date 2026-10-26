// Group check-in (D3) and group tabs (D8), for the accessibility guard
// (guidelines_test.dart) and the screenshot tools: a chat with the check-in
// card (open, done, closed), the check-in page with its calendar, streaks and
// list, the note sheet, the page that makes a check-in, and the chat's tab
// strip (folded, open, with the pinned note), the Tabs entry of the More
// menu, the list of tabs for an admin and for a member, the kinds that can be
// added and the link form, at large text, narrow and with Care mode on.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/check_in/check_in_actions.dart';
import 'package:wecord/features/check_in/check_in_create_page.dart';
import 'package:wecord/features/check_in/check_in_page.dart';
import 'package:wecord/features/forms/form_models.dart' show FormImageAnswer;
import 'package:wecord/features/group_tabs/group_tab_models.dart';
import 'package:wecord/features/group_tabs/group_tab_strip.dart';
import 'package:wecord/features/group_tabs/group_tabs_sheet.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/check_in/check_in_fakes.dart';
import '../features/group_tabs/group_tabs_fakes.dart';
import '../features/workspace/workspace_world.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

/// "Read 20 pages": 18 of 30 checked in today, a run of 7 for the caller
/// (who has or has not checked in today).
FakeCheckInRepository sampleCheckIn({
  bool done = false,
  bool closed = false,
  bool manage = false,
}) {
  final repository = FakeCheckInRepository(
    description: 'Post a line or a picture of what you read.',
    canManage: manage,
    closed: closed,
    remindMinute: 20 * 60,
  );
  const names = [
    'Grace',
    'Linus',
    'Mei',
    'Tomás',
    'Priya',
    'Jonas',
    'Aiko',
    'Sam',
    'Noor',
    'Lea',
    'Omar',
    'Ines',
    'Hugo',
    'Yara',
    'Dev',
    'Zoe',
    'Kai',
  ];
  for (var i = 0; i < names.length; i++) {
    repository.addEntry(
      'user-${i + 10}',
      names[i],
      fakeToday,
      note: i.isEven ? 'Chapter ${i + 1}. Loved the ending.' : '',
      photo: i == 1
          ? const FormImageAnswer(
              bucket: 'chat-images',
              path: 'group-1/check-ins/ci-1/pic.jpg',
            )
          : null,
    );
    // Long runs for a few of them.
    for (var back = 1; back <= (i % 5) + (i < 3 ? 4 : 0); back++) {
      repository.addEntry(
        'user-${i + 10}',
        names[i],
        fakeToday.subtract(Duration(days: back)),
      );
    }
  }
  // The caller: seven days up to yesterday (and today, when done), with a
  // gap a fortnight ago.
  for (var back = done ? 0 : 1; back <= 7; back++) {
    repository.addEntry(
      'user-1',
      'Ada',
      fakeToday.subtract(Duration(days: back)),
      note: back == 0 ? 'Two chapters tonight' : '',
    );
  }
  for (final back in [10, 11, 13, 16, 17, 20, 24]) {
    repository.addEntry(
      'user-1',
      'Ada',
      fakeToday.subtract(Duration(days: back)),
    );
  }
  return repository;
}

Future<void> _openGroup(
  WidgetTester tester,
  WorkspaceWorld workspace, {
  FakeCheckInRepository? checkIn,
  FakeGroupTabsRepository? tabs,
  bool card = false,
  ConversationType type = ConversationType.group,
  String id = 'group-1',
}) async {
  final world = workspace.world;
  world.extraOverrides = [
    ...world.extraOverrides,
    if (checkIn != null) ...checkInOverrides(checkIn, withPicker: false),
    if (tabs != null) ...groupTabsOverrides(tabs),
  ];
  if (card) {
    world.chats.messages = [
      ...richMessages().take(3),
      phoneMessage(
        'check-in-card',
        bart,
        '✅ Read 20 pages',
        minutesAgo: 6,
        conversationId: 'group-1',
        attachment: const {
          'kind': 'check_in',
          'check_in_id': 'ci-1',
          'title': 'Read 20 pages',
        },
      ),
    ];
  }
  await world.open(
    tester,
    '${ChatsScreen.path}/$id',
    extra: ChatThreadRouteExtra(title: groupDetail.title, type: type),
  );
  await settle(tester);
}

Future<void> _card(
  WidgetTester tester,
  PhoneWorld world, {
  bool done = false,
  bool closed = false,
}) async {
  final workspace = WorkspaceWorld(world: world);
  workspace.notes.pinned = null;
  workspace.install();
  await _openGroup(
    tester,
    workspace,
    checkIn: sampleCheckIn(done: done, closed: closed),
    card: true,
  );
}

Future<void> _page(
  WidgetTester tester,
  PhoneWorld world, {
  bool done = false,
  bool closed = false,
  bool manage = false,
  bool scrollToDays = false,
}) async {
  final repository = sampleCheckIn(done: done, closed: closed, manage: manage);
  world.extraOverrides = [
    ...world.extraOverrides,
    ...checkInOverrides(repository, withPicker: false),
  ];
  await pumpStandalone(tester, world, const CheckInPage(checkInId: 'ci-1'));
  await settle(tester);
  if (scrollToDays) {
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('check-in-day-label')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }
}

Future<void> _noteSheet(WidgetTester tester, PhoneWorld world) async {
  final repository = sampleCheckIn();
  world.extraOverrides = [
    ...world.extraOverrides,
    ...checkInOverrides(repository, withPicker: false),
  ];
  await pumpStandalone(
    tester,
    world,
    Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async =>
                showCheckInNoteSheet(context, check: repository.snapshot),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester);
}

Future<void> _create(
  WidgetTester tester,
  PhoneWorld world, {
  bool filled = false,
}) async {
  world.extraOverrides = [
    ...world.extraOverrides,
    ...checkInOverrides(FakeCheckInRepository(), withPicker: false),
  ];
  await pumpStandalone(
    tester,
    world,
    const CheckInCreatePage(conversationId: 'group-1'),
  );
  await settle(tester);
  if (filled) {
    await tester.enterText(
      find.byKey(const ValueKey('check-in-title-field')),
      'Read 20 pages',
    );
    await tester.tap(find.byKey(const ValueKey('check-in-setting-remind')));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('check-in-setting-end')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }
}

FakeGroupTabsRepository _tabs({bool manage = true, bool broken = false}) {
  final repository = FakeGroupTabsRepository(
    canManage: manage,
    circleId: null,
    tabs: [
      sampleTab('t1', 'note', 'House rules', target: 'n1', icon: '\u{1F4D8}'),
      sampleTab('t2', 'list', 'Chores', target: 'l1', icon: '✅'),
      sampleTab('t3', 'check_in', 'Read 20 pages', target: 'ci-1'),
      sampleTab('t4', 'form', 'Hike sign-up', target: 'f1', closed: true),
      sampleTab('t5', 'link', 'Timetable', target: 'https://example.com/t'),
      sampleTab('t6', 'events', 'Events'),
      if (broken)
        sampleTab('t7', 'note', 'Deleted note', target: 'n9', available: false),
    ],
  );
  repository.candidatesByKind['form'] = const [
    GroupTabCandidate(target: 'f1', title: 'Hike sign-up'),
  ];
  return repository;
}

Future<void> _strip(
  WidgetTester tester,
  PhoneWorld world, {
  bool open = false,
  bool pinned = false,
  bool manage = true,
}) async {
  GroupTabStrip.forgetExpanded();
  final workspace = WorkspaceWorld(world: world);
  if (!pinned) {
    workspace.notes.pinned = null;
  }
  workspace.install();
  await _openGroup(
    tester,
    workspace,
    tabs: _tabs(manage: manage),
    checkIn: sampleCheckIn(),
    card: true,
  );
  if (open) {
    await tester.tap(find.byKey(const ValueKey('group-tabs-fold')));
    await settle(tester);
  }
}

Future<void> _more(WidgetTester tester, PhoneWorld world) async {
  GroupTabStrip.forgetExpanded();
  final workspace = WorkspaceWorld(world: world);
  workspace.notes.pinned = null;
  workspace.install();
  await _openGroup(tester, workspace, tabs: _tabs());
  await tester.tap(find.byTooltip('More'));
  await settle(tester);
}

Future<void> _sheet(
  WidgetTester tester,
  PhoneWorld world, {
  bool manage = true,
  bool broken = false,
  bool empty = false,
  bool add = false,
  bool link = false,
}) async {
  final repository = empty
      ? FakeGroupTabsRepository(canManage: manage)
      : _tabs(manage: manage, broken: broken);
  world.extraOverrides = [
    ...world.extraOverrides,
    ...groupTabsOverrides(repository),
  ];
  await pumpStandalone(
    tester,
    world,
    Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => unawaited(
              showGroupTabsSheet(
                context,
                conversationId: 'group-1',
                title: 'Hike club',
                circleId: add ? 'circle-1' : null,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester);
  if (add || link) {
    // The button is under the tabs: scroll the sheet to it.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-tab-add')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(GroupTabsSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('group-tab-add')));
    await settle(tester);
  }
  if (link) {
    await tester.tap(find.byKey(const ValueKey('group-tab-kind-link')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('group-tab-link-done')));
    await settle(tester);
  }
}

final groupCheckinTabsA11yScreens = <A11yScreen>[
  A11yScreen('check-in-card', (tester, world) => _card(tester, world)),
  A11yScreen(
    'check-in-card-large-text',
    (tester, world) => _card(tester, world),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'check-in-card-narrow',
    (tester, world) => _card(tester, world),
    viewport: smallPhone,
  ),
  A11yScreen(
    'check-in-card-done',
    (tester, world) => _card(tester, world, done: true),
  ),
  A11yScreen(
    'check-in-card-closed',
    (tester, world) => _card(tester, world, closed: true),
  ),
  A11yScreen('check-in-page', (tester, world) => _page(tester, world)),
  A11yScreen(
    'check-in-page-large-text',
    (tester, world) => _page(tester, world),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'check-in-page-narrow',
    (tester, world) => _page(tester, world),
    viewport: smallPhone,
  ),
  A11yScreen(
    'check-in-page-done',
    (tester, world) => _page(tester, world, done: true),
  ),
  A11yScreen(
    'check-in-page-days',
    (tester, world) => _page(tester, world, done: true, scrollToDays: true),
  ),
  A11yScreen(
    'check-in-page-manager-closed',
    (tester, world) =>
        _page(tester, world, closed: true, manage: true, scrollToDays: true),
  ),
  A11yScreen('check-in-page-care-mode', (tester, world) {
    _care(world);
    return _page(tester, world);
  }),
  A11yScreen('check-in-note-sheet', _noteSheet),
  A11yScreen('check-in-note-sheet-narrow', _noteSheet, viewport: smallPhone),
  A11yScreen('check-in-create', (tester, world) => _create(tester, world)),
  A11yScreen(
    'check-in-create-filled',
    (tester, world) => _create(tester, world, filled: true),
  ),
  A11yScreen(
    'check-in-create-large-text',
    (tester, world) => _create(tester, world, filled: true),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'check-in-create-narrow',
    (tester, world) => _create(tester, world, filled: true),
    viewport: smallPhone,
  ),
  A11yScreen('group-tabs-folded', (tester, world) => _strip(tester, world)),
  A11yScreen(
    'group-tabs-open',
    (tester, world) => _strip(tester, world, open: true),
  ),
  A11yScreen(
    'group-tabs-open-pinned-note',
    (tester, world) => _strip(tester, world, open: true, pinned: true),
  ),
  A11yScreen(
    'group-tabs-open-large-text',
    (tester, world) => _strip(tester, world, open: true, pinned: true),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'group-tabs-open-narrow',
    (tester, world) => _strip(tester, world, open: true, pinned: true),
    viewport: smallPhone,
  ),
  A11yScreen('group-tabs-more-menu', _more),
  A11yScreen('group-tabs-more-menu-narrow', _more, viewport: smallPhone),
  A11yScreen('group-tabs-sheet', (tester, world) => _sheet(tester, world)),
  A11yScreen(
    'group-tabs-sheet-large-text',
    (tester, world) => _sheet(tester, world, broken: true),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'group-tabs-sheet-narrow',
    (tester, world) => _sheet(tester, world, broken: true),
    viewport: smallPhone,
  ),
  A11yScreen(
    'group-tabs-sheet-member',
    (tester, world) => _sheet(tester, world, manage: false),
  ),
  A11yScreen(
    'group-tabs-sheet-empty',
    (tester, world) => _sheet(tester, world, empty: true),
  ),
  A11yScreen(
    'group-tabs-add-kinds',
    (tester, world) => _sheet(tester, world, add: true),
  ),
  A11yScreen(
    'group-tabs-add-link',
    (tester, world) => _sheet(tester, world, link: true),
  ),
  A11yScreen('group-tabs-care-mode', (tester, world) {
    _care(world);
    return _strip(tester, world, open: true);
  }),
  A11yScreen(
    'desktop-group-tabs-open',
    (tester, world) => _strip(tester, world, open: true, pinned: true),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-check-in-page',
    (tester, world) => _page(tester, world, done: true),
    viewport: desktopViewport,
    desktop: true,
  ),
];
