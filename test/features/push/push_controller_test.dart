import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/push/push_controller.dart';
import 'package:wecord/features/push/push_gateway.dart';
import 'package:wecord/features/push/push_repository.dart';
import 'package:wecord/features/push/push_settings_tile.dart';
import 'package:wecord/shared/l10n/l10n.dart';
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

  @override
  String? timeZone = 'Asia/Shanghai';

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
  final languages = <String>[];
  final timeZones = <String?>[];
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
    String language = 'en',
    String? timeZone,
  }) async {
    registered.add(subscription.endpoint);
    languages.add(language);
    timeZones.add(timeZone);
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

  Future<WidgetRef> pumpTile(
    WidgetTester tester, {
    AppLanguage language = AppLanguage.english,
  }) async {
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushGatewayProvider.overrideWithValue(gateway),
          pushRepositoryProvider.overrideWithValue(repository),
          appLanguageStoreProvider.overrideWithValue(
            InMemoryAppLanguageStore(language),
          ),
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

  testWidgets('the browser is saved with the app language', (tester) async {
    gateway.current = _subscription;
    await pumpTile(tester, language: AppLanguage.chinese);
    expect(repository.languages, ['zh']);
  });

  testWidgets('turning push on saves the app language too', (tester) async {
    await pumpTile(tester, language: AppLanguage.chinese);
    await tester.tap(find.byKey(const ValueKey('push-notifications')));
    await tester.pumpAndSettle();
    expect(repository.languages, isNotEmpty);
    expect(repository.languages, everyElement('zh'));
  });

  testWidgets('changing the language saves the browser again', (tester) async {
    gateway.current = _subscription;
    final ref = await pumpTile(tester);
    expect(repository.languages, ['en']);

    await ref.read(appLanguageProvider.notifier).set(AppLanguage.chinese);
    await tester.pumpAndSettle();
    expect(repository.languages, ['en', 'zh']);

    await ref.read(appLanguageProvider.notifier).set(AppLanguage.english);
    await tester.pumpAndSettle();
    expect(repository.languages, ['en', 'zh', 'en']);
  });

  testWidgets('the browser is saved with its time zone', (tester) async {
    gateway.current = _subscription;
    await pumpTile(tester);
    expect(repository.timeZones, ['Asia/Shanghai']);
  });

  testWidgets('turning push on saves the time zone too', (tester) async {
    gateway.timeZone = 'America/Los_Angeles';
    await pumpTile(tester);
    await tester.tap(find.byKey(const ValueKey('push-notifications')));
    await tester.pumpAndSettle();
    expect(repository.timeZones, isNotEmpty);
    expect(repository.timeZones, everyElement('America/Los_Angeles'));
  });

  testWidgets('an unknown time zone is saved as unknown', (tester) async {
    gateway.timeZone = null;
    gateway.current = _subscription;
    await pumpTile(tester);
    expect(repository.timeZones, [null]);
  });

  testWidgets('changing the language keeps sending the time zone', (
    tester,
  ) async {
    gateway.current = _subscription;
    final ref = await pumpTile(tester);
    await ref.read(appLanguageProvider.notifier).set(AppLanguage.chinese);
    await tester.pumpAndSettle();
    expect(repository.timeZones, ['Asia/Shanghai', 'Asia/Shanghai']);
  });

  test('the language code follows the setting', () {
    expect(pushLanguageCode(AppLanguage.chinese), 'zh');
    expect(pushLanguageCode(AppLanguage.english), 'en');
  });
}
