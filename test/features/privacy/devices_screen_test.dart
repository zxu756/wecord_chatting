import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/privacy/device_info.dart';
import 'package:wecord/features/privacy/devices_repository.dart';
import 'package:wecord/features/privacy/devices_screen.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

class _FakeDevices implements DevicesRepository {
  _FakeDevices(this.sessions);

  List<DeviceSession> sessions;
  final revoked = <String>[];
  var signedOutOthers = 0;
  var failNext = false;
  var registered = 0;

  @override
  Future<List<DeviceSession>> list() async => sessions;

  @override
  Future<void> registerCurrentDevice() async => registered++;

  @override
  Future<void> signOutOthers() async {
    if (failNext) {
      throw StateError('offline');
    }
    signedOutOthers++;
    sessions = [
      for (final session in sessions)
        if (session.isCurrent) session,
    ];
  }

  @override
  Future<void> revoke(String sessionId) async {
    if (failNext) {
      throw StateError('offline');
    }
    revoked.add(sessionId);
    sessions = [
      for (final session in sessions)
        if (session.sessionId != sessionId) session,
    ];
  }
}

DeviceSession _session(
  String id, {
  String name = '',
  String platform = 'macOS',
  String version = '1.2.0',
  bool current = false,
  Duration age = Duration.zero,
  String userAgent = '',
}) {
  return DeviceSession(
    sessionId: id,
    deviceName: name,
    platform: platform,
    appVersion: version,
    userAgent: userAgent,
    createdAt: DateTime.now().toUtc().subtract(const Duration(days: 9)),
    lastActiveAt: DateTime.now().toUtc().subtract(age),
    isCurrent: current,
  );
}

Widget _app(_FakeDevices devices) {
  return ProviderScope(
    overrides: [devicesRepositoryProvider.overrideWithValue(devices)],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: const DevicesScreen(),
    ),
  );
}

void main() {
  test('titles fall back to the browser, then the platform', () {
    expect(_session('a', name: 'Ada MacBook').title, 'Ada MacBook');
    expect(
      _session(
        'b',
        userAgent:
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15',
      ).title,
      'Safari on macOS',
    );
    expect(_session('c', platform: 'iOS').title, 'iOS');
    expect(_session('d', platform: '').title, '');
  });

  test('describes user agents', () {
    expect(
      describeUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36 Edg/120.0',
      ),
      'Edge on Windows',
    );
    expect(
      describeUserAgent('Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Firefox/121.0'),
      'Firefox on Linux',
    );
    expect(describeUserAgent('curl/8'), '');
  });

  test('says how long ago', () {
    final now = DateTime.utc(2026, 10, 17, 12);
    expect(
      lastActiveLabel(now.subtract(const Duration(seconds: 30)), now: now),
      'Active just now',
    );
    expect(
      lastActiveLabel(now.subtract(const Duration(minutes: 20)), now: now),
      'Active 20 minutes ago',
    );
    expect(
      lastActiveLabel(now.subtract(const Duration(hours: 1)), now: now),
      'Active 1 hour ago',
    );
    expect(
      lastActiveLabel(now.subtract(const Duration(hours: 5)), now: now),
      'Active 5 hours ago',
    );
    expect(
      lastActiveLabel(now.subtract(const Duration(days: 3)), now: now),
      'Active 3 days ago',
    );
  });

  testWidgets('lists this device first, then the others', (tester) async {
    final devices = _FakeDevices([
      _session('mac', name: 'Ada MacBook', current: true),
      _session(
        'phone',
        name: 'iPhone or iPad',
        platform: 'iOS',
        age: const Duration(hours: 3),
      ),
      _session('web', platform: 'Web', age: const Duration(days: 2)),
    ]);
    await tester.pumpWidget(_app(devices));
    await tester.pumpAndSettle();

    expect(find.text('This device'), findsOneWidget);
    expect(find.text('Other devices'), findsOneWidget);
    expect(find.text('Ada MacBook'), findsOneWidget);
    expect(find.text('macOS · WeCord 1.2.0 · Active now'), findsOneWidget);
    expect(find.text('iPhone or iPad'), findsOneWidget);
    expect(find.text('iOS · WeCord 1.2.0 · Active 3 hours ago'), findsOneWidget);
    expect(find.text('Web'), findsWidgets);
    // This device cannot be signed out from here.
    expect(find.byKey(const ValueKey('device-sign-out-mac')), findsNothing);
    expect(find.byKey(const ValueKey('device-sign-out-phone')), findsOneWidget);
    // No location or address is shown.
    expect(find.textContaining('IP'), findsNothing);
  });

  testWidgets('signs one device out after confirming', (tester) async {
    final devices = _FakeDevices([
      _session('mac', name: 'Ada MacBook', current: true),
      _session('phone', name: 'Ada iPhone', platform: 'iOS'),
    ]);
    await tester.pumpWidget(_app(devices));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('device-sign-out-phone')));
    await tester.pumpAndSettle();
    expect(find.text('Sign out Ada iPhone?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(devices.revoked, isEmpty);

    await tester.tap(find.byKey(const ValueKey('device-sign-out-phone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-sign-out-confirm')));
    await tester.pumpAndSettle();
    expect(devices.revoked, ['phone']);
    expect(find.byKey(const ValueKey('devices-none')), findsOneWidget);
  });

  testWidgets('signs out of all other devices', (tester) async {
    final devices = _FakeDevices([
      _session('mac', name: 'Ada MacBook', current: true),
      _session('phone', name: 'Ada iPhone', platform: 'iOS'),
      _session('web', name: 'Chrome on Windows', platform: 'Web'),
    ]);
    await tester.pumpWidget(_app(devices));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('devices-sign-out-others')));
    await tester.pumpAndSettle();
    expect(find.text('Sign out of all other devices?'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('devices-sign-out-others-confirm')),
    );
    await tester.pumpAndSettle();
    expect(devices.signedOutOthers, 1);
    expect(find.text('Ada MacBook'), findsOneWidget);
    expect(find.text('Ada iPhone'), findsNothing);
    expect(find.byKey(const ValueKey('devices-sign-out-others')), findsNothing);
  });

  testWidgets('a failure leaves the list and says so', (tester) async {
    final devices = _FakeDevices([
      _session('mac', name: 'Ada MacBook', current: true),
      _session('phone', name: 'Ada iPhone', platform: 'iOS'),
    ])..failNext = true;
    await tester.pumpWidget(_app(devices));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('device-sign-out-phone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-sign-out-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Could not sign that device out.'), findsOneWidget);
    expect(find.text('Ada iPhone'), findsOneWidget);
  });

  testWidgets('unknown devices are named as such', (tester) async {
    final devices = _FakeDevices([
      _session('mac', name: 'Ada MacBook', current: true),
      _session('x', platform: ''),
    ]);
    await tester.pumpWidget(_app(devices));
    await tester.pumpAndSettle();
    expect(find.text('Unknown device'), findsOneWidget);
  });
}
