import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Signed storage URLs by object, reused while they are valid, so images
/// scrolled out of a chat and back do not sign (and load) again.
class SignedUrlCache {
  SignedUrlCache({
    this.maxEntries = 500,
    this.lifetime = const Duration(minutes: 50),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxEntries;

  /// Shorter than the URLs' own hour, so a reused URL never expires
  /// mid-load.
  final Duration lifetime;
  final DateTime Function() _clock;
  final _entries = <String, (String, DateTime)>{};

  static String keyFor(String bucket, String path) => '$bucket/$path';

  /// The cached URL for [key], when still valid.
  String? peek(String key) {
    final entry = _entries[key];
    if (entry == null) {
      return null;
    }
    if (!_clock().isBefore(entry.$2)) {
      _entries.remove(key);
      return null;
    }
    return entry.$1;
  }

  /// The URL for [key], signing it with [sign] when none is cached.
  Future<String> get(String key, Future<String> Function() sign) async {
    final cached = peek(key);
    if (cached != null) {
      return cached;
    }
    final url = await sign();
    _entries.remove(key);
    _entries[key] = (url, _clock().add(lifetime));
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return url;
  }

  /// Forgets [key]'s URL (it failed to load).
  void evict(String key) => _entries.remove(key);

  void clear() => _entries.clear();
}

/// The signed-in user's signed chat media URLs (dropped on sign-out).
final chatSignedUrlCacheProvider = Provider<SignedUrlCache>(
  (ref) => SignedUrlCache(),
);

/// The sizes images turned out to have, by URL or storage path, so a
/// message shown again reserves the right space before its image loads
/// and the list does not jump.
class ImageDimensionCache {
  ImageDimensionCache({this.maxEntries = 1000});

  final int maxEntries;
  final _sizes = <String, Size>{};

  Size? operator [](String key) => _sizes[key];

  void remember(String key, Size size) {
    if (size.isEmpty) {
      return;
    }
    _sizes.remove(key);
    _sizes[key] = size;
    while (_sizes.length > maxEntries) {
      _sizes.remove(_sizes.keys.first);
    }
  }

  void clear() => _sizes.clear();
}

final imageDimensionCache = ImageDimensionCache();
