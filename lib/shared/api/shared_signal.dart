import 'dart:async';

/// A "something changed" signal that many listeners share: [open] runs when
/// the first one listens (to subscribe to a Realtime channel, say) and the
/// function it returns runs when the last one stops, so a channel exists
/// once however many providers listen to it.
///
/// Changes that come in a burst are merged: the first goes out at once and
/// the rest of a [window] becomes one more at its end. A busy account
/// otherwise reloads whatever listens to the signal once per message.
class SharedSignal {
  SharedSignal(this._open, {this.window = const Duration(milliseconds: 300)});

  /// Starts the source. [notify] is what the source calls on every change;
  /// the returned function stops the source.
  final FutureOr<void> Function() Function(void Function() notify) _open;
  final Duration window;

  late final StreamController<void> _controller =
      StreamController<void>.broadcast(onListen: _start, onCancel: _stop);
  FutureOr<void> Function()? _close;
  Timer? _quiet;
  var _pending = false;

  /// Every listener gets every change; there is one source for all of them.
  Stream<void> get stream => _controller.stream;

  void _start() {
    _close = _open(_notify);
  }

  Future<void> _stop() async {
    _quiet?.cancel();
    _quiet = null;
    _pending = false;
    final close = _close;
    _close = null;
    await close?.call();
  }

  void _notify() {
    if (_controller.isClosed) {
      return;
    }
    if (_quiet != null) {
      _pending = true;
      return;
    }
    _controller.add(null);
    _quiet = Timer(window, _windowEnded);
  }

  void _windowEnded() {
    _quiet = null;
    if (_pending && _controller.hasListener) {
      _pending = false;
      _notify();
    }
  }
}
