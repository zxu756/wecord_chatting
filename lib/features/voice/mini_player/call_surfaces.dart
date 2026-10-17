import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The places showing the current call full size right now: the voice
/// room, a chat's call card. While none is on screen (the user went to
/// another page), the mini player takes over.
final callSurfacesProvider = NotifierProvider<CallSurfaces, Set<Object>>(
  CallSurfaces.new,
);

class CallSurfaces extends Notifier<Set<Object>> {
  @override
  Set<Object> build() => const {};

  /// Changes are made after the current frame, since surfaces come and go
  /// while the tree is being built or taken down.
  void show(Object token) => _set(token, true);

  void hide(Object token) => _set(token, false);

  void _set(Object token, bool shown) {
    Future.microtask(() {
      if (!ref.mounted || state.contains(token) == shown) {
        return;
      }
      state = shown ? {...state, token} : ({...state}..remove(token));
    });
  }
}

/// Marks [child] as a place that shows the call. It counts only while it
/// is really on screen: not when another page covers it.
class CallSurface extends ConsumerStatefulWidget {
  const CallSurface({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CallSurface> createState() => _CallSurfaceState();
}

class _CallSurfaceState extends ConsumerState<CallSurface> {
  final _token = Object();
  late final CallSurfaces _surfaces;

  @override
  void initState() {
    super.initState();
    _surfaces = ref.read(callSurfacesProvider.notifier);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pages under an opaque page have their tickers turned off.
    if (TickerMode.valuesOf(context).enabled) {
      _surfaces.show(_token);
    } else {
      _surfaces.hide(_token);
    }
  }

  @override
  void dispose() {
    _surfaces.hide(_token);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
