import 'dart:async';

import 'package:flutter/foundation.dart';

/// The "I am here" heartbeat of a visible, online client.
///
/// The server counts a member online (for `@here` and for circle discovery)
/// when their last `touch_presence(true)` is under three minutes old, so a
/// client that is online and can be seen tells it every [interval], and says
/// `touch_presence(false)` when it stops. While the app is hidden nobody is
/// looking, so the timer stops and the client says it left; when the app can
/// be seen again it beats at once and starts over. Going offline (Invisible,
/// online status hidden) stops it the same way.
class PresenceHeartbeat {
  PresenceHeartbeat({
    required this.beat,
    required this._visible,
    this.interval = const Duration(minutes: 2),
  }) {
    _visible.addListener(_update);
  }

  /// Sends `touch_presence(online)`.
  final void Function(bool online) beat;
  final Duration interval;
  final ValueListenable<bool> _visible;

  Timer? _timer;
  var _wanted = false;

  /// Whether the timer is running right now.
  bool get beating => _timer != null;

  /// Whether this client should be counted online (it announces a status).
  set wanted(bool value) {
    _wanted = value;
    _update();
  }

  void _update() {
    final shouldBeat = _wanted && _visible.value;
    if (shouldBeat && _timer == null) {
      beat(true);
      _timer = Timer.periodic(interval, (_) => beat(true));
    } else if (!shouldBeat && _timer != null) {
      _timer?.cancel();
      _timer = null;
      beat(false);
    }
  }

  void dispose() {
    _visible.removeListener(_update);
    _wanted = false;
    if (_timer != null) {
      _timer?.cancel();
      _timer = null;
      beat(false);
    }
  }
}
