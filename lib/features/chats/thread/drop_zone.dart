part of '../chat_thread_screen.dart';

// Drag and drop: files dropped on the chat.

extension _ThreadDropZone on _ChatThreadScreenState {
  /// Files dropped anywhere on the chat go to the tray (macOS and the
  /// web), unless the reader cannot send here or something sits over
  /// the chat.
  Widget _dropZone(BuildContext context, bool canSend, Widget child) {
    return ChatDropZone(
      enabled: canSend && ModalRoute.of(context)?.isCurrent != false,
      onFiles: (files) => unawaited(_addToTray(files)),
      child: child,
    );
  }
}
