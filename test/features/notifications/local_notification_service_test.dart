import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';

void main() {
  test(
    'fake notification service records shown message notifications',
    () async {
      final service = FakeLocalNotificationService();

      await service.showMessageNotification(
        conversationId: 'conversation-1',
        title: 'Ada',
        body: 'Hi',
      );

      expect(service.shownNotifications.single.title, 'Ada');
      expect(service.shownNotifications.single.body, 'Hi');
      expect(service.shownNotifications.single.payload, 'conversation-1');
    },
  );

  test('fake notification service exposes permission status', () async {
    final service = FakeLocalNotificationService(
      status: NotificationPermissionStatus.denied,
    );

    expect(
      await service.permissionStatus(),
      NotificationPermissionStatus.denied,
    );
  });

  test('fake notification service closes tap stream on dispose', () async {
    final service = FakeLocalNotificationService();
    final done = expectLater(service.notificationTaps(), emitsDone);

    service.dispose();

    await done;
  });
}
