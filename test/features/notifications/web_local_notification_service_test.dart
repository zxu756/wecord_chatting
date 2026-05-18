import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/web_local_notification_service.dart';

void main() {
  test(
    'reports unavailable when browser notifications are unsupported',
    () async {
      final service = WebLocalNotificationService(
        gateway: FakeWebNotificationGateway(supported: false),
      );

      expect(
        await service.permissionStatus(),
        NotificationPermissionStatus.unavailable,
      );
      expect(
        await service.requestPermission(),
        NotificationPermissionStatus.unavailable,
      );
    },
  );

  test('maps browser notification permission states', () async {
    final gateway = FakeWebNotificationGateway(permission: 'default');
    final service = WebLocalNotificationService(gateway: gateway);

    expect(
      await service.permissionStatus(),
      NotificationPermissionStatus.notRequested,
    );

    gateway.permission = 'granted';

    expect(
      await service.permissionStatus(),
      NotificationPermissionStatus.granted,
    );

    gateway.permission = 'denied';

    expect(
      await service.permissionStatus(),
      NotificationPermissionStatus.denied,
    );
  });

  test('requests browser permission before reporting granted', () async {
    final gateway = FakeWebNotificationGateway(
      permission: 'default',
      requestedPermission: 'granted',
    );
    final service = WebLocalNotificationService(gateway: gateway);

    expect(
      await service.requestPermission(),
      NotificationPermissionStatus.granted,
    );
    expect(gateway.requestPermissionCalls, 1);
    expect(gateway.permission, 'granted');
  });

  test('shows web notifications only after permission is granted', () async {
    final gateway = FakeWebNotificationGateway(permission: 'default');
    final service = WebLocalNotificationService(gateway: gateway);

    await service.showMessageNotification(
      conversationId: 'c1',
      title: 'Ada',
      body: 'Hi',
    );

    expect(gateway.shownNotifications, isEmpty);

    gateway.permission = 'granted';
    await service.showMessageNotification(
      conversationId: 'c1',
      title: 'Ada',
      body: 'Hi',
    );

    expect(gateway.shownNotifications.single.title, 'Ada');
    expect(gateway.shownNotifications.single.body, 'Hi');
    expect(gateway.shownNotifications.single.tag, 'wecord-c1');
  });

  test('emits notification taps from browser click callbacks', () async {
    final gateway = FakeWebNotificationGateway(permission: 'granted');
    final service = WebLocalNotificationService(gateway: gateway);
    final tap = expectLater(service.notificationTaps(), emits('c1'));

    await service.showMessageNotification(
      conversationId: 'c1',
      title: 'Ada',
      body: 'Hi',
    );
    gateway.shownNotifications.single.click();

    await tap;
  });
}

class FakeWebNotificationGateway implements WebNotificationGateway {
  FakeWebNotificationGateway({
    this.supported = true,
    this.permission = 'default',
    this.requestedPermission = 'default',
  });

  @override
  final bool supported;

  @override
  String permission;

  String requestedPermission;
  int requestPermissionCalls = 0;
  final shownNotifications = <ShownWebNotification>[];

  @override
  Future<String> requestPermission() async {
    requestPermissionCalls += 1;
    permission = requestedPermission;
    return permission;
  }

  @override
  void showNotification({
    required String title,
    required String body,
    required String tag,
    required void Function() onClick,
  }) {
    shownNotifications.add(
      ShownWebNotification(title: title, body: body, tag: tag, click: onClick),
    );
  }
}

class ShownWebNotification {
  const ShownWebNotification({
    required this.title,
    required this.body,
    required this.tag,
    required this.click,
  });

  final String title;
  final String body;
  final String tag;
  final void Function() click;
}
