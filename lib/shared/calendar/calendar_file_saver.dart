import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wecord/features/circles/calendar_file_download.dart';

/// What happened to a calendar file.
enum CalendarSaveResult {
  /// The browser downloaded it.
  downloaded,

  /// The system share sheet took it (Calendar is one of its targets).
  shared,

  /// Nothing could be done.
  failed,
}

/// Hands an .ics file to the person: a download in the browser, the system
/// share sheet on iOS and macOS (which offers Calendar). Tests swap in a
/// fake.
abstract interface class CalendarFileSaver {
  Future<CalendarSaveResult> save({
    required String fileName,
    required String contents,
    Rect? origin,
  });
}

final calendarFileSaverProvider = Provider<CalendarFileSaver>(
  (ref) => const PlatformCalendarFileSaver(),
);

class PlatformCalendarFileSaver implements CalendarFileSaver {
  const PlatformCalendarFileSaver();

  @override
  Future<CalendarSaveResult> save({
    required String fileName,
    required String contents,
    Rect? origin,
  }) async {
    if (kIsWeb) {
      return downloadCalendarFile(fileName, contents)
          ? CalendarSaveResult.downloaded
          : CalendarSaveResult.failed;
    }
    try {
      final data = Uint8List.fromList(utf8.encode(contents));
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(data, mimeType: 'text/calendar', name: fileName),
          ],
          fileNameOverrides: [fileName],
          sharePositionOrigin: origin,
        ),
      );
      return CalendarSaveResult.shared;
    } on Object {
      return CalendarSaveResult.failed;
    }
  }
}
