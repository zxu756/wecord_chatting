import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/share_target/share_target_gateway_stub.dart'
    if (dart.library.js_interop) 'package:wecord/features/share_target/share_target_gateway_web.dart';
import 'package:wecord/features/share_target/shared_content.dart';

/// Where the service worker (web/wecord_sw.js) leaves what another app
/// shared with WeCord, until the app's share page reads it. Only the web has
/// a "Share to WeCord"; elsewhere there is never anything waiting. Tests use
/// a fake.
abstract interface class ShareTargetGateway {
  /// What is waiting to be shared, or null when nothing is.
  Future<SharedContent?> read();

  /// Forgets what is waiting (it was sent, or dropped).
  Future<void> clear();
}

final shareTargetGatewayProvider = Provider<ShareTargetGateway>(
  (ref) => createPlatformShareTargetGateway(),
);

/// What is waiting to be shared. Read again by invalidating it.
final pendingShareProvider = FutureProvider.autoDispose<SharedContent?>((ref) {
  return ref.watch(shareTargetGatewayProvider).read();
});
