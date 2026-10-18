import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/chat_folders/chat_folder.dart';
import 'package:wecord/features/chat_folders/chat_folders_repository.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../mobile/phone_test_support.dart' show minutesAgo;

/// The chat folders server in memory. Like the real one it pings
/// [changes] after every write, so other listeners refresh.
class FakeChatFoldersRepository implements ChatFoldersRepository {
  FakeChatFoldersRepository([List<ChatFolder> folders = const []])
    : folders = [...folders];

  List<ChatFolder> folders;
  var loads = 0;
  var _next = 1;

  /// Writes the repository saw, for asserting.
  final created = <ChatFolder>[];
  final updated = <ChatFolder>[];
  final deleted = <String>[];
  final reorders = <List<String>>[];

  /// Makes the next write fail with this.
  Object? failWrites;
  final _changes = StreamController<void>.broadcast();

  /// Pretends another device changed the rows.
  void changeElsewhere(List<ChatFolder> next) {
    folders = [...next];
    _changes.add(null);
  }

  void _maybeFail() {
    final error = failWrites;
    if (error != null) {
      failWrites = null;
      throw error;
    }
  }

  @override
  Future<List<ChatFolder>> load() async {
    loads += 1;
    return [...folders]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
  }

  @override
  Future<ChatFolder> create(ChatFolder draft) async {
    _maybeFail();
    final problem = checkChatFolderName(draft.name);
    if (problem != null) {
      throw ChatFolderException(problem);
    }
    if (folders.length >= maxChatFolders) {
      throw const ChatFolderException(ChatFolderProblem.limit);
    }
    if (draft.folded && folders.any((folder) => folder.folded)) {
      throw const ChatFolderException(ChatFolderProblem.alreadyFolded);
    }
    final folder = ChatFolder(
      id: 'folder-${_next++}',
      name: draft.name.trim(),
      icon: draft.icon,
      sortKey: draft.sortKey,
      includeTypes: draft.includeTypes,
      includeIds: draft.includeIds,
      excludeIds: draft.excludeIds,
      onlyUnread: draft.onlyUnread,
      excludeMuted: draft.excludeMuted,
      onlyMuted: draft.onlyMuted,
      folded: draft.folded,
    );
    folders = [...folders, folder];
    created.add(folder);
    _changes.add(null);
    return folder;
  }

  @override
  Future<void> update(ChatFolder folder) async {
    _maybeFail();
    final problem = checkChatFolderName(folder.name);
    if (problem != null) {
      throw ChatFolderException(problem);
    }
    folders = [
      for (final existing in folders)
        if (existing.id == folder.id)
          folder.copyWith(sortKey: existing.sortKey)
        else
          existing,
    ];
    updated.add(folder);
    _changes.add(null);
  }

  @override
  Future<void> delete(String folderId) async {
    _maybeFail();
    folders = [
      for (final folder in folders)
        if (folder.id != folderId) folder,
    ];
    deleted.add(folderId);
    _changes.add(null);
  }

  @override
  Future<void> reorder(List<String> folderIds) async {
    _maybeFail();
    folders = [
      for (final folder in folders)
        folder.copyWith(
          sortKey: folderIds.contains(folder.id)
              ? folderIds.indexOf(folder.id) + 1
              : folder.sortKey,
        ),
    ];
    reorders.add(folderIds);
    _changes.add(null);
  }

  @override
  Stream<void> changes() => _changes.stream;
}

List<Override> chatFoldersOverrides(FakeChatFoldersRepository repository) => [
  chatFoldersRepositoryProvider.overrideWithValue(repository),
];

/// A small chat list to filter: a pinned direct chat, two groups (one with an
/// @mention of the signed-in user) and a quiet one.
List<ConversationSummary> folderChats() => [
  ConversationSummary(
    id: 'dm-bart',
    type: ConversationType.direct,
    title: 'Bart',
    unreadCount: 2,
    pinnedAt: minutesAgo(900),
    lastMessageBody: 'Ping',
    lastMessageAt: minutesAgo(30),
    directUserId: 'user-2',
  ),
  ConversationSummary(
    id: 'group-work',
    type: ConversationType.group,
    title: 'Work crew',
    unreadCount: 3,
    memberCount: 8,
    lastMessageBody: '@Ada the build is red',
    lastMessageAt: minutesAgo(5),
    mentionedUserIds: const {'user-1'},
  ),
  ConversationSummary(
    id: 'group-hobby',
    type: ConversationType.group,
    title: 'Hobby club',
    unreadCount: 1,
    memberCount: 20,
    lastMessageBody: 'Photos from Saturday',
    lastMessageAt: minutesAgo(60),
  ),
  ConversationSummary(
    id: 'group-quiet',
    type: ConversationType.group,
    title: 'Old classmates',
    unreadCount: 40,
    memberCount: 90,
    isMuted: true,
    lastMessageBody: 'Happy birthday!',
    lastMessageAt: minutesAgo(200),
  ),
  ConversationSummary(
    id: 'dm-grace',
    type: ConversationType.direct,
    title: 'Grace',
    unreadCount: 0,
    lastMessageBody: 'Thanks',
    lastMessageAt: minutesAgo(400),
    directUserId: 'user-3',
  ),
];

const workFolder = ChatFolder(
  id: 'folder-work',
  name: 'Work',
  icon: 'work',
  sortKey: 1,
  includeIds: {'group-work', 'dm-grace'},
);

const groupsFolder = ChatFolder(
  id: 'folder-groups',
  name: 'Groups',
  icon: 'people',
  sortKey: 2,
  includeTypes: {ConversationType.group},
);
