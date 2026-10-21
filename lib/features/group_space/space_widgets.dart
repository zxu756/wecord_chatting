import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/thumbnails.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The longest name of an album or a folder.
const spaceNameLength = 40;

/// Thrown inside [runSpaceAction] when the person backs out of a question
/// (the name dialog): nothing is said, and the action counts as not done.
class SpaceCancelled implements Exception {
  const SpaceCancelled();
}

/// Runs [body] and says what went wrong as a snackbar. True when it worked.
Future<bool> runSpaceAction(
  BuildContext context,
  Future<void> Function() body,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await body();
    return true;
  } on SpaceCancelled {
    return false;
  } on Object catch (error) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(errorText(error))));
    return false;
  }
}

void showSpaceMessage(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Asks for a name (a new album or folder, or a new name for one). Null when
/// cancelled.
Future<String?> askSpaceName(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  String initial = '',
  String? hint,
}) {
  return showCircleDialog<String>(
    context,
    builder: (context) => _NameDialog(
      title: title,
      label: label,
      confirmLabel: confirmLabel,
      initial: initial,
      hint: hint,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    required this.initial,
    this.hint,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String initial;
  final String? hint;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: widget.title,
      content: WeCordTextField(
        fieldKey: const ValueKey('space-name-field'),
        controller: _controller,
        autofocus: true,
        label: widget.label,
        hint: widget.hint,
        maxLength: spaceNameLength,
        textInputAction: TextInputAction.done,
        inputFormatters: [LengthLimitingTextInputFormatter(spaceNameLength)],
        onSubmitted: (_) => _done(),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('space-name-confirm'),
          label: widget.confirmLabel,
          onPressed: _done,
        ),
      ],
    );
  }
}

/// A picture of the space: a photo from Storage, or the poster frame of a
/// video, filling its box. [fit] defaults to cropping to fill.
class SpacePicture extends ConsumerStatefulWidget {
  const SpacePicture({
    required this.file,
    this.fit = BoxFit.cover,
    this.cacheWidth = 360,
    super.key,
  });

  final PreviewFile file;
  final BoxFit fit;
  final int cacheWidth;

  @override
  ConsumerState<SpacePicture> createState() => _SpacePictureState();
}

class _SpacePictureState extends ConsumerState<SpacePicture> {
  late Future<Object?> _picture = _load();

  @override
  void didUpdateWidget(covariant SpacePicture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.key != widget.file.key) {
      _picture = _load();
    }
  }

  Future<Object?> _load() async {
    try {
      if (widget.file.kind == PreviewKind.video) {
        return await ref
            .read(thumbnailServiceProvider)
            .thumbnailFor(widget.file);
      }
      return await ref.read(filePreviewServiceProvider).fileUrl(widget.file);
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final video = widget.file.kind == PreviewKind.video;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: video ? WeCordPalette.dark.paper : c.raised),
        FutureBuilder<Object?>(
          future: _picture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data is Uri) {
              return Image.network(
                data.toString(),
                fit: widget.fit,
                cacheWidth: widget.cacheWidth,
                excludeFromSemantics: true,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.broken_image_outlined, color: c.faint),
              );
            }
            if (data is Uint8List) {
              return Image.memory(
                data,
                fit: widget.fit,
                excludeFromSemantics: true,
              );
            }
            if (snapshot.connectionState == ConnectionState.done) {
              return Icon(
                video ? Icons.movie_outlined : Icons.image_outlined,
                color: c.faint,
              );
            }
            return const SizedBox.shrink();
          },
        ),
        if (video)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: ShapeDecoration(
                color: WeCordPalette.dark.ink.withValues(alpha: 0.9),
                shape: const StadiumBorder(),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 16,
                color: WeCordPalette.dark.onInk,
              ),
            ),
          ),
      ],
    );
  }
}

/// A line of explanation under the header (the space is off, nothing here).
class SpaceNotice extends StatelessWidget {
  const SpaceNotice({
    required this.text,
    this.icon = Icons.info_outline,
    super.key,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, height: 1.35, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The notice for a space that is closed to new things.
class SpaceOffNotice extends StatelessWidget {
  const SpaceOffNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SpaceNotice(
        key: const ValueKey('space-off-notice'),
        text: tr(
          'Nothing can be added while disappearing messages are on. What is here stays.',
        ),
        icon: Icons.timer_outlined,
      ),
    );
  }
}

/// What a list shows when it has nothing: a sentence, and optionally the
/// action that fills it.
class SpaceEmpty extends StatelessWidget {
  const SpaceEmpty({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.inline = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Sits in a list (no scrolling of its own) instead of filling the area.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: c.faint),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
          ),
        ],
        if (actionLabel != null) ...[
          const SizedBox(height: 16),
          WeCordButton(
            key: const ValueKey('space-empty-action'),
            label: actionLabel!,
            variant: WeCordButtonVariant.primary,
            onPressed: onAction,
          ),
        ],
      ],
    );
    if (inline) {
      return Padding(padding: const EdgeInsets.all(24), child: content);
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: content,
      ),
    );
  }
}

/// The error of a failed load, in words.
class SpaceLoadError extends StatelessWidget {
  const SpaceLoadError({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              errorText(error),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dangerText),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              WeCordButton(
                label: tr('Try again'),
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
