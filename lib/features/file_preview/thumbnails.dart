import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/native_file_bridge.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/preview_platform_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/file_preview/preview_platform_web.dart'
    as platform;

/// Small pictures for file cards: a PDF's first page and a video's poster
/// frame (rendered once, then kept in memory and, on iOS and macOS, on
/// disk), and an SVG's own document, which the card draws.
abstract interface class ThumbnailService {
  /// Encoded image bytes (PNG or JPEG) for a PDF or video; the SVG source
  /// for an SVG file; null when there is no picture for this file.
  Future<Uint8List?> thumbnailFor(PreviewFile file);
}

/// SVGs past this size get their typed tile in the chat instead of a
/// drawing: the card would have to download all of it to draw a thumbnail.
const maxSvgThumbnailBytes = 512 * 1024;

/// PDFs past this size get their typed tile instead of a rendered page in
/// the chat (rendering would download most of them).
const maxPdfThumbnailBytes = 20 * 1024 * 1024;

final thumbnailServiceProvider = Provider<ThumbnailService>((ref) {
  return RenderingThumbnailService(
    service: ref.watch(filePreviewServiceProvider),
    fetcher: ref.watch(fileFetcherProvider),
    bridge: ref.watch(nativeFileBridgeProvider),
  );
});

class RenderingThumbnailService implements ThumbnailService {
  RenderingThumbnailService({
    required this.service,
    required this.fetcher,
    required this.bridge,
  });

  final FilePreviewService service;
  final FileFetcher fetcher;
  final NativeFileBridge bridge;

  static const _memoryLimit = 80;
  static const _pixelWidth = 480;

  final _memory = <String, Uint8List?>{};
  final _inFlight = <String, Future<Uint8List?>>{};
  var _running = 0;
  final _waiting = Queue<Completer<void>>();

  @override
  Future<Uint8List?> thumbnailFor(PreviewFile file) {
    final kind = file.kind;
    if (kind != PreviewKind.pdf &&
        kind != PreviewKind.video &&
        kind != PreviewKind.svg) {
      return Future.value();
    }
    final key = 'v1:${file.key}';
    if (_memory.containsKey(key)) {
      final bytes = _memory.remove(key);
      _memory[key] = bytes;
      return Future.value(bytes);
    }
    return _inFlight[key] ??= _load(key, file).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<Uint8List?> _load(String key, PreviewFile file) async {
    if (file.kind == PreviewKind.svg) {
      Uint8List? source;
      try {
        source = await _readSvg(file);
      } on Object {
        source = null;
      }
      _remember(key, source);
      return source;
    }
    var bytes = await platform.readThumbnail(key);
    if (bytes == null) {
      await _acquire();
      try {
        bytes = file.kind == PreviewKind.pdf
            ? await _renderPdf(file)
            : await _videoPoster(file);
      } on Object {
        bytes = null;
      } finally {
        _release();
      }
      if (bytes != null) {
        unawaited(platform.writeThumbnail(key, bytes));
      }
    }
    _remember(key, bytes);
    return bytes;
  }

  void _remember(String key, Uint8List? bytes) {
    _memory[key] = bytes;
    while (_memory.length > _memoryLimit) {
      _memory.remove(_memory.keys.first);
    }
  }

  /// The SVG document, or null when it is too big to draw in a card.
  Future<Uint8List?> _readSvg(PreviewFile file) async {
    await _acquire();
    try {
      final fetched = await fetcher.readBytes(
        file,
        url: () => service.fileUrl(file),
        maxBytes: maxSvgThumbnailBytes,
      );
      return fetched.truncated ? null : fetched.bytes;
    } finally {
      _release();
    }
  }

  /// At most two renders at once, so a chat full of PDFs stays smooth.
  Future<void> _acquire() async {
    if (_running < 2) {
      _running++;
      return;
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    await waiter.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }

  Future<Uint8List?> _videoPoster(PreviewFile file) async {
    final cached = await fetcher.cachedPath(file);
    final url = cached != null ? Uri.file(cached) : await service.fileUrl(file);
    if (kIsWeb) {
      return platform.captureWebVideoPoster(url, _pixelWidth);
    }
    return bridge.videoPoster(url, maxSize: _pixelWidth);
  }

  Future<Uint8List?> _renderPdf(PreviewFile file) async {
    if (file.size > maxPdfThumbnailBytes) {
      return null;
    }
    await pdfrxFlutterInitialize();
    final cached = await fetcher.cachedPath(file);
    final PdfDocument document;
    if (cached != null) {
      document = await PdfDocument.openFile(cached);
    } else if (fetcher.cachesOnDisk && file.size <= 8 * 1024 * 1024) {
      // Keep small files whole: opening one from the card is then instant.
      final path = await fetcher.download(
        file,
        url: () => service.fileUrl(file),
      );
      document = await PdfDocument.openFile(path);
    } else {
      // Larger ones: only the parts the first page needs, where the
      // platform can ask for ranges.
      document = await PdfDocument.openUri(
        await service.fileUrl(file),
        preferRangeAccess: !kIsWeb,
      );
    }
    try {
      if (document.pages.isEmpty) {
        return null;
      }
      final page = document.pages.first;
      final scale = _pixelWidth / page.width;
      final rendered = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
        width: (page.width * scale).round(),
        height: (page.height * scale).round(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (rendered == null) {
        return null;
      }
      try {
        final image = await rendered.createImage();
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          return data?.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      } finally {
        rendered.dispose();
      }
    } finally {
      await document.dispose();
    }
  }
}
