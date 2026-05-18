import 'dart:async';

import 'package:wecord/features/notifications/notification_service_base.dart';

class WebLocalNotificationService implements LocalNotificationService {
  WebLocalNotificationService({required WebNotificationGateway gateway})
    : _gateway = gateway;

  final WebNotificationGateway _gateway;
  final _tapController = StreamController<String>.broadcast();

  @override
  Future<NotificationPermissionStatus> permissionStatus() async {
    if (!_gateway.supported) {
      return NotificationPermissionStatus.unavailable;
    }
    return _statusFromBrowserPermission(_gateway.permission);
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    if (!_gateway.supported) {
      return NotificationPermissionStatus.unavailable;
    }
    final permission = await _gateway.requestPermission();
    return _statusFromBrowserPermission(permission);
  }

  @override
  Future<void> showMessageNotification({
    required String conversationId,
    required String title,
    required String body,
  }) async {
    if (await permissionStatus() != NotificationPermissionStatus.granted) {
      return;
    }
    _gateway.showNotification(
      title: title,
      body: body,
      tag: 'wecord-$conversationId',
      onClick: () {
        _tapController.add(conversationId);
      },
    );
  }

  @override
  Stream<String> notificationTaps() => _tapController.stream;

  @override
  void dispose() {
    unawaited(_tapController.close());
  }

  NotificationPermissionStatus _statusFromBrowserPermission(
    String? permission,
  ) {
    return switch (permission) {
      'granted' => NotificationPermissionStatus.granted,
      'denied' => NotificationPermissionStatus.denied,
      _ => NotificationPermissionStatus.notRequested,
    };
  }
}

abstract interface class WebNotificationGateway {
  bool get supported;

  String? get permission;

  Future<String?> requestPermission();

  void showNotification({
    required String title,
    required String body,
    required String tag,
    required void Function() onClick,
  });
}
