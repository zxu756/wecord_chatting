// A manual check of the native Quick Look plugin (channel
// `wecord/quicklook`) without signing in: opens the file viewer for a
// local file through the real bridge. Put a file named `sample.docx` into
// the app's Documents folder first, e.g. on the iOS simulator:
//
//   flutter build ios --simulator --debug -t tool/quick_look_demo/main.dart
//   xcrun simctl install booted build/ios/iphonesimulator/Runner.app
//   cp sample.docx "$(xcrun simctl get_app_container booted <bundle id> data)/Documents/"
//   xcrun simctl launch booted <bundle id>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

class _LocalFetcher implements FileFetcher {
  _LocalFetcher(this.path);

  final String path;

  @override
  bool get cachesOnDisk => true;

  @override
  Future<String?> cachedPath(PreviewFile file) async => path;

  @override
  Future<String> download(
    PreviewFile file, {
    required Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async => path;

  @override
  Future<FileBytes> readBytes(
    PreviewFile file, {
    required Future<Uri> Function() url,
    int? maxBytes,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async => FileBytes(await File(path).readAsBytes(), truncated: false);
}

class _NoLinks implements FilePreviewService {
  @override
  Future<Uri> fileUrl(PreviewFile file, {bool download = false}) async =>
      Uri.file(file.path);

  @override
  Future<Uri> officePdfUrl(PreviewFile file) =>
      throw const OfficePreviewException(OfficePreviewFailure.notConfigured);
}

var _opened = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final documents = await getApplicationDocumentsDirectory();
  final path = '${documents.path}/sample.docx';
  final exists = File(path).existsSync();
  final file = PreviewFile(
    bucket: 'local',
    path: path,
    name: 'Quarterly plan.docx',
    mimeType:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    size: exists ? File(path).lengthSync() : 0,
    senderName: 'Quick Look check',
    sentAt: DateTime.now(),
  );
  runApp(
    ProviderScope(
      overrides: [
        fileFetcherProvider.overrideWithValue(_LocalFetcher(path)),
        filePreviewServiceProvider.overrideWithValue(_NoLinks()),
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        darkTheme: WeCordTheme.dark(),
        home: Builder(
          builder: (context) {
            // Opens by itself once, so the check needs no tap.
            if (exists && !_opened) {
              _opened = true;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => openFilePreview(context, file: file),
              );
            }
            return Scaffold(
              body: Center(
                child: FilledButton(
                  key: const ValueKey('open-sample'),
                  onPressed: exists
                      ? () => openFilePreview(context, file: file)
                      : null,
                  child: Text(exists ? 'Open sample.docx' : 'No sample.docx'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
