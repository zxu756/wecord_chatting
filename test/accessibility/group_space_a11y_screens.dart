// The group space (B6), for the accessibility guard (guidelines_test.dart) and
// the screenshot tools: the media page of a group with its Albums and Folders
// tabs, the space on its own (albums, folders), an album with its pictures and
// the menu of one, the pictures of an event, a folder with its files and the
// menu of one, the sheets that choose an album, a folder or pictures from the
// chat, the question for a name, and the More menu of a group chat, at large
// text, narrow and with Care mode on.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/group_space/group_space_models.dart';
import 'package:wecord/features/group_space/space_pickers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../features/group_space/group_space_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

/// The sample group's space: albums (one of an event), folders and files.
GroupSpaceWorld _space(
  PhoneWorld world, {
  GroupSpaceInfo? info,
  bool empty = false,
}) {
  final repository = FakeGroupSpaceRepository(
    info: info,
    albums: empty
        ? null
        : [
            sampleAlbum('a1', 'Trip to the lake 2026', count: 4),
            sampleAlbum('a2', 'Birthday', canManage: false),
            sampleEventAlbum('e1', 'Saturday hike'),
          ],
    items: empty
        ? null
        : {
            'a1': [
              sampleMedia('i1', alt: 'Our hut at the lake in the snow'),
              sampleMedia('i2', name: 'lake.jpg'),
              sampleMedia('i3', name: 'clip.mp4', kind: 'video'),
              sampleMedia(
                'i4',
                name: 'theirs.jpg',
                mine: false,
                canDelete: false,
                adder: 'Bart',
              ),
            ],
            'a2': [sampleMedia('i5', name: 'cake.jpg', mine: false)],
          },
    events: empty
        ? null
        : {
            'e1': [
              sampleMedia('p1', name: 'summit.jpg'),
              sampleMedia('p2', name: 'view.jpg', mine: false),
            ],
          },
    folders: empty
        ? null
        : [
            const SpaceFolder(
              id: 'fo1',
              name: 'Handouts and the long name of a folder',
              creatorName: 'Ada',
              canManage: true,
            ),
            const SpaceFolder(id: 'fo2', name: 'Receipts'),
          ],
    files: empty
        ? null
        : {
            null: [sampleFile('t1', name: 'welcome.pdf')],
            'fo1': [
              sampleFile('f1', name: 'trip-plan-with-a-rather-long-name.pdf'),
              sampleFile(
                'f2',
                name: 'map.png',
                mimeType: 'image/png',
                fromChat: true,
              ),
              sampleFile(
                'f3',
                name: 'budget.xlsx',
                mine: false,
                canDelete: false,
                adder: 'Bart',
                mimeType:
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              ),
            ],
          },
  );
  final space = GroupSpaceWorld(
    repository: repository,
    media: [
      sampleChatMedia('m1'),
      sampleChatMedia('m2'),
      sampleChatMedia('m3', type: MessageType.file, name: 'plan.pdf'),
    ],
  );
  world.extraOverrides = [...world.extraOverrides, ...space.appOverrides];
  return space;
}

Future<void> _open(
  WidgetTester tester,
  PhoneWorld world,
  String location, {
  GroupSpaceInfo? info,
  bool empty = false,
}) async {
  _space(world, info: info, empty: empty);
  await world.open(tester, location);
  await settle(tester);
}

Future<void> _thread(WidgetTester tester, PhoneWorld world) async {
  _space(world);
  await world.open(
    tester,
    '/chats/group-1',
    extra: ChatThreadRouteExtra(
      title: groupDetail.title,
      type: ConversationType.group,
    ),
  );
  await settle(tester);
}

const _space1 = '/chats/group-1/space';

