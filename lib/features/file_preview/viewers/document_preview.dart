import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/native_file_bridge.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/preview_states.dart';
import 'package:wecord/features/file_preview/viewers/pdf_preview.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Whether this platform converts Office files on the server (the web)
/// rather than showing them in Quick Look; tests set it.
final officeConvertsOnServerProvider = Provider<bool>((ref) => kIsWeb);

enum _QuickLookStep { downloading, showing, unavailable, failed }

/// Word, Excel, PowerPoint, OpenDocument, RTF and iWork files.
///
/// * iOS and macOS: downloaded into the file cache (with progress), then
///   shown natively in Quick Look; the viewer closes with it.
/// * The web: converted to PDF on the server (office-preview Edge
///   Function) and shown in the PDF viewer; when the server has no
///   converter, says so and offers the download.
class OfficePreview extends ConsumerStatefulWidget {
  const OfficePreview({
    required this.file,
    required this.desktop,
    required this.onQuickLookClosed,
    this.onDownload,
    this.onOpenIn,
    this.pdfViewerBuilder = defaultPdfViewerBuilder,
    super.key,
  });

  final PreviewFile file;
  final bool desktop;
  final VoidCallback onQuickLookClosed;
  final VoidCallback? onDownload;
  final VoidCallback? onOpenIn;
  final PdfViewerBuilder pdfViewerBuilder;

  @override
  ConsumerState<OfficePreview> createState() => _OfficePreviewState();
}

class _OfficePreviewState extends ConsumerState<OfficePreview> {
  // Web.
  Future<Uri>? _converted;

  // Apple.
  var _step = _QuickLookStep.downloading;
  var _received = 0;
  int? _total;
  String? _path;
  FetchCancel? _cancel;

  bool get _server => ref.read(officeConvertsOnServerProvider);

