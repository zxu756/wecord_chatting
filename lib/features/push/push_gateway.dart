import 'package:wecord/features/push/push_gateway_stub.dart'
    if (dart.library.js_interop) 'package:wecord/features/push/push_gateway_web.dart';

/// A browser's push subscription, as the server stores it.
class PushSubscriptionInfo {
  const PushSubscriptionInfo({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  final String endpoint;

  /// The browser's public key, base64url.
  final String p256dh;

  /// The authentication secret, base64url.
  final String auth;
}

/// The browser side of web push: permission, the service worker and the
/// push subscription. Unsupported outside the web.
abstract interface class PushGateway {
  bool get supported;

  /// 'granted', 'denied' or 'default'; null where push isn't supported.
  String? get permission;

  /// The device's IANA time zone ('Asia/Shanghai'), which the server writes
  /// the times in this browser's notifications in. Null when it can't be
  /// told.
  String? get timeZone;

  Future<String?> requestPermission();

  /// This browser's current subscription, if any.
  Future<PushSubscriptionInfo?> currentSubscription();

  /// Subscribes with the server's VAPID public key (base64url).
  Future<PushSubscriptionInfo?> subscribe(String vapidPublicKey);

  /// Ends this browser's subscription. Returns its endpoint, if it had one.
  Future<String?> unsubscribe();

  /// App paths to open, from clicks on push notifications while the app
  /// was already open.
  Stream<String> get openRequests;
}

PushGateway createPushGateway() => createPlatformPushGateway();
