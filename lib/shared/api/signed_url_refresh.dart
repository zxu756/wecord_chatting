import 'dart:async';

import 'package:flutter/foundation.dart';

/// Signed storage URLs expire (chat images after an hour, emoji after a
/// day) while screens and providers keep them. When an image from one fails
/// to load it is signed again, at most once per [cooldown] for the same key,
/// so an image that is really gone does not re-sign in a loop.
class SignedUrlRefresher {
  SignedUrlRefresher({
    this.cooldown = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration cooldown;
  final DateTime Function() _clock;
  final _lastRefresh = <String, DateTime>{};

  /// Whether [key]'s URL should be signed again now; records the attempt.
  bool tryRefresh(String key) {
    final now = _clock();
    final last = _lastRefresh[key];
    if (last != null && now.difference(last) < cooldown) {
      return false;
    }
    _lastRefresh[key] = now;
    return true;
  }

  @visibleForTesting
  void reset() => _lastRefresh.clear();
}

/// Shared by images whose signed URLs are cached in providers.
final signedUrlRefresher = SignedUrlRefresher();

/// Runs [refresh] once the current frame is built when [key] may be signed
/// again. Image error callbacks can fire during build, where providers and
/// state must not change.
void refreshSignedUrlSoon(String key, VoidCallback refresh) {
  if (!signedUrlRefresher.tryRefresh(key)) {
    return;
  }
  scheduleMicrotask(refresh);
}