final groupSpaceA11yScreens = <A11yScreen>[
  A11yScreen('group-media-albums-tab', (tester, world) async {
    await _open(tester, world, '/chats/group-1/media');
    await tester.tap(find.byKey(const ValueKey('media-tab-albums')));
    await settle(tester);
  }),
  A11yScreen('group-media-folders-tab', (tester, world) async {
    await _open(tester, world, '/chats/group-1/media');
    await tester.tap(find.byKey(const ValueKey('media-tab-folders')));
    await settle(tester);
  }),
  A11yScreen('group-space-albums', (tester, world) async {
    await _open(tester, world, _space1);
  }),
  A11yScreen('group-space-albums-large-text', (tester, world) async {
    await _open(tester, world, _space1);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('group-space-albums-narrow', (tester, world) async {
    await _open(tester, world, _space1);
  }, viewport: smallPhone),
  A11yScreen('group-space-albums-care-mode', (tester, world) async {
    _care(world);
    await _open(tester, world, _space1);
  }),
  A11yScreen('group-space-albums-empty', (tester, world) async {
    await _open(tester, world, _space1, empty: true);
  }),
  A11yScreen('group-space-off', (tester, world) async {
    await _open(
      tester,
      world,
      _space1,
      info: const GroupSpaceInfo(
        supported: true,
        enabled: false,
        canTidy: true,
      ),
    );
  }),
  A11yScreen('group-space-folders', (tester, world) async {
    await _open(tester, world, '$_space1?tab=files');
  }),
  A11yScreen('group-space-folders-large-text', (tester, world) async {
    await _open(tester, world, '$_space1?tab=files');
  }, viewport: notchedPhoneLargeText),
  A11yScreen('group-space-folders-empty', (tester, world) async {
    await _open(tester, world, '$_space1?tab=files', empty: true);
  }),
  A11yScreen('group-space-album', (tester, world) async {
    await _open(tester, world, '$_space1/albums/a1');
  }),
  A11yScreen('group-space-album-large-text', (tester, world) async {
    await _open(tester, world, '$_space1/albums/a1');
  }, viewport: notchedPhoneLargeText),
  A11yScreen('group-space-album-narrow', (tester, world) async {
    await _open(tester, world, '$_space1/albums/a1');
  }, viewport: smallPhone),
  A11yScreen('group-space-album-care-mode', (tester, world) async {
    _care(world);
    await _open(tester, world, '$_space1/albums/a1');
  }),
  A11yScreen('group-space-album-empty', (tester, world) async {
    await _open(tester, world, '$_space1/albums/a9', empty: true);
  }),
  A11yScreen('group-space-album-menu', (tester, world) async {
    await _open(tester, world, '$_space1/albums/a1');
    await tester.longPress(find.byKey(const ValueKey('album-item-i2')));
    await settle(tester);
  }),
  A11yScreen('group-space-album-options', (tester, world) async {
    await _open(tester, world, '$_space1/albums/a1');
    await tester.tap(find.byKey(const ValueKey('album-menu')));
    await settle(tester);
  }),
  A11yScreen('group-space-album-add', (tester, world) async {
    await _open(tester, world, '$_space1/albums/a1');
    await tester.tap(find.byKey(const ValueKey('album-add')));
    await settle(tester);
  }),
  A11yScreen('group-space-album-not-yours', (tester, world) async {
    await _open(tester, world, '$_space1/albums/a2');
  }),
  A11yScreen('group-space-event-album', (tester, world) async {
    await _open(tester, world, '$_space1/events/e1');
  }),
  A11yScreen('group-space-folder', (tester, world) async {
    await _open(tester, world, '$_space1/folders/fo1');
  }),
  A11yScreen('group-space-folder-large-text', (tester, world) async {
    await _open(tester, world, '$_space1/folders/fo1');
  }, viewport: notchedPhoneLargeText),
  A11yScreen('group-space-folder-narrow', (tester, world) async {
    await _open(tester, world, '$_space1/folders/fo1');
  }, viewport: smallPhone),
  A11yScreen('group-space-folder-care-mode', (tester, world) async {
    _care(world);
    await _open(tester, world, '$_space1/folders/fo1');
  }),
  A11yScreen('group-space-folder-menu', (tester, world) async {
    await _open(tester, world, '$_space1/folders/fo1');
    await tester.tap(find.byKey(const ValueKey('folder-file-more-f1')));
    await settle(tester);
  }),
  A11yScreen('group-space-files-top', (tester, world) async {
    await _open(tester, world, '$_space1/files');
  }),
  A11yScreen('group-space-folder-empty', (tester, world) async {
    await _open(tester, world, '$_space1/folders/fo9', empty: true);
  }),
  A11yScreen('group-space-name-dialog', (tester, world) async {
    await _open(tester, world, _space1);
    await tester.tap(find.byKey(const ValueKey('space-new-album')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('space-name-field')),
      'Trip to the lake 2027',
    );
    await tester.pump();
  }),
  A11yScreen('group-space-choose-album', (tester, world) async {
    await _open(tester, world, _space1);
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(
      addMessagesToAlbumFlow(
        context,
        conversationId: 'group-1',
        messageIds: const ['m1'],
      ),
    );
    await settle(tester);
  }),
  A11yScreen('group-space-choose-folder', (tester, world) async {
    await _open(tester, world, _space1);
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(
      saveMessagesToFilesFlow(
        context,
        conversationId: 'group-1',
        messageIds: const ['m3'],
      ),
    );
    await settle(tester);
  }),
  A11yScreen('group-space-choose-from-chat', (tester, world) async {
    await _open(tester, world, '$_space1/albums/a1');
    await tester.tap(find.byKey(const ValueKey('album-add')));
    await settle(tester);
    await tester.tap(find.text(tr('Choose from this chat')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('space-choice-m1')));
    await tester.pump();
  }),
  A11yScreen('group-space-choose-files-from-chat', (tester, world) async {
    await _open(tester, world, '$_space1/files');
    await tester.tap(find.byKey(const ValueKey('folder-add')));
    await settle(tester);
    await tester.tap(find.text(tr('Choose from this chat')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('space-choice-m3')));
    await tester.pump();
  }),
  A11yScreen('group-thread-more-menu-with-space', (tester, world) async {
    await _thread(tester, world);
    await tester.tap(find.byTooltip(tr('More')));
    await settle(tester);
  }),
];
