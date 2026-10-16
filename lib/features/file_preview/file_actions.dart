import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/native_file_bridge.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/web_share.dart';
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
  /// Whether Share is offered: on the web only where the browser has the
  /// Web Share API (elsewhere Download covers it).
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
    webShare: platform.createWebShare(),
  );
});

/// Files up to this size are shared themselves on the web; bigger ones as
/// a link (they would have to be downloaded into memory first).
const maxWebShareFileBytes = 25 * 1024 * 1024;

class PlatformFileActions implements FileActions {
  PlatformFileActions({
    required this.service,
    required this.fetcher,
    required this.bridge,
    this.webShare = const UnavailableWebShare(),
    bool? isWeb,
  }) : _isWeb = isWeb ?? kIsWeb;

  final FilePreviewService service;
  final FileFetcher fetcher;
  final NativeFileBridge bridge;
  final WebShare webShare;
  final bool _isWeb;

  bool get _isIOS => !_isWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  bool get canShare => !_isWeb || webShare.isAvailable;

  @override
  bool get canOpenIn => !_isWeb;

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
    if (_isWeb) {
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
    if (_isWeb) {
      return _shareOnWeb(file, onProgress);
    }
    final path = await _local(file, onProgress);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, name: file.name, mimeType: file.mimeType)],
        sharePositionOrigin: origin,
      ),
    );
  }

  /// The file itself when it is small enough to fetch, its link otherwise
  /// (or when fetching it fails).
  Future<void> _shareOnWeb(
    PreviewFile file,
    DownloadProgress? onProgress,
  ) async {
    Uint8List? bytes;
    if (file.size <= maxWebShareFileBytes) {
      try {
        final fetched = await fetcher.readBytes(
          file,
          url: () => service.fileUrl(file),
          maxBytes: maxWebShareFileBytes,
          onProgress: onProgress,
        );
        bytes = fetched.truncated ? null : fetched.bytes;
      } on Object {
        bytes = null;
      }
    }
    await webShare.share(
      name: file.name,
      mimeType: file.mimeType,
      url: await service.fileUrl(file),
      bytes: bytes,
    );
  }

  @override
  Future<bool> openIn(
    PreviewFile file, {
    Rect? origin,
    DownloadProgress? onProgress,
  }) async {
    if (_isWeb) {
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
