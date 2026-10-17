import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/qr/qr_camera.dart';
import 'package:wecord/features/qr/qr_image_decoder.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Reads a QR code from a picture's bytes; tests swap in a fake.
typedef QrImageDecoder = Future<String?> Function(Uint8List bytes);

final qrImageDecoderProvider = Provider<QrImageDecoder>(
  (ref) => decodeQrFromImageBytes,
);

/// Opens the scanner: the camera, and "Choose from photos". Returns the text
/// of the QR code that was read, or null when it was closed.
Future<String?> showQrScannerSheet(BuildContext context) {
  return showWeCordSheet<String>(
    context,
    title: tr('Scan'),
    builder: (context, _) => const QrScannerSheet(),
  );
}

/// The content of the scanner sheet.
class QrScannerSheet extends ConsumerStatefulWidget {
  const QrScannerSheet({super.key});

  @override
  ConsumerState<QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends ConsumerState<QrScannerSheet> {
  QrCameraProblem? _problem;
  var _decoding = false;
  var _done = false;
  String? _message;

  void _finish(String text) {
    if (_done || !mounted) {
      return;
    }
    _done = true;
    Navigator.of(context).pop(text);
  }

  Future<void> _choosePhoto() async {
    if (_decoding) {
      return;
    }
    setState(() {
      _decoding = true;
      _message = null;
    });
    String? text;
    var failed = false;
    try {
      final picked = await ref.read(imagePickerServiceProvider).pickImage();
      if (picked == null) {
        if (mounted) {
          setState(() => _decoding = false);
        }
        return;
      }
      text = await ref.read(qrImageDecoderProvider)(picked.bytes);
    } on Object {
      failed = true;
    }
    if (!mounted) {
      return;
    }
    if (text != null && text.isNotEmpty) {
      _finish(text);
      return;
    }
    setState(() {
      _decoding = false;
      _message = failed
          ? tr("Couldn't open that picture. Try another.")
          : tr('No QR code found in that picture.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final camera = ref.watch(qrCameraBuilderProvider);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const ValueKey('qr-scanner-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: AspectRatio(
                  aspectRatio: 0.9,
                  child: ClipPath(
                    clipper: ShapeBorderClipper(
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(WeCordRadii.xxl),
                      ),
                    ),
                    child: ColoredBox(
                      color: c.well,
                      child: _problem != null
                          ? _CameraProblem(problem: _problem!)
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                camera(
                                  context,
                                  onCode: _finish,
                                  onProblem: (problem) {
                                    if (mounted) {
                                      setState(() => _problem = problem);
                                    }
                                  },
                                ),
                                const IgnorePointer(child: _ScanFrame()),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _message ?? tr('Point the camera at a QR code.'),
                key: const ValueKey('qr-scanner-hint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: _message == null ? c.muted : c.dangerText,
                ),
              ),
            ),
            const SizedBox(height: 14),
            WeCordButton(
              key: const ValueKey('qr-choose-photo'),
              label: tr('Choose from photos'),
              icon: Icons.photo_library_outlined,
              variant: WeCordButtonVariant.secondary,
              expand: true,
              loading: _decoding,
              onPressed: _decoding ? null : () => unawaited(_choosePhoto()),
            ),
          ],
        ),
      ),
    );
  }
}

/// What shows instead of the camera when it cannot be used.
class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.problem});

  final QrCameraProblem problem;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final denied = problem == QrCameraProblem.permissionDenied;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThingAvatar(
              icon: denied
                  ? Icons.no_photography_outlined
                  : Icons.videocam_off_outlined,
              size: 56,
              color: c.raised,
              foregroundColor: c.muted,
            ),
            const SizedBox(height: 14),
            Text(
              denied ? tr('Camera access is off') : tr('No camera available'),
              key: const ValueKey('qr-camera-problem'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              denied
                  ? tr(
                      'Allow the camera for WeCord in your system settings, or '
                      'choose a picture with a QR code instead.',
                    )
                  : tr('You can still choose a picture with a QR code.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Four corner marks around the middle of the camera view.
class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScanFramePainter(
        color: Colors.white,
        shadow: Colors.black.withValues(alpha: 0.35),
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  const _ScanFramePainter({required this.color, required this.shadow});

  final Color color;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.62;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
    final arm = side * 0.2;
    for (final (paint, width) in [
      (Paint()..color = shadow, 7.0),
      (Paint()..color = color, 4.0),
    ]) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      final path = Path();
      for (final (corner, dx, dy) in [
        (rect.topLeft, 1.0, 1.0),
        (rect.topRight, -1.0, 1.0),
        (rect.bottomLeft, 1.0, -1.0),
        (rect.bottomRight, -1.0, -1.0),
      ]) {
        path
          ..moveTo(corner.dx + dx * arm, corner.dy)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(corner.dx, corner.dy + dy * arm);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ScanFramePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.shadow != shadow;
}
