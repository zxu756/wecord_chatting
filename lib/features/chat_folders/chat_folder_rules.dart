import 'package:flutter/foundation.dart';
import 'package:wecord/features/chat_folders/chat_folder.dart';
import 'package:wecord/shared/models/conversation.dart';

/// The id of the built-in "Unread" filter on the chat folder strip. The
/// strip's other entries are "All" (null) and the person's folders (their
/// ids).
const unreadFilterId = '__unread';

/// Whether [chat] has something unread: new messages or a manual "Mark
/// unread". The note to self never does.
bool isUnreadChat(ConversationSummary chat) {
  return !chat.isNoteToSelf && (chat.unreadCount > 0 || chat.isMarkedUnread);
}

/// Whether [folder] takes [chat]: not excluded, and either listed by id (always
/// in) or of a wanted kind that passes the filters.
bool folderTakes(ChatFolder folder, ConversationSummary chat) {
  if (chat.isNoteToSelf || folder.excludeIds.contains(chat.id)) {
    return false;
  }
  if (folder.includeIds.contains(chat.id)) {
    return true;
  }
  if (!folder.includeTypes.contains(chat.type)) {
    return false;
  }
  if (folder.onlyUnread && !isUnreadChat(chat)) {
    return false;
  }
  if (folder.excludeMuted && chat.isMuted) {
    return false;
  }
  if (folder.onlyMuted && !chat.isMuted) {
    return false;
  }
  return true;
}

/// [chats] with the pinned ones first, each group in its given order.
List<ConversationSummary> pinnedFirst(Iterable<ConversationSummary> chats) {
  final pinned = <ConversationSummary>[];
  final others = <ConversationSummary>[];
  for (final chat in chats) {
    (chat.pinnedAt != null ? pinned : others).add(chat);
  }
  return [...pinned, ...others];
}

/// The chats of [folder] in [chats] (the list in the order the server gave),
/// pinned ones first.
List<ConversationSummary> chatsInFolder(
  ChatFolder folder,
  Iterable<ConversationSummary> chats,
) {
  return pinnedFirst(chats.where((chat) => folderTakes(folder, chat)));
}

/// The unread chats of [chats] among those that can speak up: muted ones are
/// quiet, so they don't add to a folder's count.
List<ConversationSummary> loudUnread(Iterable<ConversationSummary> chats) {
  return [
    for (final chat in chats)
      if (isUnreadChat(chat) && !chat.isMuted) chat,
  ];
}

/// Whether one of [chats] has unread messages whose latest mentions
/// [userId]. A mention gets through a muted chat.
bool mentionsMe(Iterable<ConversationSummary> chats, String? userId) {
  if (userId == null) {
    return false;
  }
  return chats.any(
    (chat) =>
        chat.unreadCount > 0 &&
        !chat.isNoteToSelf &&
        chat.mentionedUserIds.contains(userId),
  );
}

/// What a folder chip shows: the number of unread chats and whether one
/// mentions the person.
@immutable
class FolderSummary {
  const FolderSummary({required this.unread, required this.mention});

  factory FolderSummary.of(
    Iterable<ConversationSummary> chats,
    String? userId,
  ) {
    return FolderSummary(
      unread: loudUnread(chats).length,
      mention: mentionsMe(chats, userId),
    );
  }

  final int unread;
  final bool mention;

  @override
  bool operator ==(Object other) =>
      other is FolderSummary &&
      other.unread == unread &&
      other.mention == mention;

  @override
  int get hashCode => Object.hash(unread, mention);
}

/// One row of the chat list under "All".
sealed class ChatListEntry {
  const ChatListEntry();
}

/// A chat on its own row.
class ConversationEntry extends ChatListEntry {
  const ConversationEntry(this.conversation);

  final ConversationSummary conversation;
}

/// The folded folder's chats, as one row.
class FoldedEntry extends ChatListEntry {
  const FoldedEntry({
    required this.folder,
    required this.members,
    required this.summary,
  });

  final ChatFolder folder;

  /// The folded chats, newest first (the order of the list).
  final List<ConversationSummary> members;
  final FolderSummary summary;
}

/// What the list shows for the strip's [selected] entry: null for All, the
/// built-in [unreadFilterId], or a folder's id.
///
/// Under All the folded folder's chats (pinned ones stay out of the fold)
/// give way to one [FoldedEntry] where its first chat was. Elsewhere every
/// chat shows. [chats] is in the order the server gave, the note to self
/// first.
List<ChatListEntry> chatListEntries({
  required List<ConversationSummary> chats,
  required List<ChatFolder> folders,
  required String? selected,
  required String? userId,
}) {
  if (selected == unreadFilterId) {
    return [
      for (final chat in pinnedFirst(chats.where(isUnreadChat)))
        ConversationEntry(chat),
    ];
  }
  if (selected != null) {
    final folder = folders.where((f) => f.id == selected).firstOrNull;
    if (folder == null) {
      return [for (final chat in chats) ConversationEntry(chat)];
    }
    return [
      for (final chat in chatsInFolder(folder, chats)) ConversationEntry(chat),
    ];
  }
  final folded = folders.where((f) => f.folded).firstOrNull;
  if (folded == null) {
    return [for (final chat in chats) ConversationEntry(chat)];
  }
  final members = [
    for (final chat in chats)
      if (chat.pinnedAt == null && folderTakes(folded, chat)) chat,
  ];
  if (members.isEmpty) {
    return [for (final chat in chats) ConversationEntry(chat)];
  }
  final memberIds = {for (final chat in members) chat.id};
  final entries = <ChatListEntry>[];
  var placed = false;
  for (final chat in chats) {
    if (!memberIds.contains(chat.id)) {
      entries.add(ConversationEntry(chat));
    } else if (!placed) {
      placed = true;
      entries.add(
        FoldedEntry(
          folder: folded,
          members: members,
          summary: FolderSummary.of(members, userId),
        ),
      );
    }
  }
  return entries;
}

/// [folder] after the person puts [chat] in it ([include]) or takes it out.
/// A chat the rules already take (or leave) is left to them; otherwise the
/// chat is listed by id (or excluded).
ChatFolder withChatIn(
  ChatFolder folder,
  ConversationSummary chat, {
  required bool include,
}) {
  final includeIds = {...folder.includeIds};
  final excludeIds = {...folder.excludeIds};
  if (include) {
    excludeIds.remove(chat.id);
    final next = folder.copyWith(excludeIds: excludeIds);
    if (!folderTakes(next, chat)) {
      includeIds.add(chat.id);
    }
    return next.copyWith(includeIds: includeIds);
  }
  includeIds.remove(chat.id);
  final next = folder.copyWith(includeIds: includeIds);
  if (folderTakes(next, chat)) {
    excludeIds.add(chat.id);
  }
  return next.copyWith(excludeIds: excludeIds);
}
