import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/offline/connectivity.dart';
import 'package:wecord/features/chats/offline/connectivity_banner.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

void main() {
  const offlineText = 'Offline — messages will send when you reconnect';
  const reconnectingText = 'Reconnecting…';

  late StreamController<bool> device;

  setUp(() {
    device = StreamController<bool>.broadcast();
  });

  tearDown(() async {
    realtimeStatusTracker.forget('test-channel');
    await device.close();
  });

  Widget app() {
    return ProviderScope(
      overrides: [
        deviceConnectivityProvider.overrideWith((ref) => device.stream),
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: const Scaffold(body: Column(children: [ConnectivityBanner()])),
      ),
    );
  }

  testWidgets('shows nothing while online', (tester) async {
    await tester.pumpWidget(app());
    device.add(true);
    await tester.pumpAndSettle();

    expect(find.text(offlineText), findsNothing);
    expect(find.text(reconnectingText), findsNothing);
    expect(tester.getSize(find.byType(ConnectivityBanner)).height, lessThan(1));
  });

  testWidgets('says messages wait while the device is offline', (tester) async {
    await tester.pumpWidget(app());
    device.add(false);
    await tester.pumpAndSettle();

    expect(find.text(offlineText), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    expect(find.bySemanticsLabel(offlineText), findsOneWidget);

    device.add(true);
    await tester.pumpAndSettle();
    expect(find.text(offlineText), findsNothing);
  });

  testWidgets('says reconnecting while realtime fails online', (tester) async {
    await tester.pumpWidget(app());
    device.add(true);
    await tester.pump();

    realtimeStatusTracker.report('test-channel', RealtimeChannelState.failed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(reconnectingText), findsOneWidget);
    expect(find.text(offlineText), findsNothing);

    // Offline wins over reconnecting.
    device.add(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(offlineText), findsOneWidget);

    device.add(true);
    realtimeStatusTracker.report('test-channel', RealtimeChannelState.joined);
    await tester.pumpAndSettle();
    expect(find.text(reconnectingText), findsNothing);
    expect(find.text(offlineText), findsNothing);
  });

  test('the network status combines the device and realtime', () async {
    final container = ProviderContainer(
      overrides: [
        deviceConnectivityProvider.overrideWith((ref) => device.stream),
      ],
    );
    addTearDown(container.dispose);
    final statuses = <NetworkStatus>[];
    container.listen(
      networkStatusProvider,
      (_, next) => statuses.add(next),
      fireImmediately: true,
    );
    var reconnects = 0;
    container.listen(reconnectCountProvider, (_, next) => reconnects = next);

    Future<void> settle() async {
      for (var turn = 0; turn < 10; turn++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    await settle();
    device.add(false);
    await settle();
    device.add(true);
    await settle();
    realtimeStatusTracker.report('test-channel', RealtimeChannelState.failed);
    await settle();
    realtimeStatusTracker.report('test-channel', RealtimeChannelState.joined);
    await settle();

    expect(statuses, [
      NetworkStatus.online,
      NetworkStatus.offline,
      NetworkStatus.online,
      NetworkStatus.reconnecting,
      NetworkStatus.online,
    ]);
    expect(reconnects, 1);
  });
}
