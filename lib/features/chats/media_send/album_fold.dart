import 'package:wecord/shared/models/message.dart';

/// The messages of a chat with each album folded into its first message.
class FoldedAlbums {
  const FoldedAlbums({required this.messages, required this.headOf});

  /// What the list shows, in order: every album as one message whose
  /// [ChatMessage.album] holds all of its messages.
  final List<ChatMessage> messages;

  /// The first message's id, for every message that was folded into it.
  final Map<String, String> headOf;
}

/// Whether [message] can be part of an album: a picture, video or file
/// that was sent with an album id and has not been deleted.
bool isAlbumMember(ChatMessage message) {
  return message.attachmentGroupId != null &&
      message.recalledAt == null &&
      (message.type == MessageType.image || message.type == MessageType.file);
}

/// Folds runs of consecutive messages of one sender that share an album id
/// into their first message. A run of one stays as it is (the rest of its
/// album is not loaded, or was deleted); a message in between from someone
/// else, or a deleted one, ends the run.
FoldedAlbums foldAlbums(List<ChatMessage> messages) {
  final folded = <ChatMessage>[];
  final headOf = <String, String>{};
  var index = 0;
  while (index < messages.length) {
    final message = messages[index];
    if (!isAlbumMember(message)) {
      folded.add(message);
      index += 1;
      continue;
    }
    var end = index + 1;
    while (end < messages.length &&
        isAlbumMember(messages[end]) &&
        messages[end].attachmentGroupId == message.attachmentGroupId &&
        messages[end].senderId == message.senderId) {
      end += 1;
    }
    final run = messages.sublist(index, end);
    if (run.length == 1) {
      folded.add(message);
    } else {
      folded.add(message.copyWith(album: List<ChatMessage>.unmodifiable(run)));
      for (final sibling in run.skip(1)) {
        headOf[sibling.id] = message.id;
      }
    }
    index = end;
  }
  return FoldedAlbums(messages: folded, headOf: headOf);
}
