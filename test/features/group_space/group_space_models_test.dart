import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/media_send/media_draft.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/group_space/group_space_models.dart';
import 'package:wecord/features/group_space/space_pickers.dart';
import 'package:wecord/features/group_space/space_upload.dart';
import 'package:wecord/shared/l10n/l10n.dart';

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('what the server answers', () {
    test('what the space allows', () {
      final info = GroupSpaceInfo.fromJson({
        'supported': true,
        'enabled': false,
        'can_add': false,
        'can_tidy': true,
        'is_admin': true,
        'album_count': 3,
        'folder_count': 2,
      });
      expect(info.supported, isTrue);
      expect(info.enabled, isFalse);
      expect(info.canAdd, isFalse);
      expect(info.canTidy, isTrue);
      expect(info.isAdmin, isTrue);
      expect(info.albumCount, 3);
      expect(info.folderCount, 2);
      // A direct chat only says it is not supported.
      final direct = GroupSpaceInfo.fromJson({'supported': false});
      expect(direct.supported, isFalse);
      expect(direct.canAdd, isFalse);
    });

    test('an album and an album of an event', () {
      final album = SpaceAlbum.fromJson({
        'kind': 'album',
        'id': 'a1',
        'name': 'Trip',
        'item_count': 4,
        'cover': {'bucket': 'chat-images', 'path': 'c/space/x.jpg'},
        'creator_name': 'Ada',
        'can_manage': true,
        'updated_at': '2026-10-20T01:00:00Z',
      });
      expect(album.isEvent, isFalse);
      expect(album.itemCount, 4);
      expect(album.cover, const StoredPath('chat-images', 'c/space/x.jpg'));
      expect(album.canManage, isTrue);

      final event = SpaceAlbum.fromJson({
        'kind': 'event',
        'id': 'e1',
        'name': 'Summit',
        'item_count': 2,
        'cover': {'bucket': 'chat-images', 'path': 'c/events/p.jpg'},
        'can_manage': false,
        'starts_at': '2026-10-24T01:00:00Z',
      });
      expect(event.isEvent, isTrue);
      expect(event.startsAt, isNotNull);
      expect(event.creatorName, isNull);

      // No cover when the album is empty.
      expect(
        SpaceAlbum.fromJson({
          'kind': 'album',
          'id': 'a2',
          'name': 'Empty',
          'item_count': 0,
          'cover': null,
        }).cover,
        isNull,
      );
    });

    test('a picture keeps its description and where it came from', () {
      final item = SpaceMedia.fromJson({
        'id': 'i1',
        'bucket': 'chat-images',
        'path': 'c/hut.jpg',
        'kind': 'image',
        'name': 'hut.jpg',
        'mime_type': 'image/jpeg',
        'size': 1200,
        'width': 800,
        'height': 600,
        'alt': '  A hut in the snow ',
        'adder_name': 'Ada',
        'created_at': '2026-10-20T01:00:00Z',
        'from_chat': true,
        'message_id': 'm1',
        'mine': true,
        'can_delete': true,
      });
      expect(item.alt, 'A hut in the snow');
      expect(item.fromChat, isTrue);
      expect(item.messageId, 'm1');
      final preview = item.toPreviewFile();
      expect(preview.kind, PreviewKind.image);
      expect(preview.alt, 'A hut in the snow');
      expect(preview.messageId, 'm1');
      expect(preview.width, 800);
      expect(preview.senderName, 'Ada');
      // The viewer must not widen to the whole chat's media.
      expect(preview.conversationId, isNull);
    });

    test('a picture of an event has no type: it is read from the name', () {
      final photo = SpaceMedia.fromJson({
        'id': 'p1',
        'bucket': 'chat-images',
        'path': 'c/events/summit.png',
        'kind': 'image',
        'name': 'summit.png',
      });
      expect(photo.toPreviewFile().mimeType, 'image/png');
      expect(photo.toPreviewFile().kind, PreviewKind.image);
      final video = SpaceMedia.fromJson({
        'id': 'v1',
        'bucket': 'chat-files',
        'path': 'c/space/v.mov',
        'kind': 'video',
        'name': 'v.mov',
      });
      expect(video.isVideo, isTrue);
      expect(video.toPreviewFile().kind, PreviewKind.video);
    });

    test('folders come with the number of files at the top', () {
      final folders = SpaceFolders.fromJson({
        'folders': [
          {
            'id': 'f1',
            'name': 'Handouts',
            'file_count': 3,
            'creator_name': 'Ada',
            'can_manage': true,
          },
        ],
        'root_count': 5,
      });
      expect(folders.rootCount, 5);
      expect(folders.folders.single.name, 'Handouts');
      expect(folders.folders.single.fileCount, 3);
      expect(const SpaceFolders().folders, isEmpty);
    });

    test('a file shows in the viewer with its type', () {
      final file = SpaceFile.fromJson({
        'id': 'f1',
        'folder_id': 'fo1',
        'bucket': 'chat-files',
        'path': 'c/space/plan.pdf',
        'kind': 'file',
        'name': 'plan.pdf',
        'mime_type': 'application/pdf',
        'size': 90000,
        'message_id': 'm9',
        'can_delete': true,
      });
      expect(file.folderId, 'fo1');
      final preview = file.toPreviewFile();
      expect(preview.kind, PreviewKind.pdf);
      expect(preview.messageId, 'm9');
      expect(
        SpaceFile.fromJson({
          'id': 'f2',
          'bucket': 'chat-files',
          'path': 'c/space/blob',
          'name': '',
        }).toPreviewFile().name,
        'blob',
      );
    });

    test('how many went in', () {
      final result = AddResult.fromJson({'added': 3, 'skipped': 1});
      expect(result.added, 3);
      expect(result.skipped, 1);
    });
  });

  group('the sentence after adding', () {
    test('says how many went in and how many did not', () {
      expect(
        addResultText(const AddResult(added: 2), toAlbum: true),
        '2 added to the album.',
      );
      expect(
        addResultText(const AddResult(added: 2, skipped: 1), toAlbum: true),
        '2 added to the album. 1 could not be added.',
      );
      expect(
        addResultText(const AddResult(added: 1), toAlbum: false),
        '1 saved to the group files.',
      );
      expect(
        addResultText(const AddResult(skipped: 2), toAlbum: true),
        contains('View-once'),
      );
    });

    test('is in Chinese too', () {
      AppStrings.isChinese = true;
      expect(
        addResultText(const AddResult(added: 2, skipped: 1), toAlbum: true),
        '已有 2 项加入相册。 有 1 项无法添加。',
      );
    });
  });

  group('an upload', () {
    SpaceUpload upload(String name) => SpaceUpload(
      name: name,
      mimeType: 'image/jpeg',
      length: 3,
      data: () => Stream.value(const [1, 2, 3]),
      kind: DraftKind.image,
    );

    test('keeps the extension of the name for the stored file', () {
      expect(upload('hut.JPG').extension, '.jpg');
      expect(upload('archive.tar.gz').extension, '.gz');
      expect(upload('Makefile').extension, '.makefile');
      expect(upload('noextension').extension, '');
      expect(upload('odd.ext-ension').extension, '');
      expect(upload('long.abcdefghijklmnop').extension, '');
    });

    test('can be given a description', () {
      final described = upload('a.jpg').withAlt('A hut');
      expect(described.alt, 'A hut');
      expect(described.isImage, isTrue);
      expect(described.length, 3);
    });
  });
}
