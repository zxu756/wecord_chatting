import 'dart:collection';

/// Detectors for the auth and routing problems that matter most. Each takes
/// the time as an argument (so tests need no clock) and says when something
/// is wrong, at most once per cooldown so a loop gives one report.

/// A sign-out nobody asked for. Sign-outs the app starts itself (the Sign out
/// button, deleting the account, cancelling two-step verification) call
/// [expectSignOut] first; a signed-out event outside that window is
/// unexpected: a refresh token that stopped working, a session revoked
/// elsewhere, or a bug.
class UnexpectedSignOutDetector {
  UnexpectedSignOutDetector({this.window = const Duration(seconds: 30)});

  /// How long after [expectSignOut] a signed-out event counts as asked for.
  final Duration window;

  DateTime? _expectedUntil;

  void expectSignOut(DateTime now, {Duration? within}) {
    _expectedUntil = now.add(within ?? window);
  }

  /// A signed-in event ends the expectation.
  void signedIn() => _expectedUntil = null;

  /// True when this signed-out event was not asked for.
  bool signedOut(DateTime now) {
    final until = _expectedUntil;
    return until == null || now.isAfter(until);
  }
}

/// More than [threshold] token refreshes within [window].
class RefreshBurstDetector {
  RefreshBurstDetector({
    this.threshold = 5,
    this.window = const Duration(minutes: 1),
  });

  final int threshold;
  final Duration window;

  final Queue<DateTime> _times = Queue();
  DateTime? _quietUntil;

  /// Records a refresh; returns how many there were in the window when that
  /// is a burst (and not yet reported), else null.
  int? record(DateTime now) {
    _times.addLast(now);
    while (_times.isNotEmpty && now.difference(_times.first) > window) {
      _times.removeFirst();
    }
    final quiet = _quietUntil;
    if (_times.length > threshold && (quiet == null || now.isAfter(quiet))) {
      _quietUntil = now.add(window);
      return _times.length;
    }
    return null;
  }
}

/// The same redirect (from one route to another) more than [threshold] times
/// within [window].
class RedirectLoopDetector {
  RedirectLoopDetector({
    this.threshold = 8,
    this.window = const Duration(seconds: 5),
    this.cooldown = const Duration(minutes: 1),
  });

  final int threshold;
  final Duration window;
  final Duration cooldown;

  final Map<String, Queue<DateTime>> _seen = {};
  final Map<String, DateTime> _quietUntil = {};

  /// Records a redirect; returns how many times it happened in the window
  /// when that is a loop (and not yet reported), else null.
  int? record(String from, String to, DateTime now) {
    final key = '$from->$to';
    final times = _seen.putIfAbsent(key, Queue.new)..addLast(now);
    while (times.isNotEmpty && now.difference(times.first) > window) {
      times.removeFirst();
    }
    // Keeps the map from growing with every distinct pair.
    if (_seen.length > 64) {
      _seen.removeWhere((_, q) => q.isEmpty || now.difference(q.last) > window);
    }
    final quiet = _quietUntil[key];
    if (times.length > threshold && (quiet == null || now.isAfter(quiet))) {
      _quietUntil[key] = now.add(cooldown);
      return times.length;
    }
    return null;
  }
}
