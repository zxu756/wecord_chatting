import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// The pictures of one board, decoded and kept while the board is open.
///
/// The painter asks for a picture by its storage path; until it has arrived
/// (downloaded and decoded) the painter draws a gray box, and the store
/// tells its listeners when something arrived so the board repaints.
class WhiteboardImageStore extends ChangeNotifier {
  WhiteboardImageStore({required this.download});

  /// Fetches the bytes of a stored picture.
  final Future<Uint8List> Function(String path) download;

  final _images = <String, ui.Image>{};
  final _loading = <String>{};
  final _failed = <String>{};
  var _disposed = false;

  /// The decoded picture, or null while it is loading (this starts loading).
  ui.Image? imageFor(String path) {
    final image = _images[path];
    if (image != null) {
      return image;
    }
    if (!_loading.contains(path) && !_failed.contains(path)) {
      _loading.add(path);
      _pending[path] = _load(path);
    }
    return null;
  }

  final _pending = <String, Future<void>>{};

  /// Waits until every picture in [paths] is decoded or has failed (before
  /// the board is drawn into an exported picture).
  Future<void> preload(Iterable<String> paths) async {
    for (final path in paths) {
      imageFor(path);
    }
    await Future.wait([
      for (final path in paths)
        if (_pending[path] != null) _pending[path]!,
    ]);
  }

  bool hasFailed(String path) => _failed.contains(path);

  /// Puts a picture the person just added, so it shows at once.
  Future<void> put(String path, Uint8List bytes) async {
    try {
      final image = await _decode(bytes);
      if (_disposed) {
        image.dispose();
        return;
      }
      _images[path]?.dispose();
      _images[path] = image;
      notifyListeners();
    } on Object {
      // The picture is shown from the server when it is asked for.
    }
  }

  Future<void> _load(String path) async {
    try {
      final bytes = await download(path);
      final image = await _decode(bytes);
      if (_disposed) {
        image.dispose();
        return;
      }
      _images[path] = image;
    } on Object {
      _failed.add(path);
    } finally {
      _loading.remove(path);
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }
}
