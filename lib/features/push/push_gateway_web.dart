import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:wecord/features/push/push_gateway.dart';

PushGateway createPlatformPushGateway() => BrowserPushGateway();

/// Web push through `push_sw.js`, registered under its own scope so it
/// never controls the app's pages.
class BrowserPushGateway implements PushGateway {
  static const _workerUrl = 'push_sw.js';
  static const _scope = 'push/';

  StreamController<String>? _openRequests;

  @override
  bool get supported =>
      !globalContext['Notification'].isUndefinedOrNull &&
      !globalContext['PushManager'].isUndefinedOrNull &&
      !web.window.navigator['serviceWorker'].isUndefinedOrNull;

  @override
  String? get permission => supported ? web.Notification.permission : null;

  @override
  Future<String?> requestPermission() async {
    if (!supported) {
      return null;
    }
    return (await web.Notification.requestPermission().toDart).toDart;
  }

  Future<web.ServiceWorkerRegistration> _registration() {
    return web.window.navigator.serviceWorker
        .register(_workerUrl.toJS, web.RegistrationOptions(scope: _scope))
        .toDart;
  }

  @override
  Future<PushSubscriptionInfo?> currentSubscription() async {
    if (!supported) {
      return null;
    }
    final registration = await _registration();
    final subscription = await registration.pushManager
        .getSubscription()
        .toDart;
    return subscription == null ? null : _info(subscription);
  }

  @override
  Future<PushSubscriptionInfo?> subscribe(String vapidPublicKey) async {
    if (!supported) {
      return null;
    }
    final registration = await _registration();
    final subscription = await registration.pushManager
        .subscribe(
          web.PushSubscriptionOptionsInit(
            userVisibleOnly: true,
            applicationServerKey: _base64UrlDecode(vapidPublicKey).toJS,
          ),
        )
        .toDart;
    return _info(subscription);
  }

  @override
  Future<String?> unsubscribe() async {
    if (!supported) {
      return null;
    }
    final registration = await _registration();
    final subscription = await registration.pushManager
        .getSubscription()
        .toDart;
    if (subscription == null) {
      return null;
    }
    final endpoint = subscription.endpoint;
    await subscription.unsubscribe().toDart;
    return endpoint;
  }

  @override
  Stream<String> get openRequests {
    final existing = _openRequests;
    if (existing != null) {
      return existing.stream;
    }
    final controller = StreamController<String>.broadcast();
    _openRequests = controller;
    if (supported) {
      web.window.navigator.serviceWorker.addEventListener(
        'message',
        (web.MessageEvent event) {
          final data = event.data;
          if (data == null || !data.isA<JSObject>()) {
            return;
          }
          final object = data as JSObject;
          final type = object['type'];
          final url = object['url'];
          if (type.isA<JSString>() &&
              (type as JSString).toDart == 'wecord-open' &&
              url.isA<JSString>()) {
            final path = _appPath((url as JSString).toDart);
            if (path != null) {
              controller.add(path);
            }
          }
        }.toJS,
      );
    }
    return controller.stream;
  }

  static PushSubscriptionInfo? _info(web.PushSubscription subscription) {
    final p256dh = subscription.getKey('p256dh');
    final auth = subscription.getKey('auth');
    if (p256dh == null || auth == null) {
      return null;
    }
    return PushSubscriptionInfo(
      endpoint: subscription.endpoint,
      p256dh: _base64UrlEncode(p256dh.toDart.asUint8List()),
      auth: _base64UrlEncode(auth.toDart.asUint8List()),
    );
  }
}

/// The route in a WeCord URL like `https://…/#/chats/x`.
String? _appPath(String url) {
  final uri = Uri.tryParse(url);
  final fragment = uri?.fragment ?? '';
  return fragment.startsWith('/') ? fragment : null;
}

String _base64UrlEncode(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _base64UrlDecode(String value) =>
    base64Url.decode(base64Url.normalize(value));
