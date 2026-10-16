import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:wecord/features/file_preview/file_actions.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/native_file_bridge.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/thumbnails.dart';
import 'package:wecord/features/file_preview/viewers/document_preview.dart';
import 'package:wecord/features/file_preview/viewers/pdf_preview.dart';

class FakeFilePreviewService implements FilePreviewService {
  final signed = <String>[];
  Object? officeError;
  final officeRequests = <String?>[];

  @override
  Future<Uri> fileUrl(PreviewFile file, {bool download = false}) async {
    signed.add(file.path);
    return Uri.parse(
      'https://files.test/${file.path}${download ? '?download=1' : ''}',
    );
  }

  @override
  Future<Uri> officePdfUrl(PreviewFile file) async {
    officeRequests.add(file.messageId);
    if (officeError case final error?) {
      throw error;
    }
    return Uri.parse('https://files.test/previews/${file.messageId}.pdf');
  }
}

/// Serves [contents] by path; files without contents fail like a broken
/// network until [contents] has them.
class FakeFileFetcher implements FileFetcher {
  FakeFileFetcher({this.contents = const {}, this.onDisk = true});

  Map<String, String> contents;
  final bool onDisk;
  final downloads = <String>[];

  /// Completes downloads when set; otherwise they finish at once.
  Completer<void>? gate;

  @override
  bool get cachesOnDisk => onDisk;

  @override
  Future<String?> cachedPath(PreviewFile file) async => null;

  @override
  Future<String> download(
    PreviewFile file, {
    required Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async {
    downloads.add(file.path);
    onProgress?.call(file.size ~/ 2, file.size);
    if (gate case final gate?) {
      await gate.future;
    }
    if (!contents.containsKey(file.path)) {
      throw const FileDownloadException(500);
    }
    return '/cache/${file.name}';
  }

  @override
  Future<FileBytes> readBytes(
    PreviewFile file, {
    required Future<Uri> Function() url,
    int? maxBytes,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async {
    final text = contents[file.path];
    if (text == null) {
      throw const FileDownloadException(500);
    }
    final bytes = utf8.encode(text);
    if (maxBytes != null && bytes.length > maxBytes) {
      return FileBytes(
        Uint8List.fromList(bytes.sublist(0, maxBytes)),
        truncated: true,
      );
    }
    return FileBytes(Uint8List.fromList(bytes), truncated: false);
  }
}

class FakeNativeFileBridge implements NativeFileBridge {
  FakeNativeFileBridge({this.isSupported = true, this.previewable = true});

  @override
  final bool isSupported;
  final bool previewable;
  final previewed = <String>[];
  Completer<void> dismissed = Completer<void>();

  @override
  Future<bool> canPreview(String path) async => previewable;

  @override
  Future<void> preview(String path, {required String title}) {
    previewed.add(path);
    return dismissed.future;
  }

  @override
  Future<bool> openIn(String path, {Rect? anchor}) async => true;

  @override
  Future<bool> exportCopy(String path, {required String name}) async => true;

  @override
  Future<Uint8List?> videoPoster(Uri url, {int maxSize = 480}) async => null;
}

class FakeThumbnailService implements ThumbnailService {
  @override
  Future<Uint8List?> thumbnailFor(PreviewFile file) async => null;
}

class FakeFileActions implements FileActions {
  final saved = <String>[];

  @override
  bool get canOpenIn => true;

  @override
  bool get canShare => true;

  @override
  Future<bool> openIn(
    PreviewFile file, {
    Rect? origin,
    DownloadProgress? onProgress,
  }) async => true;

  @override
  Future<SaveOutcome> save(
    PreviewFile file, {
    DownloadProgress? onProgress,
  }) async {
    saved.add(file.path);
    return SaveOutcome.saved;
  }

  @override
  Future<void> share(
    PreviewFile file, {
    Rect? origin,
    DownloadProgress? onProgress,
  }) async {}
}

/// Stands in for PDFium: shows where the PDF would come from.
Widget fakePdfViewerBuilder(
  BuildContext context,
  PdfSource source,
  PdfViewerController controller,
  PdfViewerParams params,
) {
  return Center(
    key: const ValueKey('fake-pdf-viewer'),
    child: Text(switch (source) {
      PdfFileSource(:final path) => 'pdf:$path',
      PdfUriSource(:final uri) => 'pdf:$uri',
    }),
  );
}

/// Overrides that keep the viewer off the network and native code.
List<Override> filePreviewOverrides({
  FakeFilePreviewService? service,
  FakeFileFetcher? fetcher,
  FakeNativeFileBridge? bridge,
  FakeFileActions? actions,
  bool convertsOnServer = false,
}) {
  return [
    filePreviewServiceProvider.overrideWithValue(
      service ?? FakeFilePreviewService(),
    ),
    fileFetcherProvider.overrideWithValue(fetcher ?? FakeFileFetcher()),
    nativeFileBridgeProvider.overrideWithValue(
      bridge ?? FakeNativeFileBridge(isSupported: false),
    ),
    thumbnailServiceProvider.overrideWithValue(FakeThumbnailService()),
    fileActionsProvider.overrideWithValue(actions ?? FakeFileActions()),
    pdfViewerBuilderProvider.overrideWithValue(fakePdfViewerBuilder),
    officeConvertsOnServerProvider.overrideWithValue(convertsOnServer),
  ];
}
