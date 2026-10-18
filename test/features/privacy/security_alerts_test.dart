import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/auth/password_recovery.dart';
import 'package:wecord/features/privacy/devices_repository.dart';
import 'package:wecord/features/privacy/security_alerts.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'privacy2_fakes.dart';
import 'privacy_fakes.dart';

class _RecordingDevices extends FakeDevicesRepository {
  final revoked = <String>[];

  /// Raised instead of revoking, when set.
  Object? failWith;

  @override
  Future<void> revoke(String sessionId) async {
    final failure = failWith;
    if (failure != null) {
      throw failure;
    }
    revoked.add(sessionId);
    await super.revoke(sessionId);
  }
}

class _FakePasswords implements PasswordRecoveryRepository {
  final saved = <String>[];

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Stream<void> recoveries() => const Stream.empty();

  @override
  Future<void> updatePassword(String password) async => saved.add(password);
}

String _token(Map<String, Object?> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(json.encode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(claims)}.signature';
}

Widget _app({
  required FakeSecurityAlertsRepository alerts,
  required _RecordingDevices devices,
  _FakePasswords? passwords,
}) {
  return ProviderScope(
    overrides: [
      ...privacy2Overrides(alerts: alerts),
      devicesRepositoryProvider.overrideWithValue(devices),
      passwordRecoveryRepositoryProvider.overrideWithValue(
        passwords ?? _FakePasswords(),
      ),
    ],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            final list = ref.watch(securityAlertsProvider).value ?? const [];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final alert in list) SecurityAlertCard(alert: alert),
              ],
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  test('the session of a token is its session_id claim', () {
    expect(sessionIdOfToken(_token({'session_id': 'abc'})), 'abc');
    expect(sessionIdOfToken(_token({'sub': 'u'})), isNull);
    expect(sessionIdOfToken('not.a.jwt!'), isNull);
    expect(sessionIdOfToken('nodots'), isNull);
    expect(sessionIdOfToken(null), isNull);
  });

  test('an alert names the device and its platform once', () {
    LoginAlert alert(String name, String platform) => LoginAlert(
      id: 'a',
      sessionId: 's',
      deviceName: name,
      platform: platform,
      createdAt: DateTime.utc(2026, 10, 20),
    );
    expect(alert('Ada MacBook', 'macOS').deviceLabel, 'Ada MacBook (macOS)');
    expect(alert('Chrome on macOS', 'macOS').deviceLabel, 'Chrome on macOS');
    expect(alert('', 'iOS').deviceLabel, 'iOS');
    expect(alert('Kitchen iPad', '').deviceLabel, 'Kitchen iPad');
    expect(alert('', '').deviceLabel, '');
  });

  test('alert rows become alerts, open until resolved', () {
    final open = LoginAlert.fromJson({
      'id': 'a',
      'session_id': 's',
      'device_name': 'Phone',
      'platform': 'iOS',
      'created_at': '2026-10-20T08:00:00Z',
      'resolved_at': null,
      'resolution': null,
    });
    expect(open.isOpen, isTrue);
    final closed = LoginAlert.fromJson({
      'id': 'a',
      'session_id': 's',
      'created_at': '2026-10-20T08:00:00Z',
      'resolution': 'revoked',
    });
    expect(closed.resolution, LoginAlertResolution.revoked);
    expect(closed.isOpen, isFalse);
  });

  test('the alert about this very device is not shown on it', () async {
    final alerts = FakeSecurityAlertsRepository([
      ...sampleLoginAlerts(),
      LoginAlert(
        id: 'alert-mine',
        sessionId: 'mac',
        deviceName: 'This Mac',
        platform: 'macOS',
        createdAt: DateTime.now().toUtc(),
      ),
    ]);
    final container = ProviderContainer(
      overrides: privacy2Overrides(alerts: alerts, currentSessionId: 'mac'),
    );
    addTearDown(container.dispose);
    final shown = await container.read(securityAlertsProvider.future);
    expect([for (final alert in shown) alert.id], ['alert-1']);
  });

  test('old closed alerts drop away, open ones stay', () async {
    final now = DateTime.now().toUtc();
    LoginAlert alert(String id, int days, LoginAlertResolution? resolution) =>
        LoginAlert(
          id: id,
          sessionId: id,
          deviceName: id,
          platform: '',
          createdAt: now.subtract(Duration(days: days)),
          resolution: resolution,
        );
    final container = ProviderContainer(
      overrides: privacy2Overrides(
        alerts: FakeSecurityAlertsRepository([
          alert('old-open', 10, null),
          alert('old-closed', 10, LoginAlertResolution.dismissed),
          alert('fresh-closed', 0, LoginAlertResolution.revoked),
        ]),
      ),
    );
    addTearDown(container.dispose);
    final shown = await container.read(securityAlertsProvider.future);
    expect([for (final a in shown) a.id], ['old-open', 'fresh-closed']);
    container.listen(securityAlertsOpenCountProvider, (_, _) {});
    await container.read(securityAlertsProvider.future);
    expect(container.read(securityAlertsOpenCountProvider), 1);
  });

  testWidgets('the card shows the device, platform and time', (tester) async {
    await tester.pumpWidget(
      _app(
        alerts: FakeSecurityAlertsRepository(),
        devices: _RecordingDevices(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New sign-in to your account'), findsOneWidget);
    expect(find.text('iPhone or iPad (iOS)'), findsOneWidget);
    expect(find.byKey(const ValueKey('security-not-me')), findsOneWidget);
    expect(find.byKey(const ValueKey('security-it-was-me')), findsOneWidget);
    // No address and no location on the card.
    expect(find.textContaining('IP'), findsNothing);
    expect(find.textContaining('location'), findsNothing);
  });

  testWidgets('"It was me" closes the alert without signing anyone out', (
    tester,
  ) async {
    final alerts = FakeSecurityAlertsRepository();
    final devices = _RecordingDevices();
    await tester.pumpWidget(_app(alerts: alerts, devices: devices));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('security-it-was-me')));
    await tester.pumpAndSettle();

    expect(alerts.resolved, [('alert-1', LoginAlertResolution.dismissed)]);
    expect(devices.revoked, isEmpty);
    expect(find.text('You confirmed this sign-in'), findsOneWidget);
    expect(find.byKey(const ValueKey('security-not-me')), findsNothing);
  });

  testWidgets('"Not me" signs that session out and points to the password', (
    tester,
  ) async {
    final alerts = FakeSecurityAlertsRepository();
    final devices = _RecordingDevices();
    final passwords = _FakePasswords();
    await tester.pumpWidget(
      _app(alerts: alerts, devices: devices, passwords: passwords),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('security-not-me')));
    await tester.pumpAndSettle();

    // The sessions function was asked to end the session that signed in.
    expect(devices.revoked, ['phone']);
    expect(alerts.resolved, [('alert-1', LoginAlertResolution.revoked)]);
    expect(find.text('That device was signed out'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('security-password-change')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('change-password-new')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('change-password-new')),
      'new-secret-1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('change-password-confirm')),
      'new-secret-1',
    );
    await tester.tap(find.byKey(const ValueKey('change-password-save')));
    await tester.pumpAndSettle();
    expect(passwords.saved, ['new-secret-1']);
    expect(find.text('Your password was changed.'), findsOneWidget);
  });

  testWidgets('the password sheet checks the two entries match', (
    tester,
  ) async {
    final passwords = _FakePasswords();
    await tester.pumpWidget(
      _app(
        alerts: FakeSecurityAlertsRepository(),
        devices: _RecordingDevices(),
        passwords: passwords,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('security-not-me')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('security-password-change')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('change-password-new')),
      'new-secret-1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('change-password-confirm')),
      'different',
    );
    await tester.tap(find.byKey(const ValueKey('change-password-save')));
    await tester.pumpAndSettle();
    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(passwords.saved, isEmpty);
  });

  testWidgets('"Later" leaves the password alone', (tester) async {
    final passwords = _FakePasswords();
    await tester.pumpWidget(
      _app(
        alerts: FakeSecurityAlertsRepository(),
        devices: _RecordingDevices(),
        passwords: passwords,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('security-not-me')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('security-password-later')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('change-password-new')), findsNothing);
    expect(passwords.saved, isEmpty);
    expect(find.text('You signed that device out'), findsOneWidget);
  });

  testWidgets('a session that is already gone still closes the alert', (
    tester,
  ) async {
    final alerts = FakeSecurityAlertsRepository();
    final devices = _RecordingDevices()
      ..failWith = const FunctionException(status: 404);
    await tester.pumpWidget(_app(alerts: alerts, devices: devices));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('security-not-me')));
    await tester.pumpAndSettle();

    expect(alerts.resolved, [('alert-1', LoginAlertResolution.revoked)]);
    expect(find.text('That device was signed out'), findsOneWidget);
  });

  testWidgets('a failed sign-out keeps the alert open and says so', (
    tester,
  ) async {
    final alerts = FakeSecurityAlertsRepository();
    final devices = _RecordingDevices()..failWith = StateError('offline');
    await tester.pumpWidget(_app(alerts: alerts, devices: devices));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('security-not-me')));
    await tester.pumpAndSettle();

    expect(alerts.resolved, isEmpty);
    expect(find.text('Could not sign that device out.'), findsOneWidget);
    expect(find.byKey(const ValueKey('security-not-me')), findsOneWidget);
  });
}
