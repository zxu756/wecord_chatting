import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/privacy/account_security_events.dart';
import 'package:wecord/features/privacy/devices_repository.dart';
import 'package:wecord/features/settings/security_log_screen.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../auth/account_security_fakes.dart';
import 'privacy_fakes.dart';

Widget _cards(FakeAccountSecurityRepository events) {
  return ProviderScope(
    overrides: [
      ...accountSecurityOverrides(events: events),
      devicesRepositoryProvider.overrideWithValue(FakeDevicesRepository()),
    ],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            final list = ref.watch(accountSecurityInboxProvider);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final event in list)
                  AccountSecurityEventCard(event: event),
              ],
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  group('rows from the server', () {
    test('a row becomes an event, open until answered', () {
      final open = AccountSecurityEvent.tryParse({
        'id': 'e',
        'kind': 'passkey_added',
        'detail': {'name': ' iCloud Keychain '},
        'created_at': '2026-10-28T09:00:00Z',
        'resolved_at': null,
        'resolution': null,
      })!;
      expect(open.kind, AccountSecurityKind.passkeyAdded);
      expect(open.passkeyName, 'iCloud Keychain');
      expect(open.isOpen, isTrue);
      expect(open.createdAt, DateTime.utc(2026, 10, 28, 9));

      final closed = AccountSecurityEvent.tryParse({
        'id': 'e',
        'kind': 'recovery_code_used',
        'detail': <String, dynamic>{},
        'created_at': '2026-10-28T09:00:00Z',
        'resolution': 'denied',
      })!;
      expect(closed.answer, AccountSecurityAnswer.denied);
      expect(closed.isOpen, isFalse);
      expect(closed.passkeyName, isEmpty);
    });

    test('a kind from a newer server is left out, not a crash', () {
      expect(
        AccountSecurityEvent.tryParse({
          'id': 'e',
          'kind': 'something_new',
          'created_at': '2026-10-28T09:00:00Z',
        }),
        isNull,
      );
    });

    test('every kind says what happened', () {
      for (final kind in AccountSecurityKind.values) {
        final event = AccountSecurityEvent(
          id: 'e',
          kind: kind,
          createdAt: DateTime.utc(2026, 10, 28),
        );
        expect(event.headline, isNotEmpty);
        expect(event.summary, isNotEmpty);
      }
      expect(AccountSecurityKind.fromWire('recovery_locked'), isNotNull);
      expect(AccountSecurityKind.recoveryCodeUsed.opensTheAccount, isTrue);
      expect(AccountSecurityKind.recoveryLocked.opensTheAccount, isFalse);
    });
  });

  test('old answered events drop away, open ones stay', () async {
    final now = DateTime.now().toUtc();
    AccountSecurityEvent event(
      String id,
      int days,
      AccountSecurityAnswer? answer,
    ) => AccountSecurityEvent(
      id: id,
      kind: AccountSecurityKind.passkeyRemoved,
      createdAt: now.subtract(Duration(days: days)),
      answer: answer,
    );
    final container = ProviderContainer(
      overrides: accountSecurityOverrides(
        events: FakeAccountSecurityRepository([
          event('old-open', 10, null),
          event('old-closed', 10, AccountSecurityAnswer.confirmed),
          event('fresh-closed', 0, AccountSecurityAnswer.denied),
        ]),
      ),
    );
    addTearDown(container.dispose);
    container.listen(accountSecurityInboxProvider, (_, _) {});
    container.listen(accountSecurityOpenCountProvider, (_, _) {});
    await container.read(accountSecurityEventsProvider.future);
    expect(
      [for (final e in container.read(accountSecurityInboxProvider)) e.id],
      ['old-open', 'fresh-closed'],
    );
    expect(container.read(accountSecurityOpenCountProvider), 1);
  });

  group('the card in Notifications', () {
    testWidgets('says what happened and asks', (tester) async {
      await tester.pumpWidget(_cards(FakeAccountSecurityRepository()));
      await tester.pumpAndSettle();

      expect(find.text('A recovery code was used to sign in'), findsOneWidget);
      expect(find.text('A passkey was added to your account'), findsOneWidget);
      expect(
        find.text('Two-step verification was turned off.'),
        findsOneWidget,
      );
      expect(find.text('iCloud Keychain'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('security-event-not-me')),
        findsNWidgets(2),
      );
      // The one answered three days ago is gone from the card list.
      expect(find.text('New recovery codes were made'), findsNothing);
    });

    testWidgets('"It was me" closes it and nothing else happens', (
      tester,
    ) async {
      final events = FakeAccountSecurityRepository();
      await tester.pumpWidget(_cards(events));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('security-event-it-was-me')).first,
      );
      await tester.pumpAndSettle();

      expect(events.resolved, [('ev-1', AccountSecurityAnswer.confirmed)]);
      expect(find.text('You confirmed this change'), findsOneWidget);
      expect(find.text('Secure your account'), findsNothing);
    });

    testWidgets('"Not me" closes it and points to the password', (
      tester,
    ) async {
      final events = FakeAccountSecurityRepository();
      await tester.pumpWidget(_cards(events));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('security-event-not-me')).first,
      );
      await tester.pumpAndSettle();

      expect(events.resolved, [('ev-1', AccountSecurityAnswer.denied)]);
      expect(find.text('You said this was not you'), findsOneWidget);
      expect(find.text('Secure your account'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('security-event-help-password')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('security-event-help-devices')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('security-event-help-later')));
      await tester.pumpAndSettle();
      expect(find.text('Secure your account'), findsNothing);
    });

    testWidgets('a failed answer keeps the card open and says so', (
      tester,
    ) async {
      final events = FakeAccountSecurityRepository()..failResolve = true;
      await tester.pumpWidget(_cards(events));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('security-event-not-me')).first,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Could not save your answer. Try again.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('security-event-not-me')),
        findsNWidgets(2),
      );
      expect(find.text('Secure your account'), findsNothing);
    });
  });

  group('the security log', () {
    Future<void> openLog(
      WidgetTester tester,
      FakeAccountSecurityRepository events,
    ) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: accountSecurityOverrides(events: events),
          child: const MaterialApp(home: SecurityLogScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists the last 30 days with how each was answered', (
      tester,
    ) async {
      await openLog(tester, FakeAccountSecurityRepository());
      expect(find.byKey(const ValueKey('security-log-ev-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('security-log-ev-3')), findsOneWidget);
      expect(find.textContaining('Waiting for your answer'), findsNWidgets(2));
      expect(find.textContaining('You confirmed it'), findsOneWidget);
    });

    testWidgets('an uneventful month says so', (tester) async {
      await openLog(tester, FakeAccountSecurityRepository([]));
      expect(find.text('Nothing to report'), findsOneWidget);
    });
  });
}
