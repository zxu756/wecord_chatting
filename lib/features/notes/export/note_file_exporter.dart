import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wecord/features/notes/export/note_download.dart';

/// What handing a file over did.
enum NoteExportOutcome {
  /// The browser took over the download.
  downloadStarted,

  /// The system share sheet took the file.
  shared,

  /// The person closed the share sheet.
  cancelled,

  /// This platform cannot do it.
  failed,
}

/// A name for a file made of a note: the title without the characters file
/// systems dislike, at most 60 characters, and the extension.
String noteExportFileName(String title, String extension) {
  var name = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  name = name.replaceAll(RegExp(r'^\.+'), '');
  final characters = name.characters;
  if (characters.length > 60) {
    name = characters.take(60).toString().trim();
  }
  return '${name.isEmpty ? 'note' : name}.$extension';
}

/// Hands a file to the person: a download in the browser, the share sheet on
/// Apple devices (and everywhere else). Tests swap in a fake.
abstract interface class NoteFileExporter {
  Future<NoteExportOutcome> export({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    Rect? origin,
  });
}

final noteFileExporterProvider = Provider<NoteFileExporter>(
  (ref) => const PlatformNoteFileExporter(),
);

class PlatformNoteFileExporter implements NoteFileExporter {
  const PlatformNoteFileExporter();

  @override
  Future<NoteExportOutcome> export({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    Rect? origin,
  }) async {
    if (kIsWeb) {
      return downloadNoteFile(fileName, bytes, mimeType)
          ? NoteExportOutcome.downloadStarted
          : NoteExportOutcome.failed;
    }
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
          fileNameOverrides: [fileName],
          sharePositionOrigin: origin,
        ),
      );
      return result.status == ShareResultStatus.dismissed
          ? NoteExportOutcome.cancelled
          : NoteExportOutcome.shared;
    } on Object {
      return NoteExportOutcome.failed;
    }
  }
}
