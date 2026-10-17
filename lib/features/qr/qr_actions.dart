import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/qr/qr_image_export.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Save image" and "Share" for a QR card: take the picture of the card
/// under [boundaryKey] and hand it to the platform. What happened is said
/// in a line underneath (a screen reader hears it too).
class QrCardActions extends ConsumerStatefulWidget {
  const QrCardActions({
    required this.boundaryKey,
    required this.fileName,
    required this.shareText,
    this.enabled = true,
    super.key,
  });

  /// The RepaintBoundary around the QrCard.
  final GlobalKey boundaryKey;

  /// The picture's name, without the extension.
  final String fileName;

  /// The text sent along when sharing (the link).
  final String shareText;

  final bool enabled;

  @override
  ConsumerState<QrCardActions> createState() => _QrCardActionsState();
}

class _QrCardActionsState extends ConsumerState<QrCardActions> {
  var _busy = false;
  String? _status;
  final _shareKey = GlobalKey();

  Future<void> _run(
    Future<QrExportOutcome> Function(QrImageExporter exporter, Uint8List png)
    action,
  ) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    String message;
    try {
      final png = await captureBoundaryPng(widget.boundaryKey);
      if (png == null) {
        message = tr("Couldn't make the picture. Try again.");
      } else {
        final outcome = await action(ref.read(qrImageExporterProvider), png);
        message = switch (outcome) {
          QrExportOutcome.savedToPhotos => tr('Saved to Photos'),
          QrExportOutcome.saved => tr('Saved'),
          QrExportOutcome.downloadStarted => tr('Download started'),
          QrExportOutcome.shared => '',
          QrExportOutcome.cancelled => '',
          QrExportOutcome.failed => tr("Couldn't save the picture. Try again."),
        };
      }
    } on Object {
      message = tr("Couldn't make the picture. Try again.");
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _status = message.isEmpty ? null : message;
    });
  }

  Rect? _shareOrigin() {
    final box = _shareKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final enabled = widget.enabled && !_busy;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: WeCordButton(
                key: const ValueKey('qr-save-image'),
                label: tr('Save image'),
                icon: Icons.download_rounded,
                variant: WeCordButtonVariant.secondary,
                expand: true,
                onPressed: enabled
                    ? () => unawaited(
                        _run(
                          (exporter, png) =>
                              exporter.save(png, name: widget.fileName),
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: KeyedSubtree(
                key: _shareKey,
                child: WeCordButton(
                  key: const ValueKey('qr-share'),
                  label: tr('Share'),
                  icon: Icons.ios_share_rounded,
                  expand: true,
                  onPressed: enabled
                      ? () => unawaited(
                          _run(
                            (exporter, png) => exporter.share(
                              png,
                              name: widget.fileName,
                              text: widget.shareText,
                              origin: _shareOrigin(),
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _status!,
                key: const ValueKey('qr-status'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ),
          ),
      ],
    );
  }
}
