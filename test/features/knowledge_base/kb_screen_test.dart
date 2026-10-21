import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/knowledge_base/kb_models.dart';
import 'package:wecord/features/knowledge_base/kb_screen.dart';

import '../../mobile/phone_test_support.dart';
import 'kb_fakes.dart';

const _desktop = PhoneViewport(
  name: '1280x800',
  size: Size(1280, 800),
  devicePixelRatio: 1,
);

Future<KbWorld> _open(
  WidgetTester tester, {
  bool manager = true,
  PhoneViewport viewport = notchedPhone,
  String? pageId,
  void Function(KbWorld world)? prepare,
}) async {
  usePhoneViewport(tester, viewport);
  final world = KbWorld(manager: manager);
  prepare?.call(world);
  world.install();
  await pumpStandalone(
    tester,
    world.world,
    KnowledgeBaseScreen(circleId: 'circle-1', initialPageId: pageId),
  );
  return world;
}

Future<void> _openMenuOf(WidgetTester tester, String pageId) async {
  await tester.tap(find.byKey(ValueKey('kb-more-$pageId')));
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

void main() {
  testWidgets('the tree shows every page, what is limited and what to read', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('Knowledge base'), findsOneWidget);
    for (final title in [
      'Welcome',
      'Rules',
      'Posting',
      'Moderation',
      'Resources',
      'Guides',
      'Setup',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('Required reading'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Limited'), findsOneWidget);
    expect(
      find.text('1 page is required reading. Start with it.'),
      findsOneWidget,
    );
    // Pages inside another sit further right.
    final rules = tester.getTopLeft(find.text('Rules')).dx;
    final posting = tester.getTopLeft(find.text('Posting')).dx;
    final setup = tester.getTopLeft(find.text('Setup')).dx;
    expect(posting, greaterThan(rules));
    expect(setup, greaterThan(posting));
  });

  testWidgets('a page with pages inside collapses and expands', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('kb-toggle-p-rules')));
    await settle(tester);
    expect(find.text('Posting'), findsNothing);
    expect(find.text('Moderation'), findsNothing);
    expect(find.text('Rules'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kb-toggle-p-rules')));
    await settle(tester);
    expect(find.text('Posting'), findsOneWidget);
  });

  testWidgets('an empty knowledge base invites a manager to write', (
    tester,
  ) async {
    await _open(tester, prepare: (w) => w.knowledge.pages = []);
    expect(find.text('No pages yet'), findsOneWidget);
    expect(find.text('Add the first page'), findsOneWidget);
  });

  testWidgets('an empty knowledge base only says so to a member', (
    tester,
  ) async {
    await _open(tester, manager: false, prepare: (w) => w.knowledge.pages = []);
    expect(find.text('No pages yet'), findsOneWidget);
    expect(find.text('Add the first page'), findsNothing);
    expect(find.byKey(const ValueKey('kb-add-button')), findsNothing);
  });

  testWidgets('a page that cannot be loaded offers another try', (
    tester,
  ) async {
    final world = await _open(
      tester,
      prepare: (w) => w.knowledge.loadsFail = true,
    );
    expect(find.text('Could not load the pages.'), findsOneWidget);
    world.knowledge.loadsFail = false;
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('a member can read but gets no arranging tools', (tester) async {
    await _open(tester, manager: false);
    expect(find.byKey(const ValueKey('kb-add-button')), findsNothing);
    // No page is theirs to edit, so no options either.
    expect(find.byKey(const ValueKey('kb-more-p-rules')), findsNothing);
  });

  testWidgets('opening a page shows the editor without chat tools', (
    tester,
  ) async {
    final world = await _open(tester);
    await tester.tap(find.text('Welcome'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Start here'), findsOneWidget);
    expect(
      find.textContaining('Say hello in the welcome channel'),
      findsOneWidget,
    );
    // A page is not shared into a chat and has no comments.
    expect(find.byTooltip('Share in the chat'), findsNothing);
    expect(find.byKey(const ValueKey('note-comments-button')), findsNothing);
    expect(find.byTooltip('Version history'), findsOneWidget);
    // Opening it counts as reading it.
    expect(world.knowledge.calls, contains('read:p-welcome'));
    // Back returns to the tree.
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('Knowledge base'), findsOneWidget);
    expect(find.text('Resources'), findsOneWidget);
  });

  testWidgets('a page shows where it sits and the trail goes up', (
    tester,
  ) async {
    await _open(tester, pageId: 'p-setup');
    expect(find.byKey(const ValueKey('kb-trail')), findsOneWidget);
    expect(find.textContaining('Resources'), findsOneWidget);
    expect(find.textContaining('Guides'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kb-trail-p-guides')));
    await settle(tester);
    expect(find.byKey(const ValueKey('kb-trail')), findsOneWidget);
  });

  testWidgets('the page menu has what a manager can do, and exports', (
    tester,
  ) async {
    await _open(tester, pageId: 'p-rules');
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    for (final label in [
      'Export as a Markdown file',
      'Export as a PDF',
      'Copy as Markdown',
      'Add a page inside',
      'Move to…',
      'Move down',
      'Who can read and edit…',
      'Delete page',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Rules is not first, so it can move up; the chat note tools are absent.
    expect(find.text('Move up'), findsOneWidget);
    expect(find.text('Publish to the web…'), findsNothing);
    expect(find.text('Save as a template…'), findsNothing);
    expect(find.text('Pin to the top of the chat'), findsNothing);
  });

  testWidgets('a new top-level page is made from the plus button', (
    tester,
  ) async {
    final world = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('kb-add-button')));
    await settle(tester);
    expect(find.text('New page'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('kb-new-page-title')),
      'Events',
    );
    await tester.tap(find.byKey(const ValueKey('kb-new-page-create')));
    await settle(tester);
    expect(world.knowledge.calls, contains('create:top:Events'));
    // The new page opens, in the editor.
    expect(find.byTooltip('Version history'), findsOneWidget);
  });

  testWidgets('a page is added inside another from its options', (
    tester,
  ) async {
    final world = await _open(tester);
    await _openMenuOf(tester, 'p-resources');
    await tester.tap(find.text('Add a page inside'));
    await settle(tester);
    expect(find.text('New page inside'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('kb-new-page-title')),
      'Links',
    );
    await tester.tap(find.byKey(const ValueKey('kb-new-page-create')));
    await settle(tester);
    expect(world.knowledge.calls, contains('create:p-resources:Links'));
  });

  testWidgets('a page moves up and down among its neighbours', (tester) async {
    final world = await _open(tester);
    await _openMenuOf(tester, 'p-rules');
    await tester.tap(find.text('Move up'));
    await settle(tester);
    expect(world.knowledge.calls, contains('move:p-rules:top:p-welcome'));
    await _openMenuOf(tester, 'p-rules');
    await tester.tap(find.text('Move down'));
    await settle(tester);
    expect(world.knowledge.calls, contains('move:p-rules:top:p-resources'));
  });

  testWidgets('the first page cannot go up and the last cannot go down', (
    tester,
  ) async {
    await _open(tester);
    await _openMenuOf(tester, 'p-welcome');
    expect(find.text('Move up'), findsNothing);
    expect(find.text('Move down'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    await _openMenuOf(tester, 'p-resources');
    expect(find.text('Move down'), findsNothing);
    expect(find.text('Move up'), findsOneWidget);
  });

  testWidgets('moving to another place offers only places that fit', (
    tester,
  ) async {
    final world = await _open(tester);
    await _openMenuOf(tester, 'p-guides');
    await tester.tap(find.text('Move to…'));
    await settle(tester);
    // Not inside itself (Guides, Setup) ...
    expect(find.byKey(const ValueKey('kb-move-p-guides')), findsNothing);
    expect(find.byKey(const ValueKey('kb-move-p-setup')), findsNothing);
    // ... but the top level and the other pages.
    expect(find.byKey(const ValueKey('kb-move-top')), findsOneWidget);
    expect(find.byKey(const ValueKey('kb-move-p-rules')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kb-move-p-rules')));
    await settle(tester);
    expect(world.knowledge.calls, contains('move:p-guides:p-rules:last'));
  });

  testWidgets('a page is not moved where it would nest too deep', (
    tester,
  ) async {
    // Resources > Guides > Setup is three deep: Resources (with two levels
    // below it) cannot go inside Setup's level 4 or 5 neighbours.
    await _open(
      tester,
      prepare: (w) => w.knowledge.pages = [
        ...sampleKbPages(),
        kbPage('p-l4', 'Level four', parent: 'p-setup'),
        kbPage('p-l5', 'Level five', parent: 'p-l4'),
      ],
    );
    await _openMenuOf(tester, 'p-welcome');
    await tester.tap(find.text('Move to…'));
    await settle(tester);
    // Welcome has nothing below it: it fits anywhere but under level five.
    expect(find.byKey(const ValueKey('kb-move-p-l4')), findsOneWidget);
    expect(find.byKey(const ValueKey('kb-move-p-l5')), findsNothing);
  });

  testWidgets('deleting asks first and says what happens to the pages inside', (
    tester,
  ) async {
    final world = await _open(tester);
    await _openMenuOf(tester, 'p-rules');
    await tester.tap(find.text('Delete page'));
    await settle(tester);
    expect(find.text('Delete this page?'), findsOneWidget);
    expect(
      find.textContaining('The 2 pages inside it move up'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(world.knowledge.calls.where((c) => c.startsWith('delete')), isEmpty);

    await _openMenuOf(tester, 'p-rules');
    await tester.tap(find.text('Delete page'));
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    expect(world.knowledge.calls, contains('delete:p-rules'));
    // The pages inside stay, one level up.
    expect(find.text('Posting'), findsOneWidget);
    expect(find.byKey(const ValueKey('kb-row-p-rules')), findsNothing);
  });

  testWidgets('a refusal because of rank is explained', (tester) async {
    final world = await _open(tester);
    world.knowledge.failWith = PostgrestException(
      message: 'A higher role limited this page',
      code: '42501',
    );
    await _openMenuOf(tester, 'p-rules');
    await tester.tap(find.text('Delete page'));
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    expect(
      find.text('A higher role limited this page, so you cannot change it.'),
      findsOneWidget,
    );
  });

  testWidgets('who can read and edit: choosing roles saves them', (
    tester,
  ) async {
    final world = await _open(tester);
    await _openMenuOf(tester, 'p-rules');
    await tester.tap(find.text('Who can read and edit…'));
    await settle(tester);
    expect(find.text('Who can read'), findsOneWidget);
    expect(find.text('Who can edit'), findsOneWidget);
    // Everyone by default; picking some roles asks for at least one.
    await tester.tap(find.byKey(const ValueKey('kb-view-roles')));
    await settle(tester);
    expect(find.text('Moderators'), findsOneWidget);
    final save = find.byKey(const ValueKey('kb-access-save'));
    await _scrollTo(tester, save);
    await tester.tap(save);
    await settle(tester);
    expect(world.knowledge.lastAccess, isNull, reason: 'no role chosen yet');

    await tester.tap(find.byKey(const ValueKey('kb-view-role-role-mod')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('kb-edit-roles')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('kb-edit-role-role-crew')));
    await settle(tester);
    await _scrollTo(tester, save);
    await tester.tap(save);
    await settle(tester);
    final access = world.knowledge.lastAccess!;
    expect(access.pageId, 'p-rules');
    expect(access.viewRoleIds, ['role-mod']);
    expect(access.editRoleIds, ['role-crew']);
  });

  testWidgets('a page a higher role limited can be looked at, not changed', (
    tester,
  ) async {
    final world = await _open(
      tester,
      prepare: (w) => w.knowledge.access = const KbPageAccess(
        viewRoleIds: ['role-mod'],
        locked: true,
        roles: [KbRole(id: 'role-mod', name: 'Moderators')],
      ),
    );
    await _openMenuOf(tester, 'p-rules');
    await tester.tap(find.text('Who can read and edit…'));
    await settle(tester);
    expect(find.byKey(const ValueKey('kb-access-locked')), findsOneWidget);
    final save = find.byKey(const ValueKey('kb-access-save'));
    await _scrollTo(tester, save);
    await tester.tap(save, warnIfMissed: false);
    await settle(tester);
    expect(world.knowledge.lastAccess, isNull);
    // The roles are shown for looking at, but cannot be toggled.
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('kb-view-role-role-mod')),
    );
    await tester.tap(
      find.byKey(const ValueKey('kb-view-role-role-mod')),
      warnIfMissed: false,
    );
    await settle(tester);
    expect(find.text('Moderators'), findsOneWidget);
  });

  testWidgets('searching lists the pages found, with a snippet', (
    tester,
  ) async {
    final world = await _open(
      tester,
      prepare: (w) => w.knowledge.hits = const [
        KbSearchHit(
          id: 'p-rules',
          title: 'Rules',
          snippet: 'Be kind. No spam. Budget talk stays in the finance room.',
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('kb-search-button')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('kb-search-field')), 'b');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Type at least two letters.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('kb-search-field')),
      'budget',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(world.knowledge.calls, contains('search:budget'));
    expect(find.textContaining('Budget talk'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kb-hit-p-rules')));
    await settle(tester);
    expect(find.byTooltip('Version history'), findsOneWidget);
  });

  testWidgets('a search with no result says so', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('kb-search-button')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('kb-search-field')),
      'zebra',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.textContaining('No page matches'), findsOneWidget);
    // Closing the search brings the tree back.
    await tester.tap(find.byKey(const ValueKey('kb-search-button')));
    await settle(tester);
    expect(find.text('Resources'), findsOneWidget);
  });

  testWidgets('on a wide screen the tree sits beside the open page', (
    tester,
  ) async {
    await _open(tester, viewport: _desktop);
    expect(find.text('Pick a page'), findsOneWidget);
    await tester.tap(find.text('Welcome'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
    // Both the tree and the page are on screen.
    expect(find.text('Resources'), findsOneWidget);
    expect(find.text('Start here'), findsOneWidget);
    expect(find.text('Pick a page'), findsNothing);
  });

  testWidgets('a page opened by link opens straight away', (tester) async {
    final world = await _open(tester, pageId: 'p-welcome');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Start here'), findsOneWidget);
    expect(world.knowledge.calls, contains('read:p-welcome'));
  });

  testWidgets('a change by someone else refreshes the tree', (tester) async {
    final world = await _open(tester);
    expect(find.text('Events'), findsNothing);
    world.knowledge.pages = [
      ...world.knowledge.pages,
      kbPage('p-events', 'Events', position: 9),
    ];
    world.knowledge.changesController.add(null);
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.text('Events'), findsOneWidget);
  });
}
