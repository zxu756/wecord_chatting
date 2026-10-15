import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/presence/presence_repository.dart';

/// Sets [presenceInactiveProvider] after [idleAfter] without keyboard or
/// pointer input, and clears it on the next input, so an Online user shows
/// as Idle while away. Only on desktop and web, where the app stays open
/// in the background; phones leave presence when the app is closed.
class PresenceActivityListener extends ConsumerStatefulWidget {
  const PresenceActivityListener({
    required this.child,
    this.idleAfter = defaultIdleAfter,
    this.enabled,
    super.key,
  });

  static const defaultIdleAfter = Duration(minutes: 10);

  final Widget child;
  final Duration idleAfter;

  /// Defaults to desktop and web.
  final bool? enabled;

  @override
  ConsumerState<PresenceActivityListener> createState() =>
      _PresenceActivityListenerState();
}

class _PresenceActivityListenerState
    extends ConsumerState<PresenceActivityListener> {
  /// Checks every tenth of [PresenceActivityListener.idleAfter] (pointer
  /// moves come often, so input only resets a counter).
  Timer? _timer;
  var _quietTicks = 0;

  static const _ticksToIdle = 10;

  bool get _enabled =>
      widget.enabled ??
      (kIsWeb ||
          switch (defaultTargetPlatform) {
            TargetPlatform.macOS ||
            TargetPlatform.windows ||
            TargetPlatform.linux => true,
            _ => false,
          });

  @override
  void initState() {
    super.initState();
    if (_enabled) {
      HardwareKeyboard.instance.addHandler(_onKey);
      _timer = Timer.periodic(widget.idleAfter ~/ _ticksToIdle, _tick);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_enabled) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _onInput();
    return false;
  }

  void _onInput() {
    _quietTicks = 0;
    if (ref.read(presenceInactiveProvider)) {
      ref.read(presenceInactiveProvider.notifier).state = false;
    }
  }

  void _tick(Timer timer) {
    if (!mounted) {
      return;
    }
    _quietTicks += 1;
    if (_quietTicks >= _ticksToIdle && !ref.read(presenceInactiveProvider)) {
      ref.read(presenceInactiveProvider.notifier).state = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) {
      return widget.child;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onInput(),
      onPointerMove: (_) => _onInput(),
      onPointerHover: (_) => _onInput(),
      onPointerSignal: (_) => _onInput(),
      child: widget.child,
    );
  }
}
