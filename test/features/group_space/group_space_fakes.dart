import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/group_space/album_screen.dart';
import 'package:wecord/features/group_space/folder_screen.dart';
import 'package:wecord/features/group_space/group_space_models.dart';
import 'package:wecord/features/group_space/group_space_screen.dart';
import 'package:wecord/features/group_space/group_space_repository.dart';
import 'package:wecord/features/group_space/space_upload.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../chats/media_send/media_fakes.dart';
import '../file_preview/file_preview_fakes.dart';

/// The group space as the server keeps it, for the screens to read and
/// change: albums with pictures, folders with files, the pictures of one
/// event. Every call is written down in [calls]; [failWith] makes the next
/// call that changes something fail the way the database would.
class FakeGroupSpaceRepository implements GroupSpaceRepository {
  FakeGroupSpaceRepository({
    GroupSpaceInfo? info,
    List<SpaceAlbum>? albums,
    Map<String, List<SpaceMedia>>? items,
    List<SpaceFolder>? folders,
    Map<String?, List<SpaceFile>>? files,
    Map<String, List<SpaceMedia>>? events,
  }) : infoValue =
           info ??
           const GroupSpaceInfo(supported: true, canAdd: true, canTidy: true),
       albums = [...?albums],
       items = {...?items},
       folders = [...?folders],
       files = {...?files},
       events = {...?events};

  GroupSpaceInfo infoValue;
  final List<SpaceAlbum> albums;
  final Map<String, List<SpaceMedia>> items;
  final List<SpaceFolder> folders;
  final Map<String?, List<SpaceFile>> files;
  final Map<String, List<SpaceMedia>> events;
  final calls = <String>[];

  /// Thrown by the next call that changes something.
  Object? failWith;

  /// Messages that cannot be added (view-once, deleted, forwarded...).
  final refused = <String>{};

  var _ids = 0;

  String _id(String prefix) => '$prefix-${++_ids}';

  void _change(String call) {
    calls.add(call);
    if (failWith case final error?) {
      failWith = null;
      throw error;
    }
  }

  /// A refusal in the database's words.
  static PostgrestException refusal(String message) =>
      PostgrestException(message: message, code: '22023');

  List<String> callsStarting(String prefix) => [
    for (final call in calls)
      if (call.startsWith(prefix)) call,
  ];

  @override
  Future<GroupSpaceInfo> info(String conversationId) async => infoValue;

  @override
  Future<List<SpaceAlbum>> listAlbums(String conversationId) async {
    return [
      for (final album in albums)
        album.isEvent
            ? album
            : SpaceAlbum(
                kind: album.kind,
                id: album.id,
                name: album.name,
                itemCount: items[album.id]?.length ?? 0,
                cover: _cover(album),
                creatorName: album.creatorName,
                canManage: album.canManage,
                updatedAt: album.updatedAt,
              ),
    ];
  }

  StoredPath? _cover(SpaceAlbum album) {
    final list = items[album.id] ?? const <SpaceMedia>[];
    for (final item in list) {
      if (!item.isVideo) {
        return item.stored;
      }
    }
    return album.cover;
  }

  @override
  Future<SpaceAlbum> createAlbum(String conversationId, String name) async {
    _change('createAlbum:$name');
    final album = SpaceAlbum(
      kind: SpaceAlbumKind.album,
      id: _id('album'),
      name: name,
      canManage: true,
    );
    albums.insert(0, album);
    items[album.id] = [];
    return album;
  }

  @override
  Future<void> renameAlbum(String albumId, String name) async {
    _change('renameAlbum:$albumId:$name');
    final index = albums.indexWhere((album) => album.id == albumId);
    final old = albums[index];
    albums[index] = SpaceAlbum(
      kind: old.kind,
      id: old.id,
      name: name,
      canManage: old.canManage,
    );
  }

  @override
  Future<void> setAlbumCover(String albumId, String? itemId) async {
    _change('setAlbumCover:$albumId:$itemId');
  }

  @override
  Future<void> deleteAlbum(String albumId) async {
    _change('deleteAlbum:$albumId');
    albums.removeWhere((album) => album.id == albumId);
    items.remove(albumId);
  }

  @override
  Future<List<SpaceMedia>> listAlbumItems(String albumId) async => [
    ...?items[albumId],
  ];

