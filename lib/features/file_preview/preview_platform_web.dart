// The viewer's browser side: no file cache of its own (the HTTP cache
// keeps signed links' responses), downloads through an anchor, and video
// posters drawn from a hidden <video> onto a canvas.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/preview_file.dart';

FileFetcher createFileFetcher(http.Client client) => WebFileFetcher(client);

ImageProvider localFileImage(String path) => NetworkImage(path);

VideoPlayerController localVideoController(String path) =>
    VideoPlayerController.networkUrl(Uri.parse(path));

Future<Uint8List> readLocalBytes(String path) {
  throw UnsupportedError('No local files on the web');
}

/// Starts a download of [url] (a signed link with `download=<name>`).
Future<void> triggerBrowserDownload(Uri url, String name) async {
  final anchor = web.HTMLAnchorElement()
    ..href = url.toString()
    ..download = name
    ..rel = 'noopener'
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}

Future<Uint8List?> readThumbnail(String key) async => null;

Future<void> writeThumbnail(String key, Uint8List bytes) async {}

/// A frame from early in the video at [url], as JPEG, or null when the
/// browser can't load it or won't let the page read its pixels.
Future<Uint8List?> captureWebVideoPoster(Uri url, int maxSize) async {
  final video = web.HTMLVideoElement()
    ..crossOrigin = 'anonymous'
    ..muted = true
    ..preload = 'auto'
    ..playsInline = true;
  try {
    final loaded = Completer<void>();
    final seeked = Completer<void>();
    video.onLoadedData.first.then((_) {
      if (!loaded.isCompleted) loaded.complete();
    });
    video.onError.first.then((_) {
      if (!loaded.isCompleted) loaded.completeError('load');
      if (!seeked.isCompleted) seeked.completeError('load');
    });
    video.onSeeked.first.then((_) {
      if (!seeked.isCompleted) seeked.complete();
    });
    video.src = url.toString();
    await loaded.future.timeout(const Duration(seconds: 15));
    final duration = video.duration;
    final at = duration.isFinite && duration > 0
        ? (duration / 10).clamp(0.0, 1.0)
        : 0.0;
    video.currentTime = at;
    await seeked.future.timeout(const Duration(seconds: 10));
    final width = video.videoWidth;
    final height = video.videoHeight;
    if (width == 0 || height == 0) {
      return null;
    }
    final scale = (maxSize / (width > height ? width : height)).clamp(0.0, 1.0);
    final canvas = web.HTMLCanvasElement()
      ..width = (width * scale).round()
      ..height = (height * scale).round();
    final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    context.drawImage(video, 0, 0, canvas.width, canvas.height);
    final dataUrl = canvas.toDataURL('image/jpeg', 0.82.toJS);
    final comma = dataUrl.indexOf(',');
    if (comma < 0) {
      return null;
    }
    return base64Decode(dataUrl.substring(comma + 1));
  } on Object {
    return null;
  } finally {
    video
      ..removeAttribute('src')
      ..load();
  }
}

class WebFileFetcher implements FileFetcher {
  WebFileFetcher(this._client);

  final http.Client _client;

  @override
  bool get cachesOnDisk => false;

  @override
  Future<String?> cachedPath(PreviewFile file) async => null;

  @override
  Future<String> download(
    PreviewFile file, {
    required Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) {
    throw UnsupportedError('The web keeps no downloaded files');
  }

  @override
  Future<FileBytes> readBytes(
    PreviewFile file, {
    required Future<Uri> Function() url,
    int? maxBytes,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async {
    return streamBytes(
      _client,
      await url(),
      maxBytes: maxBytes,
      onProgress: onProgress,
      cancel: cancel,
      knownSize: file.size,
    );
  }
}
