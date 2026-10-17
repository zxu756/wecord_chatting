import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Why the camera cannot scan.
enum QrCameraProblem {
  /// Camera access is off for WeCord.
  permissionDenied,

  /// No camera, or it cannot be used.
  unavailable,
}

/// Builds the live camera view of the scanner. [onCode] gets each text read
/// from a QR code; [onProblem] says the camera cannot be used. Tests swap
/// in a fake (a camera cannot run there).
typedef QrCameraBuilder =
    Widget Function(
      BuildContext context, {
      required ValueChanged<String> onCode,
      required ValueChanged<QrCameraProblem> onProblem,
    });

final qrCameraBuilderProvider = Provider<QrCameraBuilder>(
  (ref) => mobileScannerCamera,
);

/// The real camera: mobile_scanner on iOS, macOS and the web.
Widget mobileScannerCamera(
  BuildContext context, {
  required ValueChanged<String> onCode,
  required ValueChanged<QrCameraProblem> onProblem,
}) {
  return MobileScannerCamera(onCode: onCode, onProblem: onProblem);
}

/// A mobile_scanner view that reads QR codes only, with a torch button where
/// the camera has one.
class MobileScannerCamera extends StatefulWidget {
  const MobileScannerCamera({
    required this.onCode,
    required this.onProblem,
    super.key,
  });

  final ValueChanged<String> onCode;
  final ValueChanged<QrCameraProblem> onProblem;

  @override
  State<MobileScannerCamera> createState() => _MobileScannerCameraState();
}

class _MobileScannerCameraState extends State<MobileScannerCamera> {
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  var _problemReported = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _report(QrCameraProblem problem) {
    if (_problemReported) {
      return;
    }
    _problemReported = true;
    // After this frame: the error builder runs while building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onProblem(problem);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          fit: BoxFit.cover,
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final text = barcode.rawValue;
              if (text != null && text.isNotEmpty) {
                widget.onCode(text);
                return;
              }
            }
          },
          errorBuilder: (context, error) {
            _report(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? QrCameraProblem.permissionDenied
                  : QrCameraProblem.unavailable,
            );
            return const SizedBox.shrink();
          },
          placeholderBuilder: (context) => const Center(
            child: SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
        // Phones have a torch; desktops and browsers do not.
        if (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android))
          Positioned(
            right: 12,
            bottom: 12,
            child: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, _) {
                if (state.torchState == TorchState.unavailable) {
                  return const SizedBox.shrink();
                }
                final on = state.torchState == TorchState.on;
                return WeCordIconButton(
                  key: const ValueKey('qr-torch'),
                  icon: on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  tooltip: on
                      ? tr('Turn off the light')
                      : tr('Turn on the light'),
                  variant: WeCordButtonVariant.onPaper,
                  size: 44,
                  iconSize: 22,
                  onPressed: _controller.toggleTorch,
                );
              },
            ),
          ),
      ],
    );
  }
}