  @override
  Future<AddResult> addMessagesToAlbum(
    String albumId,
    List<String> messageIds,
  ) async {
    _change('addToAlbum:$albumId:${messageIds.join(',')}');
    var added = 0;
    var skipped = 0;
    for (final id in messageIds) {
      if (refused.contains(id)) {
        skipped += 1;
        continue;
      }
      added += 1;
      (items[albumId] ??= []).insert(
        0,
        SpaceMedia(
          id: _id('item'),
          bucket: 'chat-images',
          path: 'conversation-1/from-$id.jpg',
          kind: 'image',
          name: 'from-$id.jpg',
          mimeType: 'image/jpeg',
          adderName: 'Ada',
          fromChat: true,
          mine: true,
          canDelete: true,
        ),
      );
    }
    return AddResult(added: added, skipped: skipped);
  }

  @override
  Future<SpaceMedia> uploadToAlbum(
    String conversationId,
    String albumId,
    SpaceUpload upload,
  ) async {
    _change('uploadToAlbum:$albumId:${upload.name}');
    final item = SpaceMedia(
      id: _id('item'),
      bucket: upload.isImage ? 'chat-images' : 'chat-files',
      path: '$conversationId/space/${upload.name}',
      kind: upload.isImage ? 'image' : 'video',
      name: upload.name,
      mimeType: upload.mimeType,
      size: upload.length,
      adderName: 'Ada',
      mine: true,
      canDelete: true,
    );
    (items[albumId] ??= []).insert(0, item);
    return item;
  }

  @override
  Future<void> removeAlbumItem(String itemId) async {
    _change('removeAlbumItem:$itemId');
    for (final list in items.values) {
      list.removeWhere((item) => item.id == itemId);
    }
  }

  @override
  Future<void> setItemAlt(String itemId, String? alt) async {
    _change('setItemAlt:$itemId:$alt');
    for (final list in items.values) {
      final index = list.indexWhere((item) => item.id == itemId);
      if (index >= 0) {
        final old = list[index];
        list[index] = SpaceMedia(
          id: old.id,
          bucket: old.bucket,
          path: old.path,
          kind: old.kind,
          name: old.name,
          mimeType: old.mimeType,
          alt: alt,
          adderName: old.adderName,
          mine: old.mine,
          canDelete: old.canDelete,
        );
      }
    }
  }

  @override
  Future<List<SpaceMedia>> listEventPhotos(
    String conversationId,
    String eventId,
  ) async => [...?events[eventId]];

  @override
  Future<void> deleteEventPhoto(SpaceMedia photo) async {
    _change('deleteEventPhoto:${photo.id}');
    for (final list in events.values) {
      list.removeWhere((item) => item.id == photo.id);
    }
  }

  @override
  Future<SpaceFolders> listFolders(String conversationId) async {
    return SpaceFolders(
      folders: [
        for (final folder in folders)
          SpaceFolder(
            id: folder.id,
            name: folder.name,
            fileCount: files[folder.id]?.length ?? 0,
            creatorName: folder.creatorName,
            canManage: folder.canManage,
          ),
      ],
      rootCount: files[null]?.length ?? 0,
    );
  }

  @override
  Future<SpaceFolder> createFolder(String conversationId, String name) async {
    _change('createFolder:$name');
    final folder = SpaceFolder(id: _id('folder'), name: name, canManage: true);
    folders.add(folder);
    return folder;
  }

  @override
  Future<void> renameFolder(String folderId, String name) async {
    _change('renameFolder:$folderId:$name');
    final index = folders.indexWhere((folder) => folder.id == folderId);
    folders[index] = SpaceFolder(id: folderId, name: name, canManage: true);
  }

  @override
  Future<void> deleteFolder(String folderId) async {
    _change('deleteFolder:$folderId');
    folders.removeWhere((folder) => folder.id == folderId);
    files.remove(folderId);
  }

  @override
  Future<List<SpaceFile>> listFiles(
    String conversationId,
    String? folderId,
  ) async => [...?files[folderId]];

  @override
  Future<AddResult> addMessagesToFolder(
    String conversationId,
    String? folderId,
    List<String> messageIds,
  ) async {
    _change('addToFolder:$folderId:${messageIds.join(',')}');
    var added = 0;
    var skipped = 0;
    for (final id in messageIds) {
      if (refused.contains(id)) {
        skipped += 1;
        continue;
      }
      added += 1;
      (files[folderId] ??= []).insert(
        0,
        SpaceFile(
          id: _id('file'),
          folderId: folderId,
          bucket: 'chat-files',
          path: 'conversation-1/from-$id.pdf',
          kind: 'file',
          name: 'from-$id.pdf',
          mimeType: 'application/pdf',
          size: 2048,
          adderName: 'Ada',
          fromChat: true,
          mine: true,
          canDelete: true,
        ),
      );
    }
    return AddResult(added: added, skipped: skipped);
  }

