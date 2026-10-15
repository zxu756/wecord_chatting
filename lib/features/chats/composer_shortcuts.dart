import 'package:flutter/services.dart';
import 'package:wecord/shared/models/message.dart';

/// What a key press in the message field asks for, outside the
/// suggestion lists.
enum ComposerShortcut {
  /// Esc: cancel an edit or reply, close the search, or mark read.
  escape,

  /// Up in an empty field: edit the latest message the user sent.
  editLast,
}

/// The shortcut [event] triggers in a message field holding [text], or
/// null.
ComposerShortcut? composerShortcutFor(KeyEvent event, {required String text}) {
  if (event is! KeyDownEvent) {
    return null;
  }
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.escape) {
    return ComposerShortcut.escape;
  }
  final keyboard = HardwareKeyboard.instance;
  if (key == LogicalKeyboardKey.arrowUp &&
      text.isEmpty &&
      !keyboard.isShiftPressed &&
      !keyboard.isAltPressed &&
      !keyboard.isControlPressed &&
      !keyboard.isMetaPressed) {
    return ComposerShortcut.editLast;
  }
  return null;
}

/// The newest text message in [messages] that [currentUserId] sent
/// themselves and can still edit.
ChatMessage? lastEditableMessage(
  List<ChatMessage> messages,
  String? currentUserId,
) {
  ChatMessage? latest;
  for (final message in messages) {
    if (message.type != MessageType.text ||
        message.recalledAt != null ||
        !message.isSentBy(currentUserId)) {
      continue;
    }
    if (latest == null || message.createdAt.isAfter(latest.createdAt)) {
      latest = message;
    }
  }
  return latest;
}
