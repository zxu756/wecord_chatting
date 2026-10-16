import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/native_file_bridge.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/preview_platform_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/file_preview/preview_platform_web.dart'
    as platform;

/// What saving did, for the confirmation shown afterwards.
enum SaveOutcome {
  /// Added to the photo library (iOS images and videos).
  savedToPhotos,

  /// A copy was saved where the person chose.
  saved,

  /// The browser took over the download.
  downloadStarted,

  /// The person cancelled.
  cancelled,
}

/// The viewer's Download / Share / Open in actions, done the way each
/// platform expects.
abstract interface class FileActions {
  /// Whether Share is offered (not on the web: Download covers it).
  bool get canShare;

  /// Whether "Open in…" is its own action (the web downloads instead).
  bool get canOpenIn;

  Future<SaveOutcome> save(PreviewFile file, {DownloadProgress? onProgress});

  Future<void> share(
    PreviewFile file, {
    Rect? origin,
    DownloadProgress? onProgress,
  });

  /// False when no app can open it.
  Future<bool> openIn(
    PreviewFile file, {
    Rect? origin,
    DownloadProgress? onProgress,
  });
}

final fileActionsProvider = Provider<FileActions>((ref) {
  return PlatformFileActions(
    service: ref.watch(filePreviewServiceProvider),
    fetcher: ref.watch(fileFetcherProvider),
    bridge: ref.watch(nativeFileBridgeProvider),
  );
});

class PlatformFileActions implements FileActions {
  PlatformFileActions({
    required this.service,
    required this.fetcher,
    required this.bridge,
  });

  final FilePreviewService service;
  final FileFetcher fetcher;
  final NativeFileBridge bridge;

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  bool get canShare => !kIsWeb;

  @override
  bool get canOpenIn => !kIsWeb;

  Future<String> _local(PreviewFile file, DownloadProgress? onProgress) {
    return fetcher.download(
      file,
      url: () => service.fileUrl(file),
      onProgress: onProgress,
    );
  }

  @override
  Future<SaveOutcome> save(
    PreviewFile file, {
    DownloadProgress? onProgress,
  }) async {
    if (kIsWeb) {
      await platform.triggerBrowserDownload(
        await service.fileUrl(file, download: true),
        file.name,
      );
      return SaveOutcome.downloadStarted;
    }
    final path = await _local(file, onProgress);
    if (_isIOS && file.kind.isGalleryMedia) {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        return SaveOutcome.cancelled;
      }
      if (file.kind == PreviewKind.image) {
        await Gal.putImage(path);
      } else {
        await Gal.putVideo(path);
      }
      return SaveOutcome.savedToPhotos;
    }
    if (bridge.isSupported) {
      return await bridge.exportCopy(path, name: file.name)
          ? SaveOutcome.saved
          : SaveOutcome.cancelled;
    }
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
    return SaveOutcome.saved;
  }

  @override
  Future<void> share(
    PreviewFile file, {
    Rect? origin,
    DownloadProgress? onProgress,
  }) async {
    final path = await _local(file, onProgress);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, name: file.name, mimeType: file.mimeType)],
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  Future<bool> openIn(
    PreviewFile file, {
    Rect? origin,
    DownloadProgress? onProgress,
  }) async {
    if (kIsWeb) {
      await save(file);
      return true;
    }
    final path = await _local(file, onProgress);
    if (bridge.isSupported) {
      return bridge.openIn(path, anchor: origin);
    }
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
    return true;
  }
}
