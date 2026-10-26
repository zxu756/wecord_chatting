// Group tabs and check-ins inside the chat page: the strip under the header
// (and the pinned note that moves into it), the Tabs entry of the More menu,
// the Daily check-in entry of the + menu and the check-in card in the list.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu_builtin.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu_registrations.dart';
import 'package:wecord/features/chats/thread/registry/header_actions_registrations.dart';
import 'package:wecord/features/check_in/check_in_chat.dart';
import 'package:wecord/features/group_tabs/group_tab_strip.dart';
import 'package:wecord/features/group_tabs/group_tabs_chat.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../mobile/phone_test_support.dart';
import '../check_in/check_in_fakes.dart';
import '../workspace/workspace_world.dart';
import 'group_tabs_fakes.dart';

Future<void> openChat(
  WidgetTester tester,
  PhoneWorld world, {
  ConversationType type = ConversationType.group,
  String id = 'group-1',
}) {
  return world.open(
    tester,
    '${ChatsScreen.path}/$id',
    extra: ChatThreadRouteExtra(title: groupDetail.title, type: type),
  );
}

void main() {
  setUp(GroupTabStrip.forgetExpanded);

  testWidgets('a group with tabs has the folded strip; opened, it has the '
      'chips', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    final workspace = WorkspaceWorld()..install();
    workspace.notes.pinned = null;
    final tabs = FakeGroupTabsRepository(
      tabs: [
        sampleTab('t1', 'events', 'Events'),
        sampleTab('t2', 'link', 'Schedule', target: 'https://example.com/s'),
      ],
    );
    workspace.world.extraOverrides = [
      ...workspace.world.extraOverrides,
      ...groupTabsOverrides(tabs),
    ];
    await openChat(tester, workspace.world);

    expect(find.byKey(const ValueKey('group-tabs-fold')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-tabs-row')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('group-tabs-fold')));
    await settle(tester);
    expect(find.text('Schedule'), findsOneWidget);
    await workspace.world.close(tester);
  });

  testWidgets('with tabs the pinned note moves into the strip; without, the '
      'banner stays', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    final workspace = WorkspaceWorld()..install();
    final tabs = FakeGroupTabsRepository(
      tabs: [sampleTab('t1', 'events', 'Events')],
    );
    workspace.world.extraOverrides = [
      ...workspace.world.extraOverrides,
      ...groupTabsOverrides(tabs),
    ];
    await openChat(tester, workspace.world);
    expect(find.byKey(const ValueKey('pinned-note-banner')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('group-tabs-fold')));
    await settle(tester);
    expect(find.byKey(const ValueKey('group-tab-pinned-note')), findsOneWidget);
    await workspace.world.close(tester);

    // The same chat with no tabs: the banner as it always was.
    final plain = WorkspaceWorld()..install();
    await openChat(tester, plain.world);
    expect(find.byKey(const ValueKey('pinned-note-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-tabs-fold')), findsNothing);
    await plain.world.close(tester);
  });

  testWidgets('a direct chat has no strip and no Tabs entry', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    final workspace = WorkspaceWorld()..install();
    final tabs = FakeGroupTabsRepository(
      tabs: [sampleTab('t1', 'events', 'Events')],
    );
    workspace.world.extraOverrides = [
      ...workspace.world.extraOverrides,
      ...groupTabsOverrides(tabs),
    ];
    await openChat(
      tester,
      workspace.world,
      type: ConversationType.direct,
      id: 'dm-1',
    );
    expect(find.byKey(const ValueKey('group-tabs-fold')), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    expect(find.text('Tabs'), findsNothing);
    await workspace.world.close(tester);
  });

  testWidgets('the More menu of a group has Tabs and it opens the list', (
    tester,
  ) async {
    usePhoneViewport(tester, notchedPhone);
    final workspace = WorkspaceWorld()..install();
    workspace.notes.pinned = null;
    final tabs = FakeGroupTabsRepository(
      tabs: [sampleTab('t1', 'events', 'Events')],
    );
    workspace.world.extraOverrides = [
      ...workspace.world.extraOverrides,
      ...groupTabsOverrides(tabs),
    ];
    await openChat(tester, workspace.world);
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Tabs').last);
    await settle(tester);
    expect(find.byKey(const ValueKey('group-tabs-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-tab-add')), findsOneWidget);
    await workspace.world.close(tester);
  });

  testWidgets('a check-in message is the live card, not its text', (
    tester,
  ) async {
    usePhoneViewport(tester, notchedPhone);
    final workspace = WorkspaceWorld()..install();
    workspace.notes.pinned = null;
    final checkIn = FakeCheckInRepository(conversationId: 'group-1');
    checkIn.addEntry('user-3', 'Bob', fakeToday);
    workspace.world.extraOverrides = [
      ...workspace.world.extraOverrides,
      ...checkInOverrides(checkIn, withPicker: false),
    ];
    workspace.world.chats.messages = [
      ...richMessages().take(2),
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
    await openChat(tester, workspace.world);
    expect(find.byKey(const ValueKey('check-in-card-ci-1')), findsOneWidget);
    expect(find.text('Today 1/30'), findsOneWidget);
    expect(find.textContaining('✅'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('check-in-do-ci-1')));
    await settle(tester);
    expect(checkIn.calls, contains('submit'));
    expect(find.text('Today 2/30'), findsOneWidget);
    await workspace.world.close(tester);
  });

  testWidgets('the + menu of a group has Daily check-in, a direct chat does '
      'not', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    final workspace = WorkspaceWorld()..install();
    workspace.world.extraOverrides = [
      ...workspace.world.extraOverrides,
      ...checkInOverrides(FakeCheckInRepository(), withPicker: false),
    ];
    await openChat(tester, workspace.world);
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('composer-check-in-entry')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('composer-check-in-entry')));
    await settle(tester);
    expect(find.byKey(const ValueKey('check-in-create-page')), findsOneWidget);
    await workspace.world.close(tester);
  });

  test('the entries sit in the registries in the right place', () {
    final composer = ComposerMenuRegistry([
      ...builtInComposerMenu,
      checkInComposerEntry,
    ]);
    expect(
      composer.ids.indexOf('check-in'),
      greaterThan(composer.ids.indexOf('chain')),
    );
    expect(composerMenuExtensions, contains(checkInComposerEntry));
    expect(headerActionExtensions, contains(groupTabsHeaderAction));
    expect(groupTabsHeaderAction.order, greaterThan(1200));
    expect(groupTabsHeaderAction.order, lessThan(1500));
  });
}