  @override
  Future<SpaceFile> uploadToFolder(
    String conversationId,
    String? folderId,
    SpaceUpload upload,
  ) async {
    _change('uploadToFolder:$folderId:${upload.name}');
    final file = SpaceFile(
      id: _id('file'),
      folderId: folderId,
      bucket: 'chat-files',
      path: '$conversationId/space/${upload.name}',
      kind: 'file',
      name: upload.name,
      mimeType: upload.mimeType,
      size: upload.length,
      adderName: 'Ada',
      mine: true,
      canDelete: true,
    );
    (files[folderId] ??= []).insert(0, file);
    return file;
  }

  @override
  Future<void> moveFile(String fileId, String? folderId) async {
    _change('moveFile:$fileId:$folderId');
    SpaceFile? moving;
    for (final list in files.values) {
      for (final file in [...list]) {
        if (file.id == fileId) {
          moving = file;
          list.remove(file);
        }
      }
    }
    if (moving != null) {
      (files[folderId] ??= []).add(
        SpaceFile(
          id: moving.id,
          folderId: folderId,
          bucket: moving.bucket,
          path: moving.path,
          kind: moving.kind,
          name: moving.name,
          mimeType: moving.mimeType,
          size: moving.size,
          adderName: moving.adderName,
          mine: moving.mine,
          canDelete: moving.canDelete,
        ),
      );
    }
  }

  @override
  Future<void> renameFile(String fileId, String name) async {
    _change('renameFile:$fileId:$name');
    for (final list in files.values) {
      final index = list.indexWhere((file) => file.id == fileId);
      if (index >= 0) {
        final old = list[index];
        list[index] = SpaceFile(
          id: old.id,
          folderId: old.folderId,
          bucket: old.bucket,
          path: old.path,
          kind: old.kind,
          name: name,
          mimeType: old.mimeType,
          size: old.size,
          adderName: old.adderName,
          mine: old.mine,
          canDelete: old.canDelete,
        );
      }
    }
  }

  @override
  Future<void> removeFile(String fileId) async {
    _change('removeFile:$fileId');
    for (final list in files.values) {
      list.removeWhere((file) => file.id == fileId);
    }
  }
}

/// A picture of an album, as the server lists it.
SpaceMedia sampleMedia(
  String id, {
  String name = 'hut.jpg',
  String kind = 'image',
  String? alt,
  bool mine = true,
  bool canDelete = true,
  String adder = 'Ada',
  bool fromChat = false,
}) => SpaceMedia(
  id: id,
  bucket: kind == 'image' ? 'chat-images' : 'chat-files',
  path: 'conversation-1/space/$id-$name',
  kind: kind,
  name: name,
  mimeType: kind == 'image' ? 'image/jpeg' : 'video/mp4',
  size: 1200,
  alt: alt,
  adderName: adder,
  createdAt: DateTime.utc(2026, 10, 20, 9),
  fromChat: fromChat,
  mine: mine,
  canDelete: canDelete,
);

SpaceFile sampleFile(
  String id, {
  String name = 'plan.pdf',
  String? folderId,
  bool mine = true,
  bool canDelete = true,
  String adder = 'Ada',
  bool fromChat = false,
  String mimeType = 'application/pdf',
}) => SpaceFile(
  id: id,
  folderId: folderId,
  bucket: 'chat-files',
  path: 'conversation-1/space/$id-$name',
  kind: 'file',
  name: name,
  mimeType: mimeType,
  size: 90000,
  adderName: adder,
  createdAt: DateTime.utc(2026, 10, 21, 9),
  fromChat: fromChat,
  mine: mine,
  canDelete: canDelete,
);

SpaceAlbum sampleAlbum(
  String id,
  String name, {
  int count = 0,
  bool canManage = true,
  StoredPath? cover,
}) => SpaceAlbum(
  kind: SpaceAlbumKind.album,
  id: id,
  name: name,
  itemCount: count,
  cover: cover,
  creatorName: 'Ada',
  canManage: canManage,
);

