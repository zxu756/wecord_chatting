import 'package:flutter/widgets.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';

/// Tells file and image messages below it which conversation they are in,
/// who sent each file and when, and which images and videos to page
/// through when one is opened. The chat thread puts one around its list.
class FilePreviewScope extends InheritedWidget {
  const FilePreviewScope({
    required this.conversationId,
    required this.files,
    required super.child,
    super.key,
  });

  final String? conversationId;

  /// The conversation's images and files, oldest first. Called only when
  /// something is opened.
  final List<PreviewFile> Function() files;

  static FilePreviewScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FilePreviewScope>();

  @override
  bool updateShouldNotify(FilePreviewScope oldWidget) => false;
}

/// Opens [file] in the viewer, with its sender, time and gallery from the
/// nearest [FilePreviewScope] when there is one.
Future<void> openFilePreviewInScope(BuildContext context, PreviewFile file) {
  final scope = FilePreviewScope.maybeOf(context);
  final files = scope?.files() ?? const <PreviewFile>[];
  final known = files.where((item) => item.key == file.key).firstOrNull;
  final enriched = known == null
      ? file
      : file.withContext(
          messageId: known.messageId,
          conversationId: known.conversationId,
          senderName: known.senderName,
          sentAt: known.sentAt,
        );
  return openFilePreview(
    context,
    file: enriched,
    gallery: files,
    conversationId: scope?.conversationId ?? enriched.conversationId,
  );
}
