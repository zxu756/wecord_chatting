import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app (or the browser tab) can be seen right now.
///
/// Background work that only matters to someone looking (polling a list,
/// the "I am here" heartbeat) listens to this and stops while it is false,
/// then catches up when it turns true again. It is false when the app is
/// hidden, paused in the background or being detached; it stays true while
/// merely inactive (a system dialog, the app switcher, another window in
/// front), because the app is still on screen then.
class AppVisibility with WidgetsBindingObserver {
  AppVisibility._();

  static final instance = AppVisibility._();

  final _visible = ValueNotifier<bool>(true);
  var _attached = false;

  /// True while the app can be seen.
  ValueListenable<bool> get visible {
    _attach();
    return _visible;
  }

  void _attach() {
    if (_attached) {
      return;
    }
    try {
      final binding = WidgetsBinding.instance;
      binding.addObserver(this);
      _attached = true;
      _visible.value = isVisibleState(binding.lifecycleState);
    } on Object {
      // No widgets binding (a plain Dart test): always visible.
    }
  }

  /// Whether an app in [state] can be seen; unknown counts as visible.
  static bool isVisibleState(AppLifecycleState? state) {
    return switch (state) {
      null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => false,
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible.value = isVisibleState(state);
  }
}

/// [AppVisibility.visible]; tests replace it with a notifier of their own.
final appVisibleProvider = Provider<ValueListenable<bool>>(
  (ref) => AppVisibility.instance.visible,
);
