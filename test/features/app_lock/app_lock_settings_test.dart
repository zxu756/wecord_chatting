import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/app_lock/app_lock_controller.dart';
import 'package:wecord/features/app_lock/app_lock_gate.dart';
import 'package:wecord/features/app_lock/app_lock_models.dart';
import 'package:wecord/features/app_lock/app_lock_settings_screen.dart';
import 'package:wecord/features/app_lock/chat_lock_controller.dart';
import 'package:wecord/features/app_lock/lock_prompts.dart';
import 'package:wecord/features/app_lock/lock_secret.dart';
import 'package:wecord/features/app_lock/system_authenticator.dart';

import '../../mobile/phone_test_support.dart';
import 'lock_fakes.dart';

/// Settings -> Privacy & Safety -> App lock and locked chats.
void main() {
  late PhoneWorld world;
  late LockWorld lock;

  Future<void> openSettings(WidgetTester tester, {String? unlockPin}) async {
    usePhoneViewport(tester, notchedPhone);
    world.extraOverrides = lock.lockOverrides;
    await world.open(tester, '/me');
    if (unlockPin != null) {
      await typePin(tester, unlockPin);
    }
    final tile = find.byKey(const ValueKey('app-lock-tile'));
    await scrollIntoView(tester, tile);
    await tester.ensureVisible(tile);
    await settle(tester);
    await tester.tap(tile);
    await settle(tester);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(AppLockSettingsScreen, skipOffstage: false)),
  );

  AppLockState appLock(WidgetTester tester) =>
      container(tester).read(appLockProvider);

  ChatLockState chatLock(WidgetTester tester) =>
      container(tester).read(chatLockProvider);

  final toggle = find.byKey(const ValueKey('app-lock-toggle'));
  final hide = find.byKey(const ValueKey('chat-lock-hide'));
  final secret = find.byKey(const ValueKey('chat-lock-secret'));

  setUp(() {
    world = PhoneWorld();
    lock = LockWorld();
  });

  testWidgets('Privacy & Safety shows the row with its state', (tester) async {
    lock.repository.locked.addAll({'dm-1', 'group-1'});
    usePhoneViewport(tester, notchedPhone);
    world.extraOverrides = lock.lockOverrides;
    await world.open(tester, '/me');
    final tile = find.byKey(const ValueKey('app-lock-tile'));
    await scrollIntoView(tester, tile);
    expect(find.text('App lock and locked chats'), findsOneWidget);
    expect(find.text('2 locked'), findsOneWidget);
  });

  group('the app lock', () {
    testWidgets('is off to begin with', (tester) async {
      await openSettings(tester);
      expect(find.byKey(AppLockSettingsScreen.screenKey), findsOneWidget);
      expect(appLock(tester).enabled, isFalse);
      expect(find.byKey(const ValueKey('app-lock-timeout')), findsNothing);
      expect(find.byKey(const ValueKey('app-lock-change-pin')), findsNothing);
      expect(
        find.textContaining(
          'asks for Face ID, Touch ID or your device passcode',
        ),
        findsOneWidget,
      );
    });

    testWidgets('turns on after the device says yes', (tester) async {
      await openSettings(tester);
      await tester.tap(toggle);
      await settle(tester);

      expect(lock.system.reasons, ['Turn on the app lock']);
      final state = appLock(tester);
      expect(state.enabled, isTrue);
      expect(state.method, LockMethod.system);
      expect(state.locked, isFalse);
      expect(state.hasPin, isFalse);
      expect(find.byKey(const ValueKey('app-lock-timeout')), findsOneWidget);
      expect(find.text('After 1 minute'), findsOneWidget);
      expect(find.byKey(const ValueKey('app-lock-now')), findsOneWidget);
    });

    testWidgets('stays off when the device does not say yes', (tester) async {
      lock.system.answers.add(SystemAuthResult.canceled);
      await openSettings(tester);
      await tester.tap(toggle);
      await settle(tester);
      expect(appLock(tester).enabled, isFalse);
    });

    testWidgets('says so when the device has no passcode', (tester) async {
      lock.system.available = false;
      lock.store.write('pin', StoredSecret.of('482913').encode());
      lock.store.write('app_method', 'pin');
      await openSettings(tester);
      // With a PIN there is no need for the device.
      await tester.tap(toggle);
      await settle(tester);
      expect(appLock(tester).enabled, isTrue);
      expect(appLock(tester).method, LockMethod.pin);
    });

    testWidgets('makes a PIN first where the device cannot ask', (
      tester,
    ) async {
      lock.system.available = false;
      await openSettings(tester);
      await tester.tap(toggle);
      await settle(tester);

      expect(find.byKey(PinSetupPage.pageKey), findsOneWidget);
      expect(find.text('Choose a PIN'), findsOneWidget);
      await typePin(tester, '482913');
      expect(find.text('Enter it again'), findsOneWidget);
      await typePin(tester, '482913');

      final state = appLock(tester);
      expect(state.enabled, isTrue);
      expect(state.method, LockMethod.pin);
      expect(state.hasPin, isTrue);
      expect(find.byKey(const ValueKey('app-lock-change-pin')), findsOneWidget);
      expect(
        find.textContaining('This device has no passcode'),
        findsOneWidget,
      );
    });

    testWidgets('a PIN typed twice differently starts again', (tester) async {
      lock.system.available = false;
      await openSettings(tester);
      await tester.tap(toggle);
      await settle(tester);
      await typePin(tester, '482913');
      await typePin(tester, '482914');

      expect(
        find.text('The two PINs did not match. Start again.'),
        findsOneWidget,
      );
      expect(find.text('Choose a PIN'), findsOneWidget);
      expect(appLock(tester).hasPin, isFalse);

      // Closing the page leaves the lock off.
      await tester.tap(find.byKey(const ValueKey('pin-page-close')));
      await settle(tester);
      expect(appLock(tester).enabled, isFalse);
    });

    testWidgets('picks when to lock', (tester) async {
      lock.appLockOn();
      await openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('app-lock-timeout')));
      await settle(tester);
      expect(find.text('Immediately'), findsOneWidget);
      expect(find.text('After 1 hour'), findsOneWidget);
      await tester.tap(find.text('After 15 minutes'));
      await settle(tester);

      expect(appLock(tester).timeout, AppLockTimeout.fifteenMinutes);
      expect(lock.store.read('app_timeout'), 'fifteenMinutes');
    });

    testWidgets('Lock now covers the app', (tester) async {
      lock.appLockOn();
      await openSettings(tester);
      final reasons = lock.system.reasons.length;
      await tester.tap(find.byKey(const ValueKey('app-lock-now')));
      await settle(tester);
      expect(find.byKey(AppLockScreen.screenKey), findsOneWidget);
      // The lock is shown as it is; the device is not asked until the person
      // taps Unlock.
      expect(lock.system.reasons.length, reasons);
      await tester.tap(find.byKey(AppLockScreen.unlockKey));
      await settle(tester);
      expect(find.byKey(AppLockScreen.screenKey), findsNothing);
    });

    testWidgets('turns off after the device says yes', (tester) async {
      lock.appLockOn();
      await openSettings(tester);
      await tester.tap(toggle);
      await settle(tester);

      expect(lock.system.reasons.last, 'Turn off the app lock');
      expect(appLock(tester).enabled, isFalse);
    });

    testWidgets('stays on when the person does not pass', (tester) async {
      lock.appLockOn();
      await openSettings(tester);
      lock.system.answers.add(SystemAuthResult.failed);
      await tester.tap(toggle);
      await settle(tester);
      expect(appLock(tester).enabled, isTrue);
    });

    testWidgets('turning it off keeps a PIN that locked chats use', (
      tester,
    ) async {
      lock.appLockOn(pin: '482913');
      lock.store.write('chat_ids', '["dm-1"]');
      lock.repository.locked.add('dm-1');
      await openSettings(tester, unlockPin: '482913');
      await tester.tap(toggle);
      await settle(tester);
      expect(find.byKey(PinVerifyPage.pageKey), findsOneWidget);
      await typePin(tester, '482913');

      expect(appLock(tester).enabled, isFalse);
      expect(appLock(tester).hasPin, isTrue);
    });

    testWidgets('turning it off drops a PIN nothing uses', (tester) async {
      lock.appLockOn(pin: '482913');
      await openSettings(tester, unlockPin: '482913');
      await tester.tap(toggle);
      await settle(tester);
      await typePin(tester, '482913');

      expect(appLock(tester).enabled, isFalse);
      expect(appLock(tester).hasPin, isFalse);
      expect(lock.store.read('pin'), isNull);
    });

    testWidgets('a wrong PIN does not turn it off', (tester) async {
      lock.appLockOn(pin: '482913');
      await openSettings(tester, unlockPin: '482913');
      await tester.tap(toggle);
      await settle(tester);
      await typePin(tester, '111111');
      expect(find.text('Wrong PIN. 4 tries left.'), findsOneWidget);
      expect(appLock(tester).enabled, isTrue);
    });

    testWidgets('changes the PIN after the old one', (tester) async {
      lock.appLockOn(pin: '482913');
      await openSettings(tester, unlockPin: '482913');
      await tester.tap(find.byKey(const ValueKey('app-lock-change-pin')));
      await settle(tester);
      expect(find.text('Enter your current PIN'), findsOneWidget);
      await typePin(tester, '482913');
      expect(find.text('Choose a PIN'), findsOneWidget);
      await typePin(tester, '135790');
      await typePin(tester, '135790');

      final controller = container(tester).read(appLockProvider.notifier);
      expect(controller.checkPin('482913').ok, isFalse);
      expect(controller.checkPin('135790').ok, isTrue);
      expect(find.text('PIN changed.'), findsOneWidget);
    });
  });

  group('locked chats', () {
    testWidgets('say how to lock one when there are none', (tester) async {
      await openSettings(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('chat-lock-none')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('chat-lock-none')), findsOneWidget);
    });

    testWidgets('are listed by name, and unlocked after proving who you are', (
      tester,
    ) async {
      lock.repository.locked.addAll({'dm-1', 'group-1'});
      await openSettings(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('chat-lock-row-dm-1')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('chat-lock-row-group-1')),
        findsOneWidget,
      );
      expect(find.text(bart.displayName), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-lock-row-dm-1')));
      await settle(tester);
      expect(lock.repository.locked, {'group-1'});
      expect(chatLock(tester).lockedIds, {'group-1'});
    });

    testWidgets('hiding asks for a secret code first', (tester) async {
      await openSettings(tester);
      await tester.scrollUntilVisible(
        hide,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(hide);
      await settle(tester);

      expect(
        find.text(
          'Type this code in the search box to show your hidden chats. It is kept on this device only.',
        ),
        findsOneWidget,
      );
      // Too short.
      await tester.enterText(
        find.byKey(const ValueKey('secret-code-field')),
        'ab',
      );
      await tester.enterText(
        find.byKey(const ValueKey('secret-code-again')),
        'ab',
      );
      await tester.tap(find.byKey(const ValueKey('secret-code-save')));
      await settle(tester);
      expect(find.text('Use 4 to 20 characters.'), findsOneWidget);
      // Different.
      await tester.enterText(
        find.byKey(const ValueKey('secret-code-field')),
        'letmein',
      );
      await tester.enterText(
        find.byKey(const ValueKey('secret-code-again')),
        'letmeout',
      );
      await tester.tap(find.byKey(const ValueKey('secret-code-save')));
      await settle(tester);
      expect(find.text('The two codes do not match.'), findsOneWidget);
      // Right.
      await tester.enterText(
        find.byKey(const ValueKey('secret-code-again')),
        'letmein',
      );
      await tester.tap(find.byKey(const ValueKey('secret-code-save')));
      await settle(tester);

      final state = chatLock(tester);
      expect(state.hideLocked, isTrue);
      expect(state.hasSecretCode, isTrue);
      expect(find.text('Set'), findsOneWidget);
    });

    testWidgets('cancelling the code leaves hiding off', (tester) async {
      await openSettings(tester);
      await tester.scrollUntilVisible(
        hide,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(hide);
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(chatLock(tester).hideLocked, isFalse);
      expect(chatLock(tester).hasSecretCode, isFalse);
    });

    testWidgets('the code can be changed or removed', (tester) async {
      lock.store.write('chat_secret', StoredSecret.of('letmein').encode());
      lock.store.write('chat_hide', '1');
      await openSettings(tester);
      await tester.scrollUntilVisible(
        secret,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(secret);
      await settle(tester);
      expect(find.text('Change the secret code'), findsOneWidget);
      await tester.tap(find.text('Remove the secret code'));
      await settle(tester);

      final state = chatLock(tester);
      expect(state.hasSecretCode, isFalse);
      expect(
        state.hideLocked,
        isFalse,
        reason: 'nothing could show them again',
      );
      expect(find.text('Not set'), findsOneWidget);
    });
  });
}
