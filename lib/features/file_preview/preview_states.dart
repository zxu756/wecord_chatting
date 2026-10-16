import 'package:flutter/material.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart' show formatFileSize;
import 'package:wecord/shared/ui/ui.dart';

/// A file's typed squircle: its icon and extension on the type's tone.
class FileTypeTile extends StatelessWidget {
  const FileTypeTile({required this.file, this.size = 44, super.key});

  final PreviewFile file;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tone = previewToneFor(file, context.tokens.colors);
    final showLabel = size >= 56;
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: tone.fill,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(size / 3.2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            previewIconFor(file),
            size: size * (showLabel ? 0.4 : 0.48),
            color: tone.foreground,
          ),
          if (showLabel) ...[
            SizedBox(height: size * 0.04),
            Text(
              extensionLabel(file),
              maxLines: 1,
              style: TextStyle(
                fontSize: (size * 0.15).clamp(9.0, 16.0),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: tone.foreground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The centered column every state uses: a tile, a title, a line of text
/// and buttons.
class PreviewStateLayout extends StatelessWidget {
  const PreviewStateLayout({
    required this.leading,
    required this.title,
    this.message,
    this.below,
    this.actions = const [],
    super.key,
  });

  final Widget leading;
  final String title;
  final String? message;
  final Widget? below;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(WeCordSpace.x6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(height: WeCordSpace.x5),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: c.ink,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: WeCordSpace.x2),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.45, color: c.muted),
                ),
              ],
              if (below != null) ...[
                const SizedBox(height: WeCordSpace.x5),
                below!,
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: WeCordSpace.x6),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: WeCordSpace.x2,
                  runSpacing: WeCordSpace.x2,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Downloading, with real progress when the size is known.
class PreviewProgressView extends StatelessWidget {
  const PreviewProgressView({
    required this.file,
    required this.received,
    required this.total,
    this.label,
    super.key,
  });

  final PreviewFile file;
  final int received;
  final int? total;

  /// What happens after the download ("Opening in Quick Look…").
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final whole = total ?? (file.size > 0 ? file.size : null);
    final fraction = whole == null || whole == 0
        ? null
        : (received / whole).clamp(0.0, 1.0);
    return PreviewStateLayout(
      key: const ValueKey('file-preview-loading'),
      leading: FileTypeTile(file: file, size: 72),
      title: file.name,
      message: label ?? tr('Loading preview…'),
      below: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(WeCordRadii.pill),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              color: c.accent,
              backgroundColor: c.track,
            ),
          ),
          const SizedBox(height: WeCordSpace.x2),
          Text(
            whole == null
                ? formatFileSize(received)
                : tr('{done} of {total}', {
                    'done': formatFileSize(received),
                    'total': formatFileSize(whole),
                  }),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain spinner while a link is fetched (no bytes to count yet).
class PreviewSpinner extends StatelessWidget {
  const PreviewSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('file-preview-loading'),
      child: SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: context.tokens.colors.muted,
        ),
      ),
    );
  }
}

/// Something went wrong: say so, offer Retry and Download.
class PreviewErrorView extends StatelessWidget {
  const PreviewErrorView({
    required this.file,
    required this.onRetry,
    this.onDownload,
    this.title,
    this.message,
    super.key,
  });

  final PreviewFile file;
  final VoidCallback onRetry;
  final VoidCallback? onDownload;
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return PreviewStateLayout(
      key: const ValueKey('file-preview-error'),
      leading: Container(
        width: 72,
        height: 72,
        decoration: ShapeDecoration(
          color: c.dangerSoft,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        child: Icon(Icons.error_outline_rounded, size: 32, color: c.dangerText),
      ),
      title: title ?? tr("Couldn't load this file"),
      message: message ?? tr('Check your connection and try again.'),
      actions: [
        WeCordButton(
          key: const ValueKey('file-preview-retry'),
          label: tr('Try again'),
          icon: Icons.refresh_rounded,
          onPressed: onRetry,
        ),
        if (onDownload != null)
          WeCordButton(
            label: tr('Download'),
            icon: Icons.download_rounded,
            variant: WeCordButtonVariant.secondary,
            onPressed: onDownload,
          ),
      ],
    );
  }
}
