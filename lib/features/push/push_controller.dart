import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/push/push_gateway.dart';
import 'package:wecord/features/push/push_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Whether this device gets push notifications.
enum PushStatus {
  /// Not a browser with web push (or a native app, for now).
  unsupported,

  /// The browser blocked notifications for WeCord.
  denied,
  off,
  on,
}

/// The language the server writes this browser's notifications in: 'zh'
/// when the app is in Chinese (by choice or following the device), else
/// 'en'.
String pushLanguageCode(AppLanguage language) =>
    resolvesToChinese(language) ? 'zh' : 'en';

/// This browser's push state. When subscribed, the subscription is saved
/// to the server again, so it follows whoever is signed in, survives the
/// browser rotating it and carries the app's language, which it saves
/// again when the language setting changes.
final pushStatusProvider = FutureProvider.autoDispose<PushStatus>((ref) async {
  final gateway = ref.watch(pushGatewayProvider);
  final repository = ref.read(pushRepositoryProvider);
  if (!gateway.supported) {
    return PushStatus.unsupported;
  }
  if (gateway.permission == 'denied') {
    return PushStatus.denied;
  }
  // The language the server last heard, and the subscription it heard it
  // for. The setting loads a moment after start-up, so the saved choice is
  // read directly, and its arrival is not taken for a change.
  String? savedCode;
  PushSubscriptionInfo? saved;
  ref.listen(appLanguageProvider, (previous, language) {
    final code = pushLanguageCode(language);
    final subscription = saved;
    if (subscription == null || code == savedCode) {
      return;
    }
    savedCode = code;
    unawaited(
      repository
          .register(subscription, language: code)
          .catchError((Object _) {}),
    );
  });
  final subscription = await gateway.currentSubscription();
  if (subscription == null) {
    return PushStatus.off;
  }
  final code = pushLanguageCode(
    await ref
            .read(appLanguageStoreProvider)
            .load()
            .catchError((Object _) => null) ??
        ref.read(appLanguageProvider),
  );
  try {
    await repository.register(subscription, language: code);
    savedCode = code;
    saved = subscription;
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
    await repository.register(
      subscription,
      language: pushLanguageCode(ref.read(appLanguageProvider)),
    );
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
