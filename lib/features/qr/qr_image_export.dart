import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wecord/features/qr/qr_download.dart';

/// What saving or sharing a QR card's picture did.
enum QrExportOutcome {
  /// Added to the photo library (iOS).
  savedToPhotos,

  /// A copy was saved where the person chose (macOS).
  saved,

  /// The browser took over the download.
  downloadStarted,

  /// The system share sheet took it.
  shared,

  /// The person cancelled.
  cancelled,

  /// This platform cannot do it.
  failed,
}

/// Saves and shares the picture of a QR card, the way each platform does it:
/// the photo library on iOS, a save panel on macOS, a download in the
/// browser, and the share sheet. Tests swap in a fake.
abstract interface class QrImageExporter {
  Future<QrExportOutcome> save(Uint8List png, {required String name});

  Future<QrExportOutcome> share(
    Uint8List png, {
    required String name,
    String? text,
    Rect? origin,
  });
}

final qrImageExporterProvider = Provider<QrImageExporter>(
  (ref) => const PlatformQrImageExporter(),
);

class PlatformQrImageExporter implements QrImageExporter {
  const PlatformQrImageExporter();

  @override
  Future<QrExportOutcome> save(Uint8List png, {required String name}) async {
    final fileName = '$name.png';
    try {
      if (kIsWeb) {
        return downloadQrImage(fileName, png)
            ? QrExportOutcome.downloadStarted
            : QrExportOutcome.failed;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android) {
        if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
          return QrExportOutcome.cancelled;
        }
        await Gal.putImageBytes(png, name: name);
        return QrExportOutcome.savedToPhotos;
      }
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PNG', extensions: ['png']),
        ],
      );
      if (location == null) {
        return QrExportOutcome.cancelled;
      }
      await XFile.fromData(
        png,
        mimeType: 'image/png',
        name: fileName,
      ).saveTo(location.path);
      return QrExportOutcome.saved;
    } on Object {
      return QrExportOutcome.failed;
    }
  }

  @override
  Future<QrExportOutcome> share(
    Uint8List png, {
    required String name,
    String? text,
    Rect? origin,
  }) async {
    final fileName = '$name.png';
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
          fileNameOverrides: [fileName],
          text: text,
          sharePositionOrigin: origin,
        ),
      );
      return switch (result.status) {
        ShareResultStatus.dismissed => QrExportOutcome.cancelled,
        ShareResultStatus.unavailable when kIsWeb => await save(
          png,
          name: name,
        ),
        _ => QrExportOutcome.shared,
      };
    } on Object {
      // Browsers without the Web Share API download instead.
      return kIsWeb ? save(png, name: name) : QrExportOutcome.failed;
    }
  }
}

/// The picture of the [RepaintBoundary] under [key], at [pixelRatio] times
/// its size, as PNG bytes; null when it is not on screen.
Future<Uint8List?> captureBoundaryPng(
  GlobalKey key, {
  double pixelRatio = 3,
}) async {
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) {
    return null;
  }
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
