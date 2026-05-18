import 'dart:async';

enum NotificationPermissionStatus { notRequested, granted, denied, unavailable }

abstract interface class LocalNotificationService {
  Future<NotificationPermissionStatus> permissionStatus();

  Future<NotificationPermissionStatus> requestPermission();

  Future<void> showMessageNotification({
    required String conversationId,
    required String title,
    required String body,
  });

  Stream<String> notificationTaps();

  void dispose();
}

class FakeLocalNotificationService implements LocalNotificationService {
  FakeLocalNotificationService({
    NotificationPermissionStatus status =
        NotificationPermissionStatus.notRequested,
  }) : _status = status;

  final shownNotifications = <ShownMessageNotification>[];
  final _tapController = StreamController<String>.broadcast();
  NotificationPermissionStatus _status;

  @override
  Future<NotificationPermissionStatus> permissionStatus() async => _status;

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    if (_status == NotificationPermissionStatus.notRequested) {
      _status = NotificationPermissionStatus.granted;
    }
    return _status;
  }

  @override
  Future<void> showMessageNotification({
    required String conversationId,
    required String title,
    required String body,
  }) async {
    shownNotifications.add(
      ShownMessageNotification(
        title: title,
        body: body,
        payload: conversationId,
      ),
    );
  }

  @override
  Stream<String> notificationTaps() => _tapController.stream;

  @override
  void dispose() {
    unawaited(_tapController.close());
  }

  void emitTap(String conversationId) {
    _tapController.add(conversationId);
  }
}

class ShownMessageNotification {
  const ShownMessageNotification({
    required this.title,
    required this.body,
    required this.payload,
  });

  final String title;
  final String body;
  final String payload;
}
