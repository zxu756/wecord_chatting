import 'package:flutter/material.dart';
import 'package:wecord/features/chats/media_send/media_draft.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/photo_editor/editor_render.dart';
import 'package:wecord/features/photo_editor/photo_editor_screen.dart';

/// Opens the photo editor on a picture waiting in the tray and, on Done,
/// swaps in the edited copy. The picture as chosen is kept in the draft
/// until it is sent, so it can be edited again (the editor opens where it
/// was left) or put back.
Future<void> editTrayPhoto(
  BuildContext context,
  MediaTrayController controller,
  DraftAttachment draft, {
  required bool original,
}) async {
  if (!draft.canEdit) {
    return;
  }
  final source = draft.source ?? draft.file;
  final bytes = await source.readAsBytes();
  if (!context.mounted) {
    return;
  }
  final result = await Navigator.of(context, rootNavigator: true)
      .push<PhotoEditResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PhotoEditorScreen(
            sourceBytes: bytes,
            fileName: source.name.isNotEmpty ? source.name : draft.name,
            initial: draft.edits,
            // The photo keeps its own resolution (up to what phones take)
            // when it goes out at original quality, and is scaled for
            // sending otherwise.
            maxEdge: original ? editorMaxEdge : maxPhotoEdge,
            quality: original ? originalJpegQuality : photoJpegQuality,
          ),
        ),
      );
  if (result == null) {
    return;
  }
  final photo = result.photo;
  if (photo == null) {
    // Everything was taken back: the picture goes out as chosen.
    if (draft.isEdited) {
      await controller.resetEdit(draft.id);
    }
    return;
  }
  await controller.applyEdit(
    draft.id,
    photo: photo,
    document: result.document,
  );
}
