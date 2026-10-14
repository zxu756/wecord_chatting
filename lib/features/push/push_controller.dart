import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/push/push_gateway.dart';
import 'package:wecord/features/push/push_repository.dart';

/// Whether this device gets push notifications.
enum PushStatus {
  /// Not a browser with web push (or a native app, for now).
  unsupported,

  /// The browser blocked notifications for WeCord.
  denied,
  off,
  on,
}

/// This browser's push state. When subscribed, the subscription is saved
/// to the server again, so it follows whoever is signed in and survives
/// the browser rotating it.
final pushStatusProvider = FutureProvider.autoDispose<PushStatus>((ref) async {
  final gateway = ref.watch(pushGatewayProvider);
  if (!gateway.supported) {
    return PushStatus.unsupported;
  }
  if (gateway.permission == 'denied') {
    return PushStatus.denied;
  }
  final subscription = await gateway.currentSubscription();
  if (subscription == null) {
    return PushStatus.off;
  }
  try {
    await ref.read(pushRepositoryProvider).register(subscription);
  } catch (_) {
    // Saved again next time.
  }
  return PushStatus.on;
});

/// Why turning push on failed.
enum PushEnableError { denied, notConfigured, failed }

/// Asks for permission, subscribes this browser and saves it. Returns the
/// reason when that doesn't work.
Future<PushEnableError?> enablePush(WidgetRef ref) async {
  final gateway = ref.read(pushGatewayProvider);
  final repository = ref.read(pushRepositoryProvider);
  try {
    final permission = await gateway.requestPermission();
    if (permission != 'granted') {
      return PushEnableError.denied;
    }
    final key = await repository.vapidPublicKey();
    final PushSubscriptionInfo? subscription = await gateway.subscribe(key);
    if (subscription == null) {
      return PushEnableError.failed;
    }
    await repository.register(subscription);
    return null;
  } on PushNotConfiguredException {
    return PushEnableError.notConfigured;
  } catch (_) {
    return PushEnableError.failed;
  } finally {
    ref.invalidate(pushStatusProvider);
  }
}

/// Stops push on this browser.
Future<void> disablePush(WidgetRef ref) async {
  try {
    final endpoint = await ref.read(pushGatewayProvider).unsubscribe();
    if (endpoint != null) {
      await ref.read(pushRepositoryProvider).unregister(endpoint);
    }
  } finally {
    ref.invalidate(pushStatusProvider);
  }
}

/// Before signing out: this browser stops getting the account's pushes. The
/// browser keeps its subscription, which the next account signing in here
/// takes over.
Future<void> stopPushForSignOut(WidgetRef ref) async {
  try {
    final subscription = await ref
        .read(pushGatewayProvider)
        .currentSubscription();
    if (subscription != null) {
      await ref.read(pushRepositoryProvider).unregister(subscription.endpoint);
    }
  } catch (_) {
    // Signing out matters more.
  }
}
