import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;
import 'package:wecord/features/notifications/web_local_notification_service.dart';

WebNotificationGateway createWebNotificationGateway() {
  return const BrowserWebNotificationGateway();
}

class BrowserWebNotificationGateway implements WebNotificationGateway {
  const BrowserWebNotificationGateway();

  @override
  bool get supported => !globalContext['Notification'].isUndefinedOrNull;

  @override
  String? get permission => supported ? web.Notification.permission : null;

  @override
  Future<String?> requestPermission() async {
    if (!supported) {
      return null;
    }
    final permission = await web.Notification.requestPermission().toDart;
    return permission.toDart;
  }

  @override
  void showNotification({
    required String title,
    required String body,
    required String tag,
    required void Function() onClick,
  }) {
    final notification = web.Notification(
      title,
      web.NotificationOptions(body: body, tag: tag, icon: 'icons/Icon-192.png'),
    );
    notification.onclick = ((web.Event _) {
      web.window.focus();
      onClick();
      notification.close();
    }).toJS;
  }
}
