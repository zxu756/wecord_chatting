import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/pwa/pwa_gateway.dart';
import 'package:wecord/features/pwa/pwa_providers.dart';

/// While signed in: shows the unread count on the installed app's icon (and
/// in the tab title) where the browser supports it.
class PwaShellListener extends ConsumerStatefulWidget {
  const PwaShellListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PwaShellListener> createState() => _PwaShellListenerState();
}

class _PwaShellListenerState extends ConsumerState<PwaShellListener> {
  /// Shells alive right now. One shell can replace another within a frame
  /// (the old one is disposed after the new one starts), and the badge must
  /// not blink off between them.
  static var _alive = 0;

  // Kept for dispose, where a widget's ref can no longer be used.
  late final PwaGateway _gateway;

  @override
  void initState() {
    super.initState();
    _alive++;
    _gateway = ref.read(pwaGatewayProvider);
    // The count that is already there when the shell opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _gateway.setBadge(ref.read(appBadgeCountProvider));
      }
    });
  }

  @override
  void dispose() {
    // Signed out (the shell goes away): nothing left to count.
    final gateway = _gateway;
    _alive--;
    Future.microtask(() {
      if (_alive == 0) {
        gateway.setBadge(0);
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appBadgeCountProvider, (previous, count) {
      _gateway.setBadge(count);
    });
    return widget.child;
  }
}
