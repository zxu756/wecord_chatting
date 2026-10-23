import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/group_tabs/group_tab_kind_space.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds_builtin.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds_registrations.dart';
import 'package:wecord/features/group_tabs/group_tab_models.dart';
import 'package:wecord/features/group_tabs/group_tab_pickers.dart';
import 'package:wecord/features/group_tabs/group_tab_strip.dart';
import 'package:wecord/features/group_tabs/group_tabs_sheet.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart' show WeCordButton;

import 'group_tabs_fakes.dart';

/// Kinds that only write down what they were asked to open.
GroupTabKindRegistry recordingRegistry(List<String> opened) {
  GroupTabKindContribution kind(String name, int order, IconData icon) =>
      GroupTabKindContribution(
        kind: name,
        order: order,
        label: () => name.toUpperCase(),
        icon: icon,
        open: (ctx, tab) => opened.add('$name:${tab.target ?? '-'}'),
      );
  return GroupTabKindRegistry([
    kind('note', 100, Icons.description_outlined),
    kind('link', 200, Icons.link_rounded),
    kind('events', 300, Icons.event_outlined),
  ]);
}

Widget host(
  FakeGroupTabsRepository repository,
  Widget child, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    retry: (count, error) => null,
    overrides: [...groupTabsOverrides(repository), ...overrides],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

final _threeTabs = [
  sampleTab('t1', 'note', 'House rules', target: 'n1', icon: '\u{1F4D8}'),
  sampleTab('t2', 'link', 'Schedule', target: 'https://example.com/s'),
  sampleTab('t3', 'events', 'Events'),
];

void main() {
  setUp(GroupTabStrip.forgetExpanded);

  group('models', () {
    test('a tab reads the server and an unknown flag counts as available', () {
      final tab = GroupTab.fromJson({
        'id': 't',
        'kind': 'note',
        'target': 'n',
        'title': 'Rules',
        'icon': 'x',
        'sort': 2,
        'closed': true,
        'circle_id': 'c',
      });
      expect(tab.available, isTrue);
      expect(tab.closed, isTrue);
      expect(tab.sort, 2);
      expect(tab.circleId, 'c');
    });

    test('the list reads who may manage it', () {
      final tabs = GroupTabs.fromJson({
        'can_manage': true,
        'tabs': [
          {'id': 'a', 'kind': 'link', 'title': 'A'},
          {'id': 'b', 'kind': 'note', 'title': 'B', 'available': false},
        ],
      });
      expect(tabs.canManage, isTrue);
      expect(tabs.tabs.map((t) => t.id), ['a', 'b']);
      expect(tabs.tabs.last.available, isFalse);
      expect(const GroupTabs().tabs, isEmpty);
    });

    test('server refusals become the right failure', () {
      GroupTabFailureKind kind(String message, {String? code}) =>
          GroupTabException.fromPostgrest(
            PostgrestException(message: message, code: code),
          ).kind;
      expect(kind('tab_limit'), GroupTabFailureKind.limit);
      expect(kind('tab_exists'), GroupTabFailureKind.exists);
      expect(kind('tab_target_invalid'), GroupTabFailureKind.badTarget);
      expect(kind('tab_title_invalid'), GroupTabFailureKind.badTitle);
      expect(kind('Tab not found'), GroupTabFailureKind.gone);
      expect(kind('x', code: '42501'), GroupTabFailureKind.notAllowed);
      for (final value in GroupTabFailureKind.values) {
        expect(GroupTabException(value).message, isNotEmpty);
      }
    });

    test('web addresses are http or https with a host and no spaces', () {
      expect(isGroupTabLink('https://example.com/a?b=1'), isTrue);
      expect(isGroupTabLink('http://example.com'), isTrue);
      expect(isGroupTabLink('javascript:alert(1)'), isFalse);
      expect(isGroupTabLink('ftp://example.com'), isFalse);
      expect(isGroupTabLink('https://'), isFalse);
      expect(isGroupTabLink('https://exa mple.com'), isFalse);
      expect(isGroupTabLink('https://example.com/${'a' * 500}'), isFalse);
    });

    test('the words are Chinese in Chinese', () {
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      expect(tr('Tabs'), '标签页');
      expect(tr('Tabs, {count}', {'count': 3}), '标签页，共 3 个');
    });
  });

  group('the kinds', () {
    GroupTabContext context(BuildContext context, {String? circleId}) =>
        GroupTabContext(
          context: context,
          conversationId: 'g',
          title: 'Hike',
          circleId: circleId,
        );

    testWidgets('the built-in kinds come in order; the knowledge base needs a '
        'circle channel', (tester) async {
      late BuildContext inside;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              inside = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final registry = GroupTabKindRegistry(builtInGroupTabKinds);
      expect(registry.kinds, [
        'note',
        'list',
        'form',
        'check_in',
        'link',
        'kb',
        'events',
      ]);
      expect(
        registry.addable(context(inside)).map((k) => k.kind),
        isNot(contains('kb')),
      );
      expect(
        registry.addable(context(inside, circleId: 'c')).map((k) => k.kind),
        contains('kb'),
      );
      expect(registry.opens('mystery'), isFalse);
      expect(registry.kindOf('link')?.pick, isNotNull);
      expect(registry.kindOf('events')?.pick, isNull);
    });

    test('another package adds a kind with one contribution', () {
      final registry = GroupTabKindRegistry([
        ...builtInGroupTabKinds,
        GroupTabKindContribution(
          kind: GroupTabKinds.space,
          order: 650,
          label: () => 'Space',
          icon: Icons.photo_library_outlined,
          open: (ctx, tab) {},
        ),
      ]);
      expect(registry.kinds, contains('space'));
      expect(registry.kinds.indexOf('space'), registry.kinds.indexOf('kb') + 1);
    });

    test('the group space is a kind, for groups only', () {
      expect(groupTabKindExtensions, contains(spaceGroupTabKind));
      expect(spaceGroupTabKind.kind, 'space');
      expect(spaceGroupTabKind.pick, isNull);
    });

    test('the extension list is where a package adds its kind', () {
      expect(groupTabKindExtensions, isA<List<GroupTabKindContribution>>());
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(groupTabKindRegistryProvider).kinds,
        containsAll(['note', 'list', 'form', 'check_in', 'link', 'space']),
      );
    });
  });

  group('the strip', () {
    Widget strip(
      FakeGroupTabsRepository repository, {
      NoteMeta? pinned,
      List<String>? opened,
      List<Override> overrides = const [],
    }) => host(
      repository,
      GroupTabStrip(conversationId: 'g', title: 'Hike', pinnedNote: pinned),
      overrides: [
        groupTabKindRegistryProvider.overrideWithValue(
          recordingRegistry(opened ?? []),
        ),
        ...overrides,
      ],
    );

    testWidgets('a chat with no tabs shows nothing', (tester) async {
      await tester.pumpWidget(strip(FakeGroupTabsRepository()));
      await settle(tester);
      expect(find.byKey(const ValueKey('group-tabs-fold')), findsNothing);
    });

    testWidgets('it is folded: one slim line with the count', (tester) async {
      await tester.pumpWidget(strip(FakeGroupTabsRepository(tabs: _threeTabs)));
      await settle(tester);
      expect(find.byKey(const ValueKey('group-tabs-fold')), findsOneWidget);
      expect(find.text('Tabs'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.byKey(const ValueKey('group-tabs-row')), findsNothing);
      expect(find.text('Schedule'), findsNothing);
    });

    testWidgets('a tap opens the row of chips; another folds it again', (
      tester,
    ) async {
      final opened = <String>[];
      await tester.pumpWidget(
        strip(FakeGroupTabsRepository(tabs: _threeTabs), opened: opened),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('group-tabs-fold')));
      await settle(tester);

      expect(find.byKey(const ValueKey('group-tabs-row')), findsOneWidget);
      expect(find.text('\u{1F4D8} House rules'), findsOneWidget);
      expect(find.text('Schedule'), findsOneWidget);
      expect(find.text('Manage'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('group-tab-t2')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('group-tab-t1')));
      await settle(tester);
      expect(opened, ['link:https://example.com/s', 'note:n1']);

      await tester.tap(find.byKey(const ValueKey('group-tabs-fold')));
      await settle(tester);
      expect(find.byKey(const ValueKey('group-tabs-row')), findsNothing);
    });

    testWidgets('a person who cannot manage sees All, not Manage', (
      tester,
    ) async {
      await tester.pumpWidget(
        strip(FakeGroupTabsRepository(tabs: _threeTabs, canManage: false)),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('group-tabs-fold')));
      await settle(tester);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Manage'), findsNothing);
    });

    testWidgets('tabs whose target is gone or kind the app lacks are left '
        'out', (tester) async {
      final repository = FakeGroupTabsRepository(
        tabs: [
          sampleTab('t1', 'note', 'Gone', target: 'n', available: false),
          sampleTab('t2', 'mystery', 'From the future'),
          sampleTab('t3', 'events', 'Events'),
        ],
      );
      await tester.pumpWidget(strip(repository));
      await settle(tester);
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group-tabs-fold')));
      await settle(tester);
      expect(find.text('Gone'), findsNothing);
      expect(find.text('From the future'), findsNothing);
      expect(find.text('Events'), findsOneWidget);
    });

    testWidgets('only unknown tabs: nothing to show', (tester) async {
      final repository = FakeGroupTabsRepository(
        tabs: [sampleTab('t2', 'mystery', 'From the future')],
      );
      await tester.pumpWidget(strip(repository));
      await settle(tester);
      expect(find.byKey(const ValueKey('group-tabs-fold')), findsNothing);
    });

    testWidgets('the pinned note is the first tab and counts', (tester) async {
      await tester.pumpWidget(
        strip(
          FakeGroupTabsRepository(tabs: _threeTabs),
          pinned: const NoteMeta(
            id: 'np',
            conversationId: 'g',
            title: 'Trip plan',
            icon: '\u{1F5FA}',
            pinned: true,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('4'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group-tabs-fold')));
      await settle(tester);
      final first = tester.getTopLeft(
        find.byKey(const ValueKey('group-tab-pinned-note')),
      );
      final second = tester.getTopLeft(
        find.byKey(const ValueKey('group-tab-t1')),
      );
      expect(first.dx, lessThan(second.dx));
      expect(find.text('\u{1F5FA} Trip plan'), findsOneWidget);
    });

    testWidgets('a long name is cut so the row stays slim', (tester) async {
      final repository = FakeGroupTabsRepository(
        tabs: [
          sampleTab('t1', 'events', 'A very long name for a tab of forty'),
        ],
      );
      await tester.pumpWidget(strip(repository));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('group-tabs-fold')));
      await settle(tester);
      expect(find.text('A very long name for…'), findsOneWidget);
    });

    testWidgets('the row scrolls sideways when it does not fit', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = FakeGroupTabsRepository(
        tabs: [
          for (var i = 0; i < 9; i++)
            sampleTab('t$i', 'events', 'Tab number $i'),
        ],
      );
      await tester.pumpWidget(strip(repository));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('group-tabs-fold')));
      await settle(tester);
      expect(find.byKey(const ValueKey('group-tab-t8')), findsNothing);
      await tester.drag(
        find.byKey(const ValueKey('group-tabs-row')),
        const Offset(-3000, 0),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('group-tab-t8')), findsOneWidget);
    });

    testWidgets('a chat that stays open stays open', (tester) async {
      final repository = FakeGroupTabsRepository(tabs: _threeTabs);
      await tester.pumpWidget(strip(repository));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('group-tabs-fold')));
      await settle(tester);
      // The chat page is rebuilt (a new strip, the same chat).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(strip(repository));
      await settle(tester);
      expect(find.byKey(const ValueKey('group-tabs-row')), findsOneWidget);
    });

    testWidgets('a read that fails shows nothing and does not break the chat', (
      tester,
    ) async {
      final repository = FakeGroupTabsRepository(tabs: _threeTabs)
        ..tabsError = StateError('offline');
      await tester.pumpWidget(strip(repository));
      await settle(tester);
      expect(find.byKey(const ValueKey('group-tabs-fold')), findsNothing);
    });

    testWidgets('the fold reads as a button with its state', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(strip(FakeGroupTabsRepository(tabs: _threeTabs)));
      await settle(tester);
      expect(find.bySemanticsLabel('Tabs, 3'), findsOneWidget);
      handle.dispose();
    });
  });

  group('the sheet', () {
    Future<void> open(
      WidgetTester tester,
      FakeGroupTabsRepository repository, {
      List<String>? opened,
      List<Override> overrides = const [],
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          repository,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showGroupTabsSheet(
                context,
                conversationId: 'g',
                title: 'Hike',
                circleId: 'c',
              ),
              child: const Text('open'),
            ),
          ),
          overrides: [
            groupTabKindRegistryProvider.overrideWithValue(
              opened == null
                  ? GroupTabKindRegistry(builtInGroupTabKinds)
                  : recordingRegistry(opened),
            ),
            ...overrides,
          ],
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    testWidgets('anyone can open a tab; the sheet closes behind it', (
      tester,
    ) async {
      final opened = <String>[];
      await open(
        tester,
        FakeGroupTabsRepository(tabs: _threeTabs, canManage: false),
        opened: opened,
      );
      expect(find.text('Only admins can change the tabs.'), findsOneWidget);
      expect(find.byKey(const ValueKey('group-tab-add')), findsNothing);
      expect(find.byKey(const ValueKey('group-tab-rename-t1')), findsNothing);

      await tester.tap(find.text('\u{1F4D8} House rules'));
      await settle(tester);
      expect(opened, ['note:n1']);
      expect(find.byKey(const ValueKey('group-tabs-list')), findsNothing);
    });

    testWidgets('an empty chat says what tabs are for', (tester) async {
      await open(tester, FakeGroupTabsRepository());
      expect(
        find.textContaining('No tabs yet. Pin a note, a list, a form'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('group-tab-add')), findsOneWidget);
    });

    testWidgets('a tab whose target is gone says so and is not a link', (
      tester,
    ) async {
      final opened = <String>[];
      await open(
        tester,
        FakeGroupTabsRepository(
          tabs: [sampleTab('t1', 'note', 'Old', target: 'n', available: false)],
        ),
        opened: opened,
      );
      expect(find.text('No longer available'), findsOneWidget);
      await tester.tap(find.text('Old'));
      await settle(tester);
      expect(opened, isEmpty);
    });

    testWidgets('an admin renames a tab', (tester) async {
      final repository = FakeGroupTabsRepository(tabs: _threeTabs);
      await open(tester, repository, opened: <String>[]);
      await tester.tap(find.byKey(const ValueKey('group-tab-rename-t2')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('group-tab-rename-field')),
        'Timetable',
      );
      await tester.tap(find.byKey(const ValueKey('group-tab-rename-save')));
      await settle(tester);
      expect(repository.items[1].title, 'Timetable');
      expect(find.text('Timetable'), findsOneWidget);
    });

    testWidgets('an admin removes a tab', (tester) async {
      final repository = FakeGroupTabsRepository(tabs: _threeTabs);
      await open(tester, repository, opened: <String>[]);
      await tester.tap(find.byKey(const ValueKey('group-tab-remove-t3')));
      await settle(tester);
      expect(repository.items.map((t) => t.id), ['t1', 't2']);
      expect(find.byKey(const ValueKey('group-tab-row-t3')), findsNothing);
    });

    testWidgets('tabs move up and down for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      final repository = FakeGroupTabsRepository(tabs: _threeTabs);
      await open(tester, repository, opened: <String>[]);
      final row = find.byKey(const ValueKey('group-tab-row-t3'));
      final data = tester.getSemantics(row);
      expect(data, isNotNull);
      // ignore: deprecated_member_use
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        tester.getSemantics(row).id,
        SemanticsAction.customAction,
        CustomSemanticsAction.getIdentifier(
          const CustomSemanticsAction(label: 'Move up'),
        ),
      );
      await settle(tester);
      expect(repository.items.map((t) => t.id), ['t1', 't3', 't2']);
      handle.dispose();
    });

    testWidgets('adding a link takes an address and a name', (tester) async {
      final repository = FakeGroupTabsRepository();
      await open(tester, repository);
      await tester.tap(find.byKey(const ValueKey('group-tab-add')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('group-tab-kind-link')));
      await settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('group-tab-link-address')),
        'javascript:alert(1)',
      );
      await tester.enterText(
        find.byKey(const ValueKey('group-tab-link-name')),
        'Bad',
      );
      await tester.tap(find.byKey(const ValueKey('group-tab-link-done')));
      await settle(tester);
      expect(
        find.text('Enter a web address that starts with https://'),
        findsOneWidget,
      );
      expect(repository.added, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('group-tab-link-address')),
        'example.com/rules',
      );
      await tester.enterText(
        find.byKey(const ValueKey('group-tab-link-name')),
        'Rules',
      );
      await tester.tap(find.byKey(const ValueKey('group-tab-link-done')));
      await settle(tester);
      expect(repository.added.single.kind, 'link');
      expect(repository.added.single.target, 'https://example.com/rules');
      expect(repository.added.single.title, 'Rules');
      expect(find.text('Rules'), findsOneWidget);
    });

    testWidgets('adding a note picks one of the chat\'s notes', (tester) async {
      final repository = FakeGroupTabsRepository();
      await open(
        tester,
        repository,
        overrides: [
          notesListProvider('g').overrideWith(
            (ref) async => [
              const NoteSummary(
                id: 'n1',
                conversationId: 'g',
                title: 'House rules',
                icon: '\u{1F4D8}',
                managersOnly: false,
                pinned: false,
                canEdit: true,
              ),
            ],
          ),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('group-tab-add')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('group-tab-kind-note')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('group-tab-pick-n1')));
      await settle(tester);
      expect(repository.added.single.kind, 'note');
      expect(repository.added.single.target, 'n1');
      expect(repository.added.single.title, 'House rules');
    });

    testWidgets('a chat with no lists says to make one first', (tester) async {
      final repository = FakeGroupTabsRepository();
      await open(
        tester,
        repository,
        overrides: [
          taskListsProvider(
            'g',
          ).overrideWith((ref) async => <TaskListSummary>[]),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('group-tab-add')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('group-tab-kind-list')));
      await settle(tester);
      expect(
        find.text('This chat has no lists yet. Make one from Lists first.'),
        findsOneWidget,
      );
    });

    testWidgets('forms are picked from the chat\'s forms; a closed one says '
        'so', (tester) async {
      final repository = FakeGroupTabsRepository()
        ..candidatesByKind['form'] = const [
          GroupTabCandidate(target: 'f1', title: 'Sign-up'),
          GroupTabCandidate(target: 'f2', title: 'Old form', closed: true),
        ];
      await open(tester, repository);
      await tester.tap(find.byKey(const ValueKey('group-tab-add')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('group-tab-kind-form')));
      await settle(tester);
      expect(find.text('Closed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group-tab-pick-f1')));
      await settle(tester);
      expect(repository.added.single.target, 'f1');
    });

    testWidgets('a kind with no target is added at once, once', (tester) async {
      final repository = FakeGroupTabsRepository();
      await open(tester, repository);
      await tester.tap(find.byKey(const ValueKey('group-tab-add')));
      await settle(tester);
      expect(find.byKey(const ValueKey('group-tab-kind-kb')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group-tab-kind-events')));
      await settle(tester);
      expect(repository.added.single.kind, 'events');
      expect(repository.added.single.target, isNull);
      expect(repository.added.single.title, 'Events');

      await tester.tap(find.byKey(const ValueKey('group-tab-add')));
      await settle(tester);
      expect(find.byKey(const ValueKey('group-tab-kind-events')), findsNothing);
    });

    testWidgets('twelve tabs is the most; Add is off and says why', (
      tester,
    ) async {
      final repository = FakeGroupTabsRepository(
        tabs: [
          for (var i = 0; i < maxGroupTabs; i++)
            sampleTab('t$i', 'link', 'Link $i', target: 'https://e.com/$i'),
        ],
      );
      await open(tester, repository);
      expect(find.text('A chat can have up to 12 tabs.'), findsOneWidget);
      final button = tester.widget<WeCordButton>(
        find.byKey(const ValueKey('group-tab-add')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a refused change tells the person and reads again', (
      tester,
    ) async {
      final repository = FakeGroupTabsRepository(tabs: _threeTabs);
      await open(tester, repository, opened: <String>[]);
      repository.canManage = false;
      await tester.tap(find.byKey(const ValueKey('group-tab-remove-t1')));
      await settle(tester);
      expect(repository.items, hasLength(3));
      expect(find.text('Only admins can change the tabs.'), findsWidgets);
    });
  });
}
