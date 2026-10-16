import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/file_preview/file_actions.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_scope.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/preview_platform_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/file_preview/preview_platform_web.dart'
    as platform;
import 'package:wecord/features/file_preview/preview_states.dart';
import 'package:wecord/features/file_preview/thumbnails.dart';
import 'package:wecord/features/file_preview/viewers/audio_preview.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A sent file: a picture of it where there is one (a PDF's first page, a
/// video's poster frame, an image), its typed tile, name and size, and a
/// download button. Audio files play right in the card. Tapping opens the
/// file viewer.
class FileMessageContent extends ConsumerStatefulWidget {
  const FileMessageContent({
    required this.attachment,
    required this.textColor,
    this.card = false,
    this.messageId,
    this.conversationId,
    this.senderName,
    this.sentAt,
    super.key,
  });

  final FileAttachment attachment;
  final Color textColor;

  /// On its own rounded card (circle channels, the media page) rather
  /// than inside a bubble.
  final bool card;

  final String? messageId;
  final String? conversationId;
  final String? senderName;
  final DateTime? sentAt;

  @override
  ConsumerState<FileMessageContent> createState() => _FileMessageContentState();
}

class _FileMessageContentState extends ConsumerState<FileMessageContent> {
  var _saving = false;

  PreviewFile get _file => PreviewFile.fromFileAttachment(
    widget.attachment,
    messageId: widget.messageId,
    conversationId: widget.conversationId,
    senderName: widget.senderName,
    sentAt: widget.sentAt,
  );

  Future<void> _open() => openFilePreviewInScope(context, _file);

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final outcome = await ref.read(fileActionsProvider).save(_file);
      final text = switch (outcome) {
        SaveOutcome.savedToPhotos => tr('Saved to Photos'),
        SaveOutcome.saved => tr('Saved'),
        SaveOutcome.downloadStarted => null,
        SaveOutcome.cancelled => null,
      };
      if (text != null) {
        messenger?.showSnackBar(SnackBar(content: Text(text)));
      }
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not open the file. Try again.'))),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final kind = file.kind;
    final c = context.tokens.colors;
    final foreground = widget.card ? c.ink : widget.textColor;
    final muted = foreground.withValues(alpha: 0.65);
    final buttonFill = widget.card
        ? c.raised
        : foreground.withValues(alpha: 0.1);

    final details = Row(
      children: [
        FileTypeTile(file: file, size: 40),
        const SizedBox(width: 10),
        Flexible(
          fit: FlexFit.tight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                [
                  formatFileSize(file.size),
                  if (file.extension.isNotEmpty) extensionLabel(file),
                ].join(' · '),
                style: TextStyle(fontSize: 12, height: 1.3, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        WeCordPressable(
          key: ValueKey('file-message-download-${file.path}'),
          onPressed: _saving ? null : () => unawaited(_save()),
          tooltip: tr('Download'),
          semanticLabel: tr('Download'),
          shape: const CircleBorder(),
          pressedScale: 0.92,
          builder: (context, states) => SizedBox.square(
            dimension: WeCordSizes.touchTarget,
            child: Center(
              child: AnimatedContainer(
                duration: WeCordMotion.quick,
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: states.contains(WidgetState.hovered)
                      ? foreground.withValues(alpha: 0.18)
                      : buttonFill,
                  shape: BoxShape.circle,
                ),
                child: _saving
                    ? SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: muted,
                        ),
                      )
                    : Icon(Icons.download_rounded, size: 18, color: foreground),
              ),
            ),
          ),
        ),
      ],
    );

    final visual = switch (kind) {
      PreviewKind.video || PreviewKind.pdf || PreviewKind.image => true,
      _ => false,
    };
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (visual) ...[FileThumbnail(file: file), const SizedBox(height: 8)],
        Padding(
          padding: EdgeInsets.symmetric(vertical: visual ? 0 : 2),
          child: details,
        ),
        if (kind == PreviewKind.audio)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: AudioFilePlayer(
              file: file,
              compact: true,
              foreground: foreground,
            ),
          ),
      ],
    );

    return WeCordPressable(
      key: ValueKey('file-message-${widget.attachment.path}'),
      onPressed: () => unawaited(_open()),
      pressedScale: 0.98,
      semanticLabel: tr('Open {name}', {'name': file.name}),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) {
        if (!widget.card) {
          return body;
        }
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: hovered ? c.raised : c.well,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(color: c.lineSoft),
          ),
          child: body,
        );
      },
    );
  }
}

