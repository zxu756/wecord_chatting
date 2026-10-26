
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/accessibility/image_alt_sheet.dart';
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/group_space/group_space_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';
import 'group_space_fakes.dart';

Finder _text(String text) => find.text(text);

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the albums', () {
    testWidgets(
      'list the albums with their counts, and the pictures of events',
      (tester) async {
        final world = GroupSpaceWorld(
          repository: FakeGroupSpaceRepository(
            albums: [
              sampleAlbum('a1', 'Trip 2026'),
              sampleEventAlbum('e1', 'Summit picnic'),
            ],
            items: {
              'a1': [sampleMedia('i1'), sampleMedia('i2', name: 'lake.jpg')],
            },
          ),
        );
        await pumpSpace(tester, world);

        expect(_text('Group space'), findsOneWidget);
        expect(_text('Trip 2026'), findsOneWidget);
        expect(_text('2 items'), findsWidgets);
        expect(_text('Summit picnic'), findsOneWidget);
        expect(_text('Event'), findsOneWidget);
        expect(find.byKey(const ValueKey('space-new-album')), findsOneWidget);
      },
    );

    testWidgets('say so when there are none, and offer the first', (
      tester,
    ) async {
      final world = GroupSpaceWorld();
      await pumpSpace(tester, world);
      expect(_text('No albums yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('space-empty-action')), findsOneWidget);
    });

    testWidgets('a new album is made and opened', (tester) async {
      final world = GroupSpaceWorld();
      await pumpSpace(tester, world);

      await tester.tap(find.byKey(const ValueKey('space-new-album')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('space-name-field')),
        'Trip 2026',
      );
      await tester.tap(find.byKey(const ValueKey('space-name-confirm')));
      await tester.pumpAndSettle();

      expect(world.repository.calls, ['createAlbum:Trip 2026']);
      // It opens, empty, with its name in the header.
      expect(_text('Trip 2026'), findsOneWidget);
      expect(_text('Nothing in this album yet'), findsOneWidget);
    });

    testWidgets('a refusal is said in words', (tester) async {
      final world = GroupSpaceWorld(
        repository: FakeGroupSpaceRepository(
          albums: [sampleAlbum('a1', 'Trip')],
        ),
      );
      await pumpSpace(tester, world);
      world.repository.failWith = FakeGroupSpaceRepository.refusal(
        'This group already has an album with that name',
      );
      await tester.tap(find.byKey(const ValueKey('space-new-album')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('space-name-field')),
        'Trip',
      );
      await tester.tap(find.byKey(const ValueKey('space-name-confirm')));
      await tester.pumpAndSettle();
      expect(
        _text('This group already has an album with that name'),
        findsOneWidget,
      );
      // And in Chinese.
      AppStrings.isChinese = true;
      world.repository.failWith = FakeGroupSpaceRepository.refusal(
        'The group space is full',
      );
      await tester.tap(find.byKey(const ValueKey('space-new-album')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('space-name-field')),
        'More',
      );
      await tester.tap(find.byKey(const ValueKey('space-name-confirm')));
      await tester.pumpAndSettle();
      expect(_text('群空间已满'), findsOneWidget);
    });

    testWidgets('closed to adding while disappearing messages are on', (
      tester,
    ) async {
      final world = GroupSpaceWorld(
        repository: FakeGroupSpaceRepository(
          info: const GroupSpaceInfo(
            supported: true,
            enabled: false,
            canAdd: false,
            canTidy: true,
          ),
          albums: [sampleAlbum('a1', 'Trip')],
        ),
      );
      await pumpSpace(tester, world);
      expect(find.byKey(const ValueKey('space-off-notice')), findsOneWidget);
      expect(find.byKey(const ValueKey('space-new-album')), findsNothing);
      // What is there can still be opened.
      expect(_text('Trip'), findsOneWidget);
    });

    testWidgets('a direct chat has no space', (tester) async {
      final world = GroupSpaceWorld(
        repository: FakeGroupSpaceRepository(info: const GroupSpaceInfo()),
      );
      await pumpSpace(tester, world);
      expect(_text('Only group chats have a group space.'), findsOneWidget);
      expect(find.byKey(const ValueKey('space-new-album')), findsNothing);
    });

    testWidgets('someone who may not add sees the albums and no button', (
      tester,
    ) async {
      final world = GroupSpaceWorld(
        repository: FakeGroupSpaceRepository(
          info: const GroupSpaceInfo(supported: true),
          albums: [sampleAlbum('a1', 'Trip', canManage: false)],
        ),
      );
      await pumpSpace(tester, world);
      expect(find.byKey(const ValueKey('space-new-album')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('space-album-a1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('album-add')), findsNothing);
      expect(find.byKey(const ValueKey('album-menu')), findsNothing);
    });
  });

  group('one album', () {
    FakeGroupSpaceRepository withPictures({bool others = false}) =>
        FakeGroupSpaceRepository(
          albums: [sampleAlbum('a1', 'Trip 2026', count: 3)],
          items: {
            'a1': [
              sampleMedia('i1', alt: 'A hut in the snow'),
              sampleMedia('i2', name: 'lake.jpg'),
              sampleMedia('i3', name: 'clip.mp4', kind: 'video'),
              if (others)
                sampleMedia(
                  'i4',
                  name: 'theirs.jpg',
                  mine: false,
                  canDelete: false,
                  adder: 'Bart',
                ),
            ],
          },
        );

    testWidgets('shows its pictures; a tap opens the viewer', (tester) async {
      final world = GroupSpaceWorld(repository: withPictures());
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/albums/a1',
      );
      expect(_text('Trip 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('album-item-i1')), findsOneWidget);
      expect(find.byKey(const ValueKey('album-item-i3')), findsOneWidget);
      // A described picture carries the ALT mark.
      expect(find.byKey(const ValueKey('album-alt-i1')), findsOneWidget);
      expect(find.byKey(const ValueKey('album-alt-i2')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('album-item-i2')));
      await tester.pumpAndSettle();
      expect(find.byType(FilePreviewScreen), findsOneWidget);
    });

    testWidgets('a picture can become the cover', (tester) async {
      final world = GroupSpaceWorld(repository: withPictures());
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/albums/a1',
      );
      await tester.longPress(find.byKey(const ValueKey('album-item-i2')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Make album cover'));
      await tester.pumpAndSettle();
      expect(world.repository.calls, ['setAlbumCover:a1:i2']);
    });

    testWidgets('a video cannot be the cover or be described', (tester) async {
      final world = GroupSpaceWorld(repository: withPictures());
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/albums/a1',
      );
      await tester.longPress(find.byKey(const ValueKey('album-item-i3')));
      await tester.pumpAndSettle();
      expect(_text('Make album cover'), findsNothing);
      expect(_text('Describe this picture'), findsNothing);
      expect(_text('Remove from album'), findsOneWidget);
    });

    testWidgets('a picture gets a description', (tester) async {
      final world = GroupSpaceWorld(repository: withPictures());
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/albums/a1',
      );
      await tester.longPress(find.byKey(const ValueKey('album-item-i2')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Describe this picture'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ImageAltSheet.fieldKey('i2')),
        '  The lake at dawn ',
      );
      await tester.tap(find.byKey(ImageAltSheet.saveKey));
      await tester.pumpAndSettle();
      expect(world.repository.calls, ['setItemAlt:i2:The lake at dawn']);
      expect(find.byKey(const ValueKey('album-alt-i2')), findsOneWidget);
    });

    testWidgets('a picture is removed after asking', (tester) async {
      final world = GroupSpaceWorld(repository: withPictures());
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/albums/a1',
      );
      await tester.longPress(find.byKey(const ValueKey('album-item-i2')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Remove from album'));
      await tester.pumpAndSettle();
      expect(_text('Remove from the album?'), findsOneWidget);
      // The file was uploaded here: it goes with the entry.
      expect(_text('The file is deleted.'), findsOneWidget);
      await tester.tap(_text('Remove'));
      await tester.pumpAndSettle();
      expect(world.repository.calls, ['removeAlbumItem:i2']);
      expect(find.byKey(const ValueKey('album-item-i2')), findsNothing);
    });

    testWidgets('someone else\'s picture has no menu for a plain member', (
      tester,
    ) async {
      final repository = withPictures(others: true);
      repository.albums
        ..clear()
        ..add(sampleAlbum('a1', 'Trip 2026', canManage: false));
      final world = GroupSpaceWorld(repository: repository);
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/albums/a1',
      );
      // Someone else's picture has nothing to hold for.
      expect(
        tester
            .widget<WeCordPressable>(
              find.byKey(const ValueKey('album-item-i4')),
            )
            .onLongPress,
        isNull,
      );
      await tester.longPress(find.byKey(const ValueKey('album-item-i1')));
      await tester.pumpAndSettle();
      expect(_text('Open'), findsOneWidget);
      expect(_text('Remove from album'), findsOneWidget);
    });

    testWidgets('a finger is told to touch and hold; a mouse gets a button', (
      tester,
    ) async {
      final world = GroupSpaceWorld(repository: withPictures(others: true));
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/albums/a1',
      );
      expect(_text('Touch and hold a picture for more.'), findsOneWidget);
      expect(find.byKey(const ValueKey('album-item-more-i1')), findsNothing);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(const SizedBox.shrink());
      final desktop = GroupSpaceWorld(repository: withPictures(others: true));
      await pumpSpace(
        tester,
        desktop,
        location: '/chats/conversation-1/space/albums/a1',
      );
      expect(_text('Touch and hold a picture for more.'), findsNothing);
      expect(find.byKey(const ValueKey('album-item-more-i1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('album-item-more-i1')));
      await tester.pumpAndSettle();
      expect(_text('Remove from album'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('can be renamed and deleted by whoever manages it', (
      tester,
    ) async {
      final world = GroupSpaceWorld(repository: withPictures());
      await pumpSpace(tester, world);
      await tester.tap(find.byKey(const ValueKey('space-album-a1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('album-menu')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Rename album'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('space-name-field')),
        'Trip 2027',
      );
      await tester.tap(find.byKey(const ValueKey('space-name-confirm')));
      await tester.pumpAndSettle();
      expect(world.repository.calls, ['renameAlbum:a1:Trip 2027']);
      expect(_text('Trip 2027'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('album-menu')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Delete album'));
      await tester.pumpAndSettle();
      expect(_text('Delete the album "Trip 2027"?'), findsOneWidget);
      await tester.tap(_text('Delete album').last);
      await tester.pumpAndSettle();
      expect(world.repository.calls.last, 'deleteAlbum:a1');
      // Back on the list, which no longer has it.
      expect(_text('No albums yet'), findsOneWidget);
    });

    testWidgets('pictures are chosen from the chat', (tester) async {
      final world = GroupSpaceWorld(
        repository: withPictures(),
        media: [
          sampleChatMedia('m1'),
          sampleChatMedia('m2'),
          sampleChatMedia('m3', type: MessageType.file, name: 'plan.pdf'),
        ],
      );
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/albums/a1',
      );
      await tester.tap(find.byKey(const ValueKey('album-add')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Choose from this chat'));
      await tester.pumpAndSettle();

      // Pictures only for an album.
      expect(find.byKey(const ValueKey('space-choice-m1')), findsOneWidget);
      expect(find.byKey(const ValueKey('space-choice-m3')), findsNothing);
      expect(_text('Choose some first'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('space-choice-m1')));
      await tester.tap(find.byKey(const ValueKey('space-choice-m2')));
      await tester.pumpAndSettle();
      expect(_text('Add 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('space-pick-confirm')));
      await tester.pumpAndSettle();

      expect(world.repository.calls, hasLength(1));
      expect(world.repository.calls.single, startsWith('addToAlbum:a1:'));
      expect(_text('2 added to the album.'), findsOneWidget);
      expect(find.byKey(const ValueKey('album-item-i1')), findsOneWidget);
    });

    testWidgets('says how many could not be added', (tester) async {
      final world = GroupSpaceWorld(
        repository: withPictures()..refused.add('m2'),
        media: [sampleChatMedia('m1'), sampleChatMedia('m2')],
      );
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/albums/a1',
      );
      await tester.tap(find.byKey(const ValueKey('album-add')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Choose from this chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('space-choice-m1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('space-choice-m2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('space-pick-confirm')));
      await tester.pumpAndSettle();
      expect(
        _text('1 added to the album. 1 could not be added.'),
        findsOneWidget,
      );
    });

    testWidgets('videos are uploaded from the device, with progress', (
      tester,
    ) async {
      final world = GroupSpaceWorld(repository: withPictures());
      world.picker.photos = [
        XFile.fromData(
          Uint8List.fromList([1, 2, 3, 4]),
          name: 'clip.mp4',
          path: 'clip.mp4',
          length: 4,
          mimeType: 'video/mp4',
        ),
      ];
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/albums/a1',
      );
      await tester.tap(find.byKey(const ValueKey('album-add')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Upload photos and videos'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(world.repository.calls, ['uploadToAlbum:a1:clip.mp4']);
      expect(world.picker.photoCalls, 1);
      expect(_text('1 added to the album.'), findsOneWidget);
    });

    testWidgets('a document is not an album picture', (tester) async {
      final world = GroupSpaceWorld(repository: withPictures());
      world.picker.photos = [
        XFile.fromData(
          Uint8List.fromList([1, 2, 3, 4]),
          name: 'notes.pdf',
          path: 'notes.pdf',
          length: 4,
          mimeType: 'application/pdf',
        ),
      ];
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/albums/a1',
      );
      await tester.tap(find.byKey(const ValueKey('album-add')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Upload photos and videos'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(world.repository.calls, isEmpty);
      expect(
        find.textContaining('"notes.pdf" is not a picture or a video.'),
        findsOneWidget,
      );
    });

    testWidgets('the pictures of an event are read-only but can be deleted', (
      tester,
    ) async {
      final repository = FakeGroupSpaceRepository(
        albums: [sampleEventAlbum('e1', 'Summit picnic')],
        events: {
          'e1': [
            sampleMedia('p1', name: 'summit.jpg'),
            sampleMedia('p2', name: 'view.jpg', mine: false, canDelete: false),
          ],
        },
      );
      final world = GroupSpaceWorld(repository: repository);
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/events/e1',
      );
      expect(_text('Summit picnic'), findsOneWidget);
      expect(
        find.textContaining('pictures people added from the event'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('album-add')), findsNothing);
      expect(find.byKey(const ValueKey('album-menu')), findsNothing);
      expect(find.text('Touch and hold a picture for more.'), findsNothing);

      await tester.longPress(find.byKey(const ValueKey('album-item-p1')));
      await tester.pumpAndSettle();
      expect(_text('Make album cover'), findsNothing);
      await tester.tap(_text('Delete picture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(repository.calls, ['deleteEventPhoto:p1']);
    });

    testWidgets('an event album opens from the list', (tester) async {
      final repository = FakeGroupSpaceRepository(
        albums: [sampleEventAlbum('e1', 'Summit picnic')],
        events: {
          'e1': [sampleMedia('p1', name: 'summit.jpg')],
        },
      );
      await pumpSpace(tester, GroupSpaceWorld(repository: repository));
      await tester.tap(find.byKey(const ValueKey('space-album-e1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('album-item-p1')), findsOneWidget);
    });
  });

  group('the folders', () {
    FakeGroupSpaceRepository withFiles() => FakeGroupSpaceRepository(
      folders: [
        const SpaceFolder(
          id: 'fo1',
          name: 'Handouts',
          creatorName: 'Ada',
          canManage: true,
        ),
        const SpaceFolder(id: 'fo2', name: 'Receipts', canManage: false),
      ],
      files: {
        null: [sampleFile('t1', name: 'welcome.pdf')],
        'fo1': [
          sampleFile('f1', name: 'plan.pdf', folderId: 'fo1'),
          sampleFile('f2', name: 'map.png', folderId: 'fo1', fromChat: true),
        ],
      },
    );

    testWidgets('list the folders and the files outside them', (tester) async {
      final world = GroupSpaceWorld(repository: withFiles());
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space?tab=files',
      );
      expect(_text('Group files'), findsOneWidget);
      expect(_text('Handouts'), findsOneWidget);
      expect(_text('Receipts'), findsOneWidget);
      expect(find.byKey(const ValueKey('space-new-folder')), findsOneWidget);
    });

    testWidgets('a new folder is made and opened', (tester) async {
      final world = GroupSpaceWorld();
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space?tab=files',
      );
      expect(_text('No files yet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('space-new-folder')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('space-name-field')),
        'Minutes',
      );
      await tester.tap(find.byKey(const ValueKey('space-name-confirm')));
      await tester.pumpAndSettle();
      expect(world.repository.calls, ['createFolder:Minutes']);
      expect(_text('Minutes'), findsOneWidget);
      expect(_text('No files here yet'), findsOneWidget);
    });

    testWidgets('open, rename, move and remove a file', (tester) async {
      final world = GroupSpaceWorld(repository: withFiles());
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/folders/fo1',
      );
      expect(_text('Handouts'), findsOneWidget);
      expect(_text('plan.pdf'), findsOneWidget);
      expect(_text('map.png'), findsOneWidget);

      // Rename.
      await tester.tap(find.byKey(const ValueKey('folder-file-more-f1')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('space-name-field')),
        'agenda.pdf',
      );
      await tester.tap(find.byKey(const ValueKey('space-name-confirm')));
      await tester.pumpAndSettle();
      expect(_text('agenda.pdf'), findsOneWidget);

      // Move to the other folder.
      await tester.tap(find.byKey(const ValueKey('folder-file-more-f1')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Move to...'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('space-pick-folder-fo1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('space-pick-folder-fo2')));
      await tester.pumpAndSettle();
      expect(world.repository.callsStarting('moveFile'), ['moveFile:f1:fo2']);
      expect(_text('agenda.pdf'), findsNothing);

      // Remove one that came from the chat: it stays there.
      await tester.tap(find.byKey(const ValueKey('folder-file-more-f2')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Remove from group files'));
      await tester.pumpAndSettle();
      expect(_text('The file stays in the chat.'), findsOneWidget);
      await tester.tap(_text('Remove'));
      await tester.pumpAndSettle();
      expect(world.repository.calls.last, 'removeFile:f2');
      expect(_text('No files here yet'), findsOneWidget);
    });

    testWidgets('move can go to the top level', (tester) async {
      final world = GroupSpaceWorld(repository: withFiles());
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/folders/fo1',
      );
      await tester.tap(find.byKey(const ValueKey('folder-file-more-f1')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Move to...'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('space-pick-top')));
      await tester.pumpAndSettle();
      expect(world.repository.calls, ['moveFile:f1:null']);
    });

    testWidgets('a file is uploaded', (tester) async {
      final world = GroupSpaceWorld(repository: withFiles());
      world.picker.files = [
        XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          name: 'budget.csv',
          path: 'budget.csv',
          length: 3,
          mimeType: 'text/csv',
        ),
      ];
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/folders/fo1',
      );
      await tester.tap(find.byKey(const ValueKey('folder-add')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Upload files'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(world.repository.calls, ['uploadToFolder:fo1:budget.csv']);
      expect(_text('1 saved to the group files.'), findsOneWidget);
    });

    testWidgets('files are chosen from the chat, pictures and all', (
      tester,
    ) async {
      final world = GroupSpaceWorld(
        repository: withFiles(),
        media: [
          sampleChatMedia('m1'),
          sampleChatMedia('m3', type: MessageType.file, name: 'plan.pdf'),
        ],
      );
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/files',
      );
      await tester.tap(find.byKey(const ValueKey('folder-add')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Choose from this chat'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('space-choice-m1')), findsOneWidget);
      expect(find.byKey(const ValueKey('space-choice-m3')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('space-choice-m3')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('space-pick-confirm')));
      await tester.pumpAndSettle();
      expect(world.repository.calls, ['addToFolder:null:m3']);
    });

    testWidgets('a folder is renamed and deleted by its owner', (tester) async {
      final world = GroupSpaceWorld(repository: withFiles());
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/folders/fo1',
      );
      await tester.tap(find.byKey(const ValueKey('folder-menu')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Rename folder'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('space-name-field')),
        'Handouts 2026',
      );
      await tester.tap(find.byKey(const ValueKey('space-name-confirm')));
      await tester.pumpAndSettle();
      expect(_text('Handouts 2026'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('folder-menu')));
      await tester.pumpAndSettle();
      await tester.tap(_text('Delete folder'));
      await tester.pumpAndSettle();
      expect(_text('Delete the folder "Handouts 2026"?'), findsOneWidget);
      expect(find.textContaining('Its 2 files'), findsOneWidget);
      await tester.tap(_text('Delete folder').last);
      await tester.pumpAndSettle();
      expect(world.repository.calls.last, 'deleteFolder:fo1');
    });

    testWidgets('someone else\'s folder has no menu for a plain member', (
      tester,
    ) async {
      final world = GroupSpaceWorld(repository: withFiles());
      await pumpSpace(
        tester,
        world,
        location: '/chats/conversation-1/space/folders/fo2',
        extraOverrides: const [],
      );
      expect(find.byKey(const ValueKey('folder-menu')), findsNothing);
      expect(_text('No files here yet'), findsOneWidget);
    });

    testWidgets('a file someone else added cannot be changed by a member', (
      tester,
    ) async {
      final repository = FakeGroupSpaceRepository(
        folders: [const SpaceFolder(id: 'fo1', name: 'Handouts')],
        files: {
          'fo1': [
            sampleFile(
              'f9',
              name: 'theirs.pdf',
              folderId: 'fo1',
              mine: false,
              canDelete: false,
              adder: 'Bart',
            ),
          ],
        },
      );
      await pumpSpace(
        tester,
        GroupSpaceWorld(repository: repository),
        location: '/chats/conversation-1/space/folders/fo1',
      );
      await tester.tap(find.byKey(const ValueKey('folder-file-more-f9')));
      await tester.pumpAndSettle();
      expect(_text('Open'), findsOneWidget);
      expect(_text('Rename'), findsNothing);
      expect(_text('Remove from group files'), findsNothing);
    });
  });

  group('the media page', () {
    testWidgets('a group chat has albums and folders next to its media', (
      tester,
    ) async {
      final world = GroupSpaceWorld(
        repository: FakeGroupSpaceRepository(
          albums: [sampleAlbum('a1', 'Trip 2026')],
          folders: [const SpaceFolder(id: 'fo1', name: 'Handouts')],
        ),
      );
      await pumpSpace(tester, world, location: '/chats/conversation-1/media');
      expect(find.byKey(const ValueKey('media-tab-albums')), findsOneWidget);
      expect(find.byKey(const ValueKey('media-tab-folders')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('media-tab-albums')));
      await tester.pumpAndSettle();
      expect(_text('Trip 2026'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('media-tab-folders')));
      await tester.pumpAndSettle();
      expect(_text('Handouts'), findsOneWidget);
      expect(find.byType(ChatMediaScreen), findsOneWidget);
    });

    testWidgets('a direct chat keeps the three tabs it had', (tester) async {
      final world = GroupSpaceWorld(
        repository: FakeGroupSpaceRepository(info: const GroupSpaceInfo()),
      );
      await pumpSpace(tester, world, location: '/chats/conversation-1/media');
      expect(find.byKey(const ValueKey('media-tab-albums')), findsNothing);
      expect(_text('Images'), findsOneWidget);
      expect(_text('Voice'), findsOneWidget);
      expect(_text('Files'), findsOneWidget);
    });

    testWidgets('fits a narrow phone at large text', (tester) async {
      usePhoneViewport(tester, notchedPhoneLargeText);
      final world = GroupSpaceWorld(
        repository: FakeGroupSpaceRepository(
          albums: [
            sampleAlbum('a1', 'Trip 2026 with a rather long name indeed'),
            sampleEventAlbum('e1', 'Summit picnic'),
          ],
        ),
      );
      await pumpSpace(tester, world, location: '/chats/conversation-1/media');
      await tester.tap(find.byKey(const ValueKey('media-tab-albums')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
