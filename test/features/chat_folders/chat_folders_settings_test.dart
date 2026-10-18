import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chat_folders/chat_folder.dart';
import 'package:wecord/features/chat_folders/chat_folder_editor.dart';
import 'package:wecord/features/chat_folders/chat_folders_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../mobile/phone_test_support.dart';
import 'chat_folders_fakes.dart';

void main() {
  late PhoneWorld world;
  late FakeChatFoldersRepository folders;

  Future<void> openPage(
    WidgetTester tester, {
    List<ChatFolder> existing = const [],
  }) async {
    world = PhoneWorld();
    folders = FakeChatFoldersRepository(existing);
    world.chats.conversations = folderChats();
    world.extraOverrides = chatFoldersOverrides(folders);
    usePhoneViewport(tester, notchedPhone);
    await world.open(tester, '/me');
    final tile = find.byKey(const ValueKey('chat-folders-tile'));
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    // Between the title and the floating user panel.
    final y = tester.getCenter(tile).dy;
    if (y < 150 || y > 600) {
      await tester.drag(find.byType(Scrollable).first, Offset(0, 350 - y));
      await settle(tester);
    }
    await tester.tap(tile);
    await settle(tester);
  }

  /// The editor's form is a lazy list: scroll down to [finder].
  Future<void> inEditor(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      150,
      scrollable: find
          .descendant(
            of: find.byType(ChatFolderEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder rowOf(String id) => find.byKey(ValueKey('chat-folder-row-$id'));

  testWidgets('Settings -> Chats leads to the page', (tester) async {
    await openPage(tester);
    expect(find.byType(ChatFoldersScreen), findsOneWidget);
    expect(find.text('Chat folders'), findsWidgets);
    expect(find.byKey(const ValueKey('chat-folders-empty')), findsOneWidget);
  });

  testWidgets('templates start a new folder', (tester) async {
    await openPage(tester);
    for (final name in [
      'Unread (not muted)',
      'Groups',
      'Direct messages',
      'Muted',
      'Folded group chats',
    ]) {
      expect(find.text(name), findsWidgets);
    }

    final groups = find.byKey(
      const ValueKey('chat-folder-template-row-groups'),
    );
    await tester.ensureVisible(groups);
    await tester.tap(groups);
    await settle(tester);
    final name = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('chat-folder-name-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(name.controller.text, 'Groups');
    await tester.tap(find.byKey(const ValueKey('chat-folder-save')));
    await settle(tester);

    expect(folders.created.single.includeTypes, {ConversationType.group});
    expect(rowOf(folders.created.single.id), findsOneWidget);
    expect(find.text('Groups'), findsWidgets);
  });

  testWidgets('rows say what each folder takes', (tester) async {
    await openPage(
      tester,
      existing: [
        workFolder,
        groupsFolder.copyWith(onlyUnread: true, excludeMuted: true),
      ],
    );
    expect(find.text('2 picked'), findsOneWidget);
    expect(find.text('Groups · Unread only · Not muted'), findsOneWidget);
  });

  testWidgets('a folder is edited from its row', (tester) async {
    await openPage(tester, existing: [workFolder]);
    await tester.tap(rowOf('folder-work'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('chat-folder-name-field')),
      'Day job',
    );
    // Unread only, hide muted chats, and take direct messages by kind.
    await tester.tap(find.byKey(const ValueKey('chat-folder-only-unread')));
    await tester.tap(find.byKey(const ValueKey('chat-folder-direct')));
    await tester.tap(find.byKey(const ValueKey('chat-folder-muted-hide')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('chat-folder-save')));
    await settle(tester);

    final saved = folders.updated.single;
    expect(saved.name, 'Day job');
    expect(saved.onlyUnread, true);
    expect(saved.includeTypes, {ConversationType.direct});
    expect(saved.excludeMuted, true);
    expect(saved.onlyMuted, false);
    // The picked chats stay.
    expect(saved.includeIds, {'group-work', 'dm-grace'});
    expect(find.text('Day job'), findsOneWidget);
  });

  testWidgets('chats are picked and left out from the editor', (tester) async {
    await openPage(tester, existing: [groupsFolder]);
    await tester.tap(rowOf('folder-groups'));
    await settle(tester);

    final include = find.byKey(const ValueKey('chat-folder-include'));
    await inEditor(tester, include);
    await tester.tap(include);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('chat-pick-dm-grace')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('chat-picker-done')));
    await settle(tester);
    expect(find.text('1 chat'), findsOneWidget);

    final exclude = find.byKey(const ValueKey('chat-folder-exclude'));
    await inEditor(tester, exclude);
    await tester.tap(exclude);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('chat-pick-group-quiet')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('chat-picker-done')));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('chat-folder-save')));
    await settle(tester);
    expect(folders.updated.single.includeIds, {'dm-grace'});
    expect(folders.updated.single.excludeIds, {'group-quiet'});
  });

  testWidgets('only one folder can fold', (tester) async {
    await openPage(
      tester,
      existing: [workFolder.copyWith(folded: true), groupsFolder],
    );
    await tester.tap(rowOf('folder-groups'));
    await settle(tester);
    final fold = find.byKey(const ValueKey('chat-folder-folded'));
    await inEditor(tester, fold);
    expect(
      find.text(
        'Only one folder can be folded. Turn it off in the other folder first.',
      ),
      findsOneWidget,
    );
    await tester.tap(fold);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('chat-folder-save')));
    await settle(tester);
    expect(folders.updated.single.folded, false);
  });

  testWidgets('dragging a handle saves the new order', (tester) async {
    await openPage(tester, existing: [workFolder, groupsFolder]);
    final handle = find.descendant(
      of: rowOf('folder-work'),
      matching: find.byIcon(Icons.drag_handle_rounded),
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await settle(tester);

    expect(folders.reorders.single, ['folder-groups', 'folder-work']);
    expect(
      tester.getTopLeft(rowOf('folder-groups')).dy,
      lessThan(tester.getTopLeft(rowOf('folder-work')).dy),
    );
  });

  testWidgets('a screen reader can move a row up and down', (tester) async {
    final semantics = tester.ensureSemantics();
    await openPage(tester, existing: [workFolder, groupsFolder]);
    final data = tester.getSemantics(rowOf('folder-work')).getSemanticsData();
    // Move down and to the end, from the list itself.
    expect(data.customSemanticsActionIds, isNotEmpty);
    semantics.dispose();
  });

  testWidgets('a failed reorder says so and keeps the old order', (
    tester,
  ) async {
    await openPage(tester, existing: [workFolder, groupsFolder]);
    folders.failWrites = StateError('offline');
    final handle = find.descendant(
      of: rowOf('folder-work'),
      matching: find.byIcon(Icons.drag_handle_rounded),
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await settle(tester);
    expect(find.text('Could not change the order. Try again.'), findsOneWidget);
    expect(
      tester.getTopLeft(rowOf('folder-work')).dy,
      lessThan(tester.getTopLeft(rowOf('folder-groups')).dy),
    );
  });

  testWidgets('at twenty folders nothing offers a twenty-first', (
    tester,
  ) async {
    await openPage(
      tester,
      existing: [
        for (var i = 1; i <= maxChatFolders; i++)
          ChatFolder(id: 'f$i', name: 'Folder $i', sortKey: i),
      ],
    );
    expect(find.byKey(const ValueKey('chat-folders-new')), findsNothing);
    expect(find.text('Start from a template'), findsNothing);
  });

  testWidgets('a change from another device shows on the page', (tester) async {
    await openPage(tester, existing: [workFolder]);
    expect(rowOf('folder-groups'), findsNothing);
    folders.changeElsewhere([workFolder, groupsFolder]);
    await settle(tester);
    expect(rowOf('folder-groups'), findsOneWidget);
  });
}