/// The picture at the top of a file card: a PDF's first page, a video's
/// poster frame with a play button, or the image itself. Falls back to the
/// typed tile on a quiet block.
class FileThumbnail extends ConsumerStatefulWidget {
  const FileThumbnail({required this.file, super.key});

  final PreviewFile file;

  @override
  ConsumerState<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends ConsumerState<FileThumbnail> {
  Future<Uint8List?>? _rendered;
  Future<ImageProvider?>? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.key != widget.file.key) {
      _load();
    }
  }

  void _load() {
    if (widget.file.kind == PreviewKind.image) {
      _image = _imageProvider();
    } else {
      _rendered = ref
          .read(thumbnailServiceProvider)
          .thumbnailFor(widget.file)
          .catchError((Object _) => null);
    }
  }

  Future<ImageProvider?> _imageProvider() async {
    try {
      final cached = await ref
          .read(fileFetcherProvider)
          .cachedPath(widget.file);
      if (cached != null) {
        return ResizeImage(platform.localFileImage(cached), width: 640);
      }
      final url = await ref
          .read(filePreviewServiceProvider)
          .fileUrl(widget.file);
      return ResizeImage(NetworkImage(url.toString()), width: 640);
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final c = context.tokens.colors;
    final kind = file.kind;
    final dark = WeCordPalette.dark;
    final aspect = switch (kind) {
      PreviewKind.video => 16 / 9,
      PreviewKind.pdf => 4 / 3,
      _ =>
        file.width != null && file.height != null && file.height! > 0
            ? (file.width! / file.height!).clamp(0.75, 1.9)
            : 4 / 3,
    };
    final fill = kind == PreviewKind.video ? dark.paper : c.well;

    Widget placeholder({bool loading = false}) => ColoredBox(
      color: fill,
      child: Center(
        child: kind == PreviewKind.video
            ? null
            : loading
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.faint,
                ),
              )
            : FileTypeTile(file: file, size: 56),
      ),
    );

    Widget picture;
    if (kind == PreviewKind.image) {
      picture = FutureBuilder<ImageProvider?>(
        future: _image,
        builder: (context, snapshot) {
          final image = snapshot.data;
          if (image == null) {
            return placeholder(
              loading: snapshot.connectionState != ConnectionState.done,
            );
          }
          return Image(
            image: image,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => placeholder(),
          );
        },
      );
    } else {
      picture = FutureBuilder<Uint8List?>(
        future: _rendered,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return placeholder(
              loading: snapshot.connectionState != ConnectionState.done,
            );
          }
          return ColoredBox(
            color: kind == PreviewKind.pdf ? WeCordPalette.light.panel : fill,
            child: Image.memory(
              bytes,
              fit: kind == PreviewKind.pdf ? BoxFit.fitWidth : BoxFit.cover,
              alignment: Alignment.topCenter,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => placeholder(),
            ),
          );
        },
      );
    }

    return AspectRatio(
      aspectRatio: aspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            picture,
            if (kind == PreviewKind.pdf)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(WeCordRadii.md),
                  border: Border.all(color: c.lineSoft),
                ),
              ),
            if (kind == PreviewKind.video)
              Center(
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: dark.ink.withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                    boxShadow: context.tokens.shadows.float,
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 30,
                    color: dark.onInk,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