SpaceAlbum sampleEventAlbum(String id, String name, {int count = 2}) =>
    SpaceAlbum(
      kind: SpaceAlbumKind.event,
      id: id,
      name: name,
      itemCount: count,
      cover: StoredPath('chat-images', 'conversation-1/events/$id.jpg'),
      startsAt: DateTime.utc(2026, 10, 24, 1),
    );

/// A message of the chat that can be picked: a picture or a file.
ConversationMediaItem sampleChatMedia(
  String id, {
  MessageType type = MessageType.image,
  String name = 'photo.jpg',
}) => ConversationMediaItem(
  messageId: id,
  conversationId: 'conversation-1',
  senderId: 'user-2',
  senderName: 'Bart',
  type: type,
  body: '',
  attachment: type == MessageType.image
      ? {
          'kind': 'image',
          'bucket': 'chat-images',
          'path': 'conversation-1/$id.jpg',
          'mime_type': 'image/jpeg',
          'size': 1000,
        }
      : {
          'kind': 'file',
          'bucket': 'chat-files',
          'path': 'conversation-1/$id-$name',
          'name': name,
          'mime_type': 'application/pdf',
          'size': 2048,
        },
  createdAt: DateTime.utc(2026, 10, 19, 10),
);

/// Everything a group space screen needs in a test.
class GroupSpaceWorld {
  GroupSpaceWorld({FakeGroupSpaceRepository? repository, this.media = const []})
    : repository = repository ?? FakeGroupSpaceRepository();

  final FakeGroupSpaceRepository repository;
  final picker = FakeChatMediaPicker();
  final uploader = FakeChatMediaUploader();

  /// What the chat's own media list holds (to choose from).
  List<ConversationMediaItem> media;

  /// For the whole app (the phone world has its own file viewer fakes).
  List<Override> get appOverrides => [
    groupSpaceRepositoryProvider.overrideWithValue(repository),
    chatMediaPickerProvider.overrideWithValue(picker),
    chatMediaUploaderProvider.overrideWithValue(uploader),
    chatMediaProvider('group-1').overrideWith((ref) async => media),
  ];

  /// For a screen alone.
  List<Override> get overrides => [
    ...appOverrides,
    chatMediaProvider('conversation-1').overrideWith((ref) async => media),
    ...filePreviewOverrides(),
  ];
}

/// Shows the group space screens the way the app routes them, starting at
/// [location], with [world]'s fakes.
Future<GoRouter> pumpSpace(
  WidgetTester tester,
  GroupSpaceWorld world, {
  String location = '/chats/conversation-1/space',
  bool dark = false,
  List<Override> extraOverrides = const [],
}) async {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/chats/:conversationId/media',
        builder: (context, state) => ChatMediaScreen(
          conversationId: state.pathParameters['conversationId']!,
        ),
      ),
      GoRoute(
        path: '/chats/:conversationId/space',
        builder: (context, state) => GroupSpaceScreen(
          conversationId: state.pathParameters['conversationId']!,
          initialTab: GroupSpaceScreen.tabFrom(state.uri.queryParameters),
        ),
      ),
      GoRoute(
        path: '/chats/:conversationId/space/albums/:albumId',
        builder: (context, state) => AlbumScreen(
          conversationId: state.pathParameters['conversationId']!,
          albumId: state.pathParameters['albumId'],
          title: state.extra is String ? state.extra! as String : null,
        ),
      ),
      GoRoute(
        path: '/chats/:conversationId/space/events/:eventId',
        builder: (context, state) => AlbumScreen(
          conversationId: state.pathParameters['conversationId']!,
          eventId: state.pathParameters['eventId'],
          title: state.extra is String ? state.extra! as String : null,
        ),
      ),
      GoRoute(
        path: '/chats/:conversationId/space/files',
        builder: (context, state) => FolderScreen(
          conversationId: state.pathParameters['conversationId']!,
        ),
      ),
      GoRoute(
        path: '/chats/:conversationId/space/folders/:folderId',
        builder: (context, state) => FolderScreen(
          conversationId: state.pathParameters['conversationId']!,
          folderId: state.pathParameters['folderId'],
          title: state.extra is String ? state.extra! as String : null,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...world.overrides, ...extraOverrides],
      child: MaterialApp.router(
        theme: dark ? WeCordTheme.dark() : WeCordTheme.light(),
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}
