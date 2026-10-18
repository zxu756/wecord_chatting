import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chat_folders/chat_folder.dart';
import 'package:wecord/features/chat_folders/chat_folders_repository.dart';
import 'package:wecord/features/chat_folders/folded_folder_row.dart';
import 'package:wecord/features/home/home_sidebar.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';
import 'chat_folders_fakes.dart';

void main() {
  late PhoneWorld world;
  late FakeChatFoldersRepository folders;

  Future<void> openHome(
    WidgetTester tester, {
    List<ChatFolder> existing = const [],
    bool wide = false,
  }) async {
    world = PhoneWorld();
    folders = FakeChatFoldersRepository(existing);
    world.chats.conversations = folderChats();
    world.extraOverrides = chatFoldersOverrides(folders);
    if (wide) {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    } else {
      usePhoneViewport(tester, notchedPhone);
    }
    await world.open(tester, '/home');
  }

  Finder row(String id) => find.byKey(ValueKey('home-dm-$id'));
  Finder chip(String id) => find.byKey(ValueKey('chat-folder-$id'));

  /// The strip scrolls sideways: bring [finder] into view first.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  Future<void> select(WidgetTester tester, String id) async {
    await reveal(tester, chip(id));
    await tester.tap(chip(id));
    await settle(tester);
  }

  group('on the phone', () {
    testWidgets('the strip lists All, Unread and each folder', (tester) async {
      await openHome(tester, existing: [workFolder, groupsFolder]);

      expect(find.byKey(const ValueKey('chat-folder-strip')), findsOneWidget);
      expect(chip('all'), findsOneWidget);
      expect(chip('unread'), findsOneWidget);
      expect(chip('folder-work'), findsOneWidget);
      expect(chip('folder-groups'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-folder-new')), findsOneWidget);
      // All is selected, with every chat listed and the friends row above.
      expect(find.byKey(const ValueKey('phone-friends-row')), findsOneWidget);
      for (final id in ['dm-bart', 'group-work', 'group-hobby', 'dm-grace']) {
        expect(row(id), findsOneWidget);
      }
    });

    testWidgets('counts are gray and a mention is a red dot', (tester) async {
      await openHome(tester, existing: [workFolder, groupsFolder]);
      final c = tester.element(chip('all')).tokens.colors;

      CountBadge badgeIn(String id) => tester.widget<CountBadge>(
        find.descendant(
          of: chip(id),
          matching: find.byWidgetPredicate(
            (widget) => widget is CountBadge && widget.count != null,
          ),
        ),
      );

      // Work: group-work (3 unread, mentions me); dm-grace is read.
      final work = badgeIn('folder-work');
      expect(work.count, 1);
      expect(work.tone, BadgeTone.unread);
      // Groups: work crew + hobby club count; the muted group is quiet.
      expect(badgeIn('folder-groups').count, 2);
      // Unread: dm-bart, work crew, hobby club (the muted chat is quiet).
      expect(badgeIn('unread').count, 3);

      // The pill is painted with the gray token, never the red one.
      Finder painted(Color color) => find.descendant(
        of: chip('folder-work'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color == color,
        ),
      );
      expect(painted(c.badgeUnread), findsOneWidget);
      expect(c.badgeUnread, isNot(c.badgeMention));

      // The mention dot is the red one, only on folders that have a mention.
      Finder dotIn(String id) => find.descendant(
        of: chip(id),
        matching: find.byKey(const ValueKey('chat-folder-mention-dot')),
      );
      expect(dotIn('folder-work'), findsOneWidget);
      expect(dotIn('folder-groups'), findsOneWidget);
      expect(dotIn('unread'), findsOneWidget);
      expect(
        tester.widget<CountBadge>(dotIn('folder-work')).tone,
        BadgeTone.mention,
      );
      expect(dotIn('all'), findsNothing);
    });

    testWidgets('a folder without a mention has no red dot', (tester) async {
      await openHome(
        tester,
        existing: [
          const ChatFolder(
            id: 'folder-dm',
            name: 'People',
            sortKey: 1,
            includeTypes: {ConversationType.direct},
          ),
        ],
      );
      expect(
        find.descendant(
          of: chip('folder-dm'),
          matching: find.byKey(const ValueKey('chat-folder-mention-dot')),
        ),
        findsNothing,
      );
    });

    testWidgets('choosing a folder filters the list, pinned chats first', (
      tester,
    ) async {
      final pinnedWork = workFolder.copyWith(
        includeIds: {'group-work', 'dm-grace', 'dm-bart'},
      );
      await openHome(tester, existing: [pinnedWork]);

      await select(tester, 'folder-work');
      expect(row('group-work'), findsOneWidget);
      expect(row('dm-grace'), findsOneWidget);
      expect(row('dm-bart'), findsOneWidget);
      expect(row('group-hobby'), findsNothing);
      // Pinned first, then the list's own order.
      double top(String id) => tester.getTopLeft(row(id)).dy;
      expect(top('dm-bart'), lessThan(top('group-work')));
      expect(top('group-work'), lessThan(top('dm-grace')));

      await select(tester, 'all');
      expect(row('group-hobby'), findsOneWidget);
    });

    testWidgets('Unread lists what has something new', (tester) async {
      await openHome(tester, existing: [workFolder]);
      await select(tester, 'unread');
      expect(row('dm-bart'), findsOneWidget);
      expect(row('group-work'), findsOneWidget);
      expect(row('group-quiet'), findsOneWidget);
      expect(row('dm-grace'), findsNothing);
    });

    testWidgets('an empty folder says so and offers to edit it', (
      tester,
    ) async {
      await openHome(
        tester,
        existing: [const ChatFolder(id: 'folder-empty', name: 'Empty')],
      );
      await select(tester, 'folder-empty');
      expect(find.byKey(const ValueKey('chat-folder-empty')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-folder-empty-edit')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('chat-folder-name-field')),
        findsOneWidget,
      );
    });

    testWidgets('a folder is made from a template and then shown', (
      tester,
    ) async {
      await openHome(tester);
      await reveal(tester, find.byKey(const ValueKey('chat-folder-new')));
      await tester.tap(find.byKey(const ValueKey('chat-folder-new')));
      await settle(tester);
      expect(find.text('New folder'), findsWidgets);

      await tester.tap(
        find.byKey(const ValueKey('chat-folder-template-groups')),
      );
      await settle(tester);
      // The template filled the form in.
      final field = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('chat-folder-name-field')),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.controller.text, 'Groups');

      await tester.tap(find.byKey(const ValueKey('chat-folder-save')));
      await settle(tester);

      expect(folders.created, hasLength(1));
      expect(folders.created.single.includeTypes, {ConversationType.group});
      expect(folders.created.single.sortKey, 1);
      // The new folder is selected and filters the list.
      expect(chip(folders.created.single.id), findsOneWidget);
      expect(row('group-work'), findsOneWidget);
      expect(row('dm-bart'), findsNothing);
    });

    testWidgets('the editor refuses a blank name and says why a save failed', (
      tester,
    ) async {
      await openHome(tester);
      await reveal(tester, find.byKey(const ValueKey('chat-folder-new')));
      await tester.tap(find.byKey(const ValueKey('chat-folder-new')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('chat-folder-save')));
      await settle(tester);
      expect(folders.created, isEmpty);
      expect(
        find.textContaining('Give the folder a name of up to 30'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('chat-folder-name-field')),
        'Family',
      );
      folders.failWrites = const ChatFolderException(ChatFolderProblem.limit);
      await tester.tap(find.byKey(const ValueKey('chat-folder-save')));
      await settle(tester);
      expect(find.byKey(const ValueKey('chat-folder-error')), findsOneWidget);
      expect(find.text('You can have up to 20 folders.'), findsOneWidget);
    });

    testWidgets('twenty folders leave no room for a new chip', (tester) async {
      await openHome(
        tester,
        existing: [
          for (var i = 1; i <= maxChatFolders; i++)
            ChatFolder(id: 'f$i', name: 'Folder $i', sortKey: i),
        ],
      );
      expect(find.byKey(const ValueKey('chat-folder-new')), findsNothing);
    });

    testWidgets('holding a folder edits it, and it can be deleted', (
      tester,
    ) async {
      await openHome(tester, existing: [workFolder]);
      await tester.longPress(chip('folder-work'));
      await settle(tester);
      expect(find.text('Edit folder'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('chat-folder-name-field')),
        'Office',
      );
      await tester.tap(find.byKey(const ValueKey('chat-folder-save')));
      await settle(tester);
      expect(folders.updated.single.name, 'Office');
      expect(find.text('Office'), findsWidgets);

      await tester.longPress(chip('folder-work'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('chat-folder-delete')));
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('chat-folder-delete-confirm')),
      );
      await settle(tester);
      expect(folders.deleted, ['folder-work']);
      expect(chip('folder-work'), findsNothing);
    });

    testWidgets('a conversation can be added to a folder and taken out', (
      tester,
    ) async {
      await openHome(tester, existing: [workFolder]);
      await tester.longPress(row('group-hobby'));
      await settle(tester);
      expect(find.text('Add to folder…'), findsOneWidget);
      await tester.tap(find.text('Add to folder…'));
      await settle(tester);

      final entry = find.byKey(const ValueKey('add-to-folder-folder-work'));
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await settle(tester);
      expect(folders.updated.last.includeIds, contains('group-hobby'));
      // The folder now lists the chat.
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      await select(tester, 'folder-work');
      expect(row('group-hobby'), findsOneWidget);

      // And again to take it out.
      await tester.longPress(row('group-hobby'));
      await settle(tester);
      await tester.tap(find.text('Add to folder…'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('add-to-folder-folder-work')));
      await settle(tester);
      expect(folders.updated.last.includeIds, isNot(contains('group-hobby')));
    });

    testWidgets('a chat the rules take is excluded, not just unlisted', (
      tester,
    ) async {
      await openHome(tester, existing: [groupsFolder]);
      await tester.longPress(row('group-hobby'));
      await settle(tester);
      await tester.tap(find.text('Add to folder…'));
      await settle(tester);
      expect(find.text('Included by its rules'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('add-to-folder-folder-groups')),
      );
      await settle(tester);
      expect(folders.updated.last.excludeIds, {'group-hobby'});
    });

    testWidgets('the sheet can start a folder with the chat in it', (
      tester,
    ) async {
      await openHome(tester);
      await tester.longPress(row('dm-grace'));
      await settle(tester);
      await tester.tap(find.text('Add to folder…'));
      await settle(tester);
      expect(find.byKey(const ValueKey('add-to-folder-empty')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('add-to-folder-new')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('chat-folder-name-field')),
        'Friends',
      );
      await tester.tap(find.byKey(const ValueKey('chat-folder-save')));
      await settle(tester);
      expect(folders.created.single.includeIds, {'dm-grace'});
    });

    testWidgets('changes made on another device show up on their own', (
      tester,
    ) async {
      await openHome(tester, existing: [workFolder]);
      expect(chip('folder-groups'), findsNothing);
      folders.changeElsewhere([workFolder, groupsFolder]);
      await settle(tester);
      expect(chip('folder-groups'), findsOneWidget);

      folders.changeElsewhere([groupsFolder]);
      await settle(tester);
      expect(chip('folder-work'), findsNothing);
    });

    testWidgets('a folder deleted elsewhere while open falls back to All', (
      tester,
    ) async {
      await openHome(tester, existing: [workFolder, groupsFolder]);
      await select(tester, 'folder-work');
      expect(row('group-hobby'), findsNothing);
      folders.changeElsewhere([groupsFolder]);
      await settle(tester);
      expect(row('group-hobby'), findsOneWidget);
    });

    testWidgets('chats are only fetched, never created, by the strip', (
      tester,
    ) async {
      await openHome(tester, existing: [workFolder]);
      expect(folders.loads, 1);
      expect(folders.created, isEmpty);
    });
  });

  group('folded group chats', () {
    const folded = ChatFolder(
      id: 'folder-fold',
      name: 'Folded group chats',
      icon: 'people',
      sortKey: 1,
      includeIds: {'group-hobby', 'group-quiet'},
      folded: true,
    );

    testWidgets('are one row under All, and open as a folder', (tester) async {
      await openHome(tester, existing: [folded]);

      final foldedRow = find.byKey(const ValueKey('folded-folder-row'));
      expect(foldedRow, findsOneWidget);
      expect(row('group-hobby'), findsNothing);
      expect(row('group-quiet'), findsNothing);
      // The others stay.
      expect(row('group-work'), findsOneWidget);
      expect(row('dm-grace'), findsOneWidget);
      // The newest folded chat is previewed, and the unread chats counted
      // in gray (the muted one is quiet).
      expect(find.textContaining('Photos from Saturday'), findsOneWidget);
      final count = tester.widget<CountBadge>(
        find.byKey(const ValueKey('folded-folder-count')),
      );
      expect(count.count, 1);
      expect(count.tone, BadgeTone.unread);
      expect(find.byKey(const ValueKey('folded-folder-mention')), findsNothing);

      await tester.tap(foldedRow);
      await settle(tester);
      expect(row('group-hobby'), findsOneWidget);
      expect(row('group-quiet'), findsOneWidget);
      expect(row('group-work'), findsNothing);
      expect(foldedRow, findsNothing);

      await select(tester, 'all');
      expect(foldedRow, findsOneWidget);
    });

    testWidgets('show a red dot when a folded chat mentions me', (
      tester,
    ) async {
      await openHome(
        tester,
        existing: [
          folded.copyWith(includeIds: {'group-work', 'group-hobby'}),
        ],
      );
      expect(
        tester
            .widget<CountBadge>(
              find.byKey(const ValueKey('folded-folder-mention')),
            )
            .tone,
        BadgeTone.mention,
      );
    });

    testWidgets('read as one entry by a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      await openHome(tester, existing: [folded]);
      final node = tester.getSemantics(
        find.byKey(const ValueKey('folded-folder-row')),
      );
      expect(node.label, contains('Folded group chats'));
      expect(node.label, contains('2 chats'));
      expect(node.label, contains('1 unread'));
      expect(node.hint, 'Opens the folder');
      semantics.dispose();
    });

    testWidgets('a pinned chat is not folded', (tester) async {
      await openHome(
        tester,
        existing: [
          folded.copyWith(includeIds: {'group-hobby', 'dm-bart'}),
        ],
      );
      expect(row('dm-bart'), findsOneWidget);
      expect(row('group-hobby'), findsNothing);
    });
  });

  group('for screen readers', () {
    testWidgets('chips say what they hold and which is selected', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openHome(tester, existing: [workFolder]);

      final all = tester.getSemantics(chip('all'));
      expect(all.label, 'All');
      expect(
        all.getSemanticsData().flagsCollection.isSelected,
        isNot(Tristate.none),
      );

      final work = tester.getSemantics(chip('folder-work'));
      expect(work.label, 'Work, 1 unread, You are mentioned');
      expect(work.hint, 'Hold to edit this folder');
      // Holding it is an action a screen reader can run.
      expect(
        work.getSemanticsData().hasAction(SemanticsAction.longPress),
        isTrue,
      );
      expect(
        tester.getSemantics(chip('unread')).label,
        'Unread, 3 unread, You are mentioned',
      );

      await select(tester, 'folder-work');
      final selectedWork = tester.getSemantics(chip('folder-work'));
      expect(
        selectedWork.getSemanticsData().flagsCollection.isSelected,
        Tristate.isTrue,
      );
      semantics.dispose();
    });

    testWidgets('the strip is a labelled group', (tester) async {
      final semantics = tester.ensureSemantics();
      await openHome(tester, existing: [workFolder]);
      expect(find.bySemanticsLabel('Chat folders'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('on a wide screen', () {
    testWidgets('the sidebar has the same chips above the chat list', (
      tester,
    ) async {
      await openHome(tester, existing: [workFolder, groupsFolder], wide: true);

      final sidebar = find.byType(HomeSidebar);
      expect(
        find.descendant(of: sidebar, matching: chip('folder-work')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sidebar, matching: chip('all')),
        findsOneWidget,
      );
      // The chips sit above the first conversation row.
      expect(
        tester.getTopLeft(chip('all')).dy,
        lessThan(tester.getTopLeft(row('dm-bart')).dy),
      );

      await select(tester, 'folder-groups');
      expect(row('group-work'), findsOneWidget);
      expect(row('dm-bart'), findsNothing);
    });

    testWidgets('right-clicking a chat offers Add to folder', (tester) async {
      await openHome(tester, existing: [workFolder], wide: true);
      await tester.tap(row('group-hobby'), buttons: kSecondaryButton);
      await settle(tester);
      expect(find.text('Add to folder…'), findsOneWidget);
    });

    testWidgets('right-clicking a folder edits it', (tester) async {
      await openHome(tester, existing: [workFolder], wide: true);
      await reveal(tester, chip('folder-work'));
      await tester.tap(chip('folder-work'), buttons: kSecondaryButton);
      await settle(tester);
      expect(find.text('Edit folder'), findsOneWidget);
    });

    testWidgets('folded group chats are one row in the sidebar too', (
      tester,
    ) async {
      await openHome(
        tester,
        existing: [
          const ChatFolder(
            id: 'folder-fold',
            name: 'Folded group chats',
            sortKey: 1,
            includeIds: {'group-hobby', 'group-quiet'},
            folded: true,
          ),
        ],
        wide: true,
      );
      final foldedRow = find.descendant(
        of: find.byType(HomeSidebar),
        matching: find.byType(FoldedFolderRow),
      );
      expect(foldedRow, findsOneWidget);
      expect(row('group-hobby'), findsNothing);
      await tester.tap(foldedRow);
      await settle(tester);
      expect(row('group-hobby'), findsOneWidget);
    });
  });

  group('with the other list features', () {
    testWidgets('pinned, muted and marked-unread chats keep their marks', (
      tester,
    ) async {
      await openHome(tester, existing: [groupsFolder]);
      await select(tester, 'folder-groups');
      expect(
        find.descendant(
          of: row('group-quiet'),
          matching: find.byIcon(Icons.notifications_off_outlined),
        ),
        findsOneWidget,
      );
      // Mark unread still works from inside a folder.
      await tester.longPress(row('group-hobby'));
      await settle(tester);
      expect(find.text('Mark read'), findsOneWidget);
      expect(find.text('Pin chat'), findsOneWidget);
      expect(find.text('Mute'), findsOneWidget);
    });
  });
}
