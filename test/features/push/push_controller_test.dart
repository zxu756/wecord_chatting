import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/push/push_controller.dart';
import 'package:wecord/features/push/push_gateway.dart';
import 'package:wecord/features/push/push_repository.dart';
import 'package:wecord/features/push/push_settings_tile.dart';
import 'package:wecord/shared/ui/ui.dart';

const _subscription = PushSubscriptionInfo(
  endpoint: 'https://push.example.com/abc',
  p256dh: 'key',
  auth: 'secret',
);

class FakePushGateway implements PushGateway {
  @override
  bool supported = true;

  @override
  String? permission = 'default';

  String grant = 'granted';
  PushSubscriptionInfo? current;
  final subscribedWith = <String>[];
  var unsubscribes = 0;

  @override
  Future<String?> requestPermission() async => permission = grant;

  @override
  Future<PushSubscriptionInfo?> currentSubscription() async => current;

  @override
  Future<PushSubscriptionInfo?> subscribe(String vapidPublicKey) async {
    subscribedWith.add(vapidPublicKey);
    return current = _subscription;
  }

  @override
  Future<String?> unsubscribe() async {
    unsubscribes++;
    final endpoint = current?.endpoint;
    current = null;
    return endpoint;
  }

  @override
  Stream<String> get openRequests => const Stream.empty();
}

class FakePushRepository implements PushRepository {
  bool configured = true;
  final registered = <String>[];
  final unregistered = <String>[];
  final notified = <String>[];
  final calls = <String>[];

  @override
  Future<String> vapidPublicKey() async {
    if (!configured) {
      throw const PushNotConfiguredException();
    }
    return 'vapid-public';
  }

  @override
  Future<void> register(
    PushSubscriptionInfo subscription, {
    String? userAgent,
  }) async {
    registered.add(subscription.endpoint);
  }

  @override
  Future<void> unregister(String endpoint) async => unregistered.add(endpoint);

  @override
  Future<void> notifySent(String messageId) async => notified.add(messageId);

  @override
  Future<void> notifyCall(String callId) async => calls.add(callId);
}

void main() {
  late FakePushGateway gateway;
  late FakePushRepository repository;

  setUp(() {
    gateway = FakePushGateway();
    repository = FakePushRepository();
  });

  Future<WidgetRef> pumpTile(WidgetTester tester) async {
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushGatewayProvider.overrideWithValue(gateway),
          pushRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const PushSettingsTile();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return capturedRef;
  }

  WeCordSwitch tile(WidgetTester tester) => tester.widget(
    find.descendant(
      of: find.byKey(const ValueKey('push-notifications')),
      matching: find.byType(WeCordSwitch),
    ),
  );

  testWidgets('hidden where web push is unsupported', (tester) async {
    gateway.supported = false;
    await pumpTile(tester);

    expect(find.byKey(const ValueKey('push-notifications')), findsNothing);
  });

  testWidgets('turning it on subscribes and saves the browser', (tester) async {
    await pumpTile(tester);
    expect(tile(tester).value, isFalse);

    await tester.tap(find.byKey(const ValueKey('push-notifications')));
    await tester.pumpAndSettle();

    expect(gateway.subscribedWith, ['vapid-public']);
    expect(repository.registered, contains(_subscription.endpoint));
    expect(tile(tester).value, isTrue);

    await tester.tap(find.byKey(const ValueKey('push-notifications')));
    await tester.pumpAndSettle();
    expect(gateway.unsubscribes, 1);
    expect(repository.unregistered, [_subscription.endpoint]);
    expect(tile(tester).value, isFalse);
  });

  testWidgets('explains a refused permission or a server without push', (
    tester,
  ) async {
    gateway.grant = 'default';
    await pumpTile(tester);
    await tester.tap(find.byKey(const ValueKey('push-notifications')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allow notifications'), findsOneWidget);
    expect(gateway.subscribedWith, isEmpty);

    gateway.grant = 'granted';
    repository.configured = false;
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold)),
    ).removeCurrentSnackBar();
    await tester.tap(find.byKey(const ValueKey('push-notifications')));
    await tester.pumpAndSettle();
    expect(find.textContaining("aren't set up"), findsOneWidget);
  });

  testWidgets('blocked notifications disable the switch', (tester) async {
    gateway.permission = 'denied';
    await pumpTile(tester);

    expect(tile(tester).onChanged, isNull);
    expect(find.textContaining('blocked'), findsOneWidget);
  });

  testWidgets('an existing subscription is saved for whoever signs in', (
    tester,
  ) async {
    gateway.current = _subscription;
    final ref = await pumpTile(tester);

    expect(tile(tester).value, isTrue);
    expect(repository.registered, [_subscription.endpoint]);

    await stopPushForSignOut(ref);
    expect(repository.unregistered, [_subscription.endpoint]);
    expect(gateway.unsubscribes, 0);
  });
}
