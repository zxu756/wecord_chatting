import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:wecord/shared/models/message.dart';

/// What a key press in the message field asks for, outside the
/// suggestion lists.
enum ComposerShortcut {
  /// Esc: cancel an edit or reply, close the search, or mark read.
  escape,

  /// Up in an empty field: edit the latest message the user sent.
  editLast,

  /// Cmd/Ctrl+Shift+E: rewrite the draft with AI.
  rewriteWithAi,
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
  if (key == LogicalKeyboardKey.keyE &&
      keyboard.isShiftPressed &&
      (keyboard.isMetaPressed || keyboard.isControlPressed) &&
      !keyboard.isAltPressed) {
    return ComposerShortcut.rewriteWithAi;
  }
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

/// Where the open chat's message box is, so the "jump to the message box"
/// shortcut (Ctrl/Cmd+J) can reach it from anywhere in the app — the
/// keyboard's way past a long message list.
abstract final class ComposerFocusRegistry {
  static FocusNode? _node;

  /// Called by the chat that is on screen.
  static void attach(FocusNode node) => _node = node;

  /// Called when that chat goes away.
  static void detach(FocusNode node) {
    if (identical(_node, node)) {
      _node = null;
    }
  }

  /// Moves focus into the message box; false when no chat is open.
  static bool focus() {
    final node = _node;
    if (node == null || !node.canRequestFocus || node.context == null) {
      return false;
    }
    node.requestFocus();
    return true;
  }
}
