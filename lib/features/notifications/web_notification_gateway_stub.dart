import 'package:wecord/features/notifications/web_local_notification_service.dart';

WebNotificationGateway createWebNotificationGateway() {
  return const UnsupportedWebNotificationGateway();
}

class UnsupportedWebNotificationGateway implements WebNotificationGateway {
  const UnsupportedWebNotificationGateway();

  @override
  bool get supported => false;

  @override
  String? get permission => null;

  @override
  Future<String?> requestPermission() async => null;

  @override
  void showNotification({
    required String title,
    required String body,
    required String tag,
    required void Function() onClick,
  }) {}
}
