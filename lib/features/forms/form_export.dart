import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wecord/features/forms/form_download.dart';

/// What exporting the answers did.
enum FormExportOutcome {
  /// The browser took over the download.
  downloadStarted,

  /// The system share sheet took the file.
  shared,

  /// The person closed the share sheet.
  cancelled,

  /// This platform cannot do it.
  failed,
}

/// Hands a CSV file to the person: a download in the browser, the share
/// sheet on Apple devices (and everywhere else). Tests swap in a fake.
abstract interface class FormFileExporter {
  Future<FormExportOutcome> exportCsv({
    required String fileName,
    required String contents,
    Rect? origin,
  });
}

final formFileExporterProvider = Provider<FormFileExporter>(
  (ref) => const PlatformFormFileExporter(),
);

class PlatformFormFileExporter implements FormFileExporter {
  const PlatformFormFileExporter();

  @override
  Future<FormExportOutcome> exportCsv({
    required String fileName,
    required String contents,
    Rect? origin,
  }) async {
    if (kIsWeb) {
      return downloadFormCsv(fileName, contents)
          ? FormExportOutcome.downloadStarted
          : FormExportOutcome.failed;
    }
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              utf8.encode(contents),
              mimeType: 'text/csv',
              name: fileName,
            ),
          ],
          fileNameOverrides: [fileName],
          sharePositionOrigin: origin,
        ),
      );
      return result.status == ShareResultStatus.dismissed
          ? FormExportOutcome.cancelled
          : FormExportOutcome.shared;
    } on Object {
      return FormExportOutcome.failed;
    }
  }
}
