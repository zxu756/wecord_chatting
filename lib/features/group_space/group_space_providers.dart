import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/group_space/group_space_models.dart';
import 'package:wecord/features/group_space/group_space_repository.dart';

/// What the group space of a chat allows. Not supported for anything but a
/// group chat, so asking about a direct chat is harmless.
final groupSpaceInfoProvider = FutureProvider.autoDispose
    .family<GroupSpaceInfo, String>((ref, conversationId) {
      return ref.watch(groupSpaceRepositoryProvider).info(conversationId);
    });

/// The albums of a group: the ones people made, and the pictures of the
/// chat's events.
final groupAlbumsProvider = FutureProvider.autoDispose
    .family<List<SpaceAlbum>, String>((ref, conversationId) {
      return ref.watch(groupSpaceRepositoryProvider).listAlbums(conversationId);
    });

final albumItemsProvider = FutureProvider.autoDispose
    .family<List<SpaceMedia>, String>((ref, albumId) {
      return ref.watch(groupSpaceRepositoryProvider).listAlbumItems(albumId);
    });

/// Which event of which chat.
typedef EventAlbumRef = ({String conversationId, String eventId});

final eventAlbumProvider = FutureProvider.autoDispose
    .family<List<SpaceMedia>, EventAlbumRef>((ref, key) {
      return ref
          .watch(groupSpaceRepositoryProvider)
          .listEventPhotos(key.conversationId, key.eventId);
    });

final groupFoldersProvider = FutureProvider.autoDispose
    .family<SpaceFolders, String>((ref, conversationId) {
      return ref
          .watch(groupSpaceRepositoryProvider)
          .listFolders(conversationId);
    });

/// Which folder of which chat; a null folder is the top level.
typedef FolderRef = ({String conversationId, String? folderId});

final folderFilesProvider = FutureProvider.autoDispose
    .family<List<SpaceFile>, FolderRef>((ref, key) {
      return ref
          .watch(groupSpaceRepositoryProvider)
          .listFiles(key.conversationId, key.folderId);
    });