  @override
  void initState() {
    super.initState();
    if (_server) {
      _convert();
    } else if (ref.read(nativeFileBridgeProvider).isSupported) {
      unawaited(_quickLook());
    } else {
      _step = _QuickLookStep.unavailable;
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  void _convert() {
    setState(() {
      _converted = ref
          .read(filePreviewServiceProvider)
          .officePdfUrl(widget.file);
    });
  }

  Future<void> _quickLook() async {
    final bridge = ref.read(nativeFileBridgeProvider);
    final cancel = _cancel = FetchCancel();
    setState(() {
      _step = _QuickLookStep.downloading;
      _received = 0;
    });
    try {
      final path = _path ??= await ref
          .read(fileFetcherProvider)
          .download(
            widget.file,
            url: () =>
                ref.read(filePreviewServiceProvider).fileUrl(widget.file),
            cancel: cancel,
            onProgress: (received, total) {
              if (mounted) {
                setState(() {
                  _received = received;
                  _total = total;
                });
              }
            },
          );
      if (!mounted) {
        return;
      }
      if (!await bridge.canPreview(path)) {
        setState(() => _step = _QuickLookStep.unavailable);
        return;
      }
      setState(() => _step = _QuickLookStep.showing);
      await bridge.preview(path, title: widget.file.name);
      if (mounted) {
        widget.onQuickLookClosed();
      }
    } on FetchCancelledException {
      // Closed.
    } catch (_) {
      if (mounted) {
        setState(() => _step = _QuickLookStep.failed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    if (_server) {
      return FutureBuilder<Uri>(
        future: _converted,
        builder: (context, snapshot) {
          final error = snapshot.error;
          if (error is OfficePreviewException &&
              error.failure != OfficePreviewFailure.failed) {
            return PreviewUnavailableView(
              file: file,
              title: error.failure == OfficePreviewFailure.notConfigured
                  ? tr("Preview isn't available here")
                  : tr("This file can't be previewed"),
              message: tr('Download it to open it in an app on your device.'),
              onDownload: widget.onDownload,
            );
          }
          if (error != null) {
            return PreviewErrorView(
              file: file,
              title: tr("Couldn't make a preview"),
              onRetry: _convert,
              onDownload: widget.onDownload,
            );
          }
          final url = snapshot.data;
          if (url == null) {
            return PreviewStateLayout(
              key: const ValueKey('file-preview-loading'),
              leading: FileTypeTile(file: file, size: 72),
              title: file.name,
              message: tr('Converting for preview…'),
              below: const PreviewSpinner(),
            );
          }
          return PdfPreview(
            file: file,
            desktop: widget.desktop,
            onDownload: widget.onDownload,
            viewerBuilder: widget.pdfViewerBuilder,
            resolve: (onProgress, cancel) async => PdfUriSource(url),
          );
        },
      );
    }

    return switch (_step) {
      _QuickLookStep.downloading => PreviewProgressView(
        file: file,
        received: _received,
        total: _total,
        label: tr('Opening in Quick Look…'),
      ),
      _QuickLookStep.showing => PreviewStateLayout(
        key: const ValueKey('quick-look-showing'),
        leading: FileTypeTile(file: file, size: 72),
        title: file.name,
        message: tr('Opening in Quick Look…'),
        actions: [
          WeCordButton(
            label: tr('Show again'),
            icon: Icons.visibility_outlined,
            variant: WeCordButtonVariant.secondary,
            onPressed: () => unawaited(_quickLook()),
          ),
        ],
      ),
      _QuickLookStep.unavailable => PreviewUnavailableView(
        file: file,
        title: tr("This file can't be previewed"),
        message: tr('Download it to open it in an app on your device.'),
        onDownload: widget.onDownload,
        onOpenIn: widget.onOpenIn,
      ),
      _QuickLookStep.failed => PreviewErrorView(
        file: file,
        onRetry: () => unawaited(_quickLook()),
        onDownload: widget.onDownload,
      ),
    };
  }
}

/// No preview for this file: its tile, why, and Download / Open in.
class PreviewUnavailableView extends StatelessWidget {
  const PreviewUnavailableView({
    required this.file,
    required this.title,
    this.message,
    this.onDownload,
    this.onOpenIn,
    this.extra = const [],
    super.key,
  });

  final PreviewFile file;
  final String title;
  final String? message;
  final VoidCallback? onDownload;
  final VoidCallback? onOpenIn;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    return PreviewStateLayout(
      key: const ValueKey('file-preview-unavailable'),
      leading: FileTypeTile(file: file, size: 88),
      title: title,
      message: [file.name, if (message != null) message!].join('\n'),
      actions: [
        if (onDownload != null)
          WeCordButton(
            key: const ValueKey('file-preview-unavailable-download'),
            label: tr('Download'),
            icon: Icons.download_rounded,
            onPressed: onDownload,
          ),
        if (onOpenIn != null)
          WeCordButton(
            label: tr('Open in…'),
            icon: Icons.open_in_new_rounded,
            variant: WeCordButtonVariant.secondary,
            onPressed: onOpenIn,
          ),
        ...extra,
      ],
    );
  }
}

/// Any other file: what it is and Download / Open in, plus Quick Look on
/// Apple platforms (it reads many more formats than the app does).
class OtherFilePreview extends ConsumerStatefulWidget {
  const OtherFilePreview({
    required this.file,
    this.onDownload,
    this.onOpenIn,
    super.key,
  });

  final PreviewFile file;
  final VoidCallback? onDownload;
  final VoidCallback? onOpenIn;

  @override
  ConsumerState<OtherFilePreview> createState() => _OtherFilePreviewState();
}

class _OtherFilePreviewState extends ConsumerState<OtherFilePreview> {
  var _opening = false;

  Future<void> _quickLook() async {
    setState(() => _opening = true);
    final bridge = ref.read(nativeFileBridgeProvider);
    try {
      final path = await ref
          .read(fileFetcherProvider)
          .download(
            widget.file,
            url: () =>
                ref.read(filePreviewServiceProvider).fileUrl(widget.file),
          );
      if (await bridge.canPreview(path)) {
        await bridge.preview(path, title: widget.file.name);
      } else if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr("Quick Look can't show this file."))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Could not open the file. Try again.'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final quickLook = ref.watch(nativeFileBridgeProvider).isSupported;
    return PreviewUnavailableView(
      file: widget.file,
      title: tr('No preview for this file'),
      message: previewSubtitle(widget.file),
      onDownload: widget.onDownload,
      onOpenIn: widget.onOpenIn,
      extra: [
        if (quickLook)
          WeCordButton(
            key: const ValueKey('file-preview-quick-look'),
            label: tr('Quick Look'),
            icon: Icons.visibility_outlined,
            variant: WeCordButtonVariant.secondary,
            loading: _opening,
            onPressed: () => unawaited(_quickLook()),
          ),
      ],
    );
  }
}
