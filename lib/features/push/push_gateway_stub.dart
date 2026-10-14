import 'package:wecord/features/push/push_gateway.dart';

PushGateway createPlatformPushGateway() => const UnsupportedPushGateway();

class UnsupportedPushGateway implements PushGateway {
  const UnsupportedPushGateway();

  @override
  bool get supported => false;

  @override
  String? get permission => null;

  @override
  Future<String?> requestPermission() async => null;

  @override
  Future<PushSubscriptionInfo?> currentSubscription() async => null;

  @override
  Future<PushSubscriptionInfo?> subscribe(String vapidPublicKey) async => null;

  @override
  Future<String?> unsubscribe() async => null;

  @override
  Stream<String> get openRequests => const Stream.empty();
}
