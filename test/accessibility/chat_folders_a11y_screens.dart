// The chat folder screens, for the accessibility guard (guidelines_test.dart)
// and the accessibility screenshot tool: the strip on Home (phone and
// desktop), the folded group chats row, the editor, "Add to folder", the
// chat picker and Settings -> Chats -> Chat folders.
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chat_folders/chat_folder.dart';
import 'package:wecord/features/chat_folders/chat_folder_editor.dart';

import '../features/chat_folders/chat_folders_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

const _foldedFolder = ChatFolder(
  id: 'folder-fold',
  name: 'Folded group chats',
  icon: 'people',
  sortKey: 3,
  includeIds: {'group-hobby', 'group-quiet'},
  folded: true,
);

const _folders = [workFolder, groupsFolder];

/// Home with folders and the chats they sort.
void _foldersWorld(PhoneWorld world, {List<ChatFolder> folders = _folders}) {
  world.chats.conversations = folderChats();
  world.extraOverrides = chatFoldersOverrides(
    FakeChatFoldersRepository(folders),
  );
}

Future<void> _revealChip(WidgetTester tester, String id) async {
  final chip = find.byKey(ValueKey('chat-folder-$id'));
  await tester.ensureVisible(chip);
  await tester.pump();
}

Future<void> _openSettingsPage(WidgetTester tester, PhoneWorld world) async {
  await world.open(tester, '/me');
  final tile = find.byKey(const ValueKey('chat-folders-tile'));
  await tester.scrollUntilVisible(
    tile,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
  final y = tester.getCenter(tile).dy;
  if (y < 150 || y > 600) {
    await tester.drag(find.byType(Scrollable).first, Offset(0, 350 - y));
    await settle(tester);
  }
  await tester.tap(tile);
  await settle(tester);
}

final chatFoldersA11yScreens = <A11yScreen>[
  A11yScreen('chat-folders-home', (tester, world) async {
    _foldersWorld(world);
    await world.open(tester, '/home');
  }),
  A11yScreen('chat-folders-selected', (tester, world) async {
    _foldersWorld(world);
    await world.open(tester, '/home');
    await _revealChip(tester, 'folder-groups');
    await tester.tap(find.byKey(const ValueKey('chat-folder-folder-groups')));
    await settle(tester);
  }),
  A11yScreen('chat-folders-folded-row', (tester, world) async {
    _foldersWorld(world, folders: const [workFolder, _foldedFolder]);
    await world.open(tester, '/home');
  }),
  A11yScreen('chat-folders-editor', (tester, world) async {
    _foldersWorld(world);
    await world.open(tester, '/home');
    await _revealChip(tester, 'folder-work');
    await tester.longPress(
      find.byKey(const ValueKey('chat-folder-folder-work')),
    );
    await settle(tester);
  }),
  A11yScreen('chat-folders-new-folder', (tester, world) async {
    _foldersWorld(world, folders: const []);
    await world.open(tester, '/home');
    await tester.tap(find.byKey(const ValueKey('chat-folder-new')));
    await settle(tester);
  }),
  A11yScreen('chat-folders-add-to', (tester, world) async {
    _foldersWorld(world);
    await world.open(tester, '/home');
    await tester.longPress(find.byKey(const ValueKey('home-dm-group-hobby')));
    await settle(tester);
    await tester.tap(find.text('Add to folder…'));
    await settle(tester);
  }),
  A11yScreen('chat-folders-picker', (tester, world) async {
    _foldersWorld(world);
    await world.open(tester, '/home');
    await _revealChip(tester, 'folder-work');
    await tester.longPress(
      find.byKey(const ValueKey('chat-folder-folder-work')),
    );
    await settle(tester);
    final include = find.byKey(const ValueKey('chat-folder-include'));
    await tester.scrollUntilVisible(
      include,
      150,
      scrollable: find
          .descendant(
            of: find.byType(ChatFolderEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(include);
    await settle(tester);
  }),
  A11yScreen('chat-folders-settings', (tester, world) async {
    _foldersWorld(
      world,
      folders: const [workFolder, groupsFolder, _foldedFolder],
    );
    await _openSettingsPage(tester, world);
  }),
  A11yScreen('chat-folders-settings-empty', (tester, world) async {
    _foldersWorld(world, folders: const []);
    await _openSettingsPage(tester, world);
  }),
  A11yScreen(
    'desktop-chat-folders-home',
    (tester, world) async {
      _foldersWorld(world, folders: const [workFolder, _foldedFolder]);
      await world.open(tester, '/home');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-chat-folders-selected',
    (tester, world) async {
      _foldersWorld(world, folders: const [workFolder, groupsFolder]);
      await world.open(tester, '/home');
      await _revealChip(tester, 'folder-work');
      await tester.tap(find.byKey(const ValueKey('chat-folder-folder-work')));
      await settle(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-chat-folders-add-to',
    (tester, world) async {
      _foldersWorld(world);
      await world.open(tester, '/home');
      await tester.tap(
        find.byKey(const ValueKey('home-dm-group-hobby')),
        buttons: kSecondaryButton,
      );
      await settle(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
