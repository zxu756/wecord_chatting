import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/app_lock/app_lock_controller.dart';
import 'package:wecord/features/app_lock/app_lock_models.dart';
import 'package:wecord/features/app_lock/system_authenticator.dart';
import 'package:wecord/features/auth/auth_repository.dart';

import 'lock_fakes.dart';

void main() {
  group('PIN waits', () {
    test('nothing to wait for until the fifth wrong try', () {
      expect(pinWaitAfter(0), isNull);
      expect(pinWaitAfter(1), isNull);
      expect(pinWaitAfter(4), isNull);
      expect(pinWaitAfter(5), const Duration(seconds: 30));
      expect(pinWaitAfter(6), isNull);
      expect(pinWaitAfter(10), const Duration(minutes: 1));
      expect(pinWaitAfter(15), const Duration(minutes: 5));
      expect(pinWaitAfter(20), const Duration(minutes: 15));
      // And every five after that.
      expect(pinWaitAfter(25), const Duration(minutes: 15));
      expect(pinWaitAfter(200), const Duration(minutes: 15));
    });
  });

  group('the app lock', () {
    late LockWorld world;

    setUp(() => world = LockWorld());

    test('starts off and open', () {
      final container = world.container();
      addTearDown(container.dispose);
      final state = container.read(appLockProvider);
      expect(state.enabled, isFalse);
      expect(state.locked, isFalse);
      expect(state.hasPin, isFalse);
      expect(state.timeout, AppLockTimeout.oneMinute);
    });

    test('a PIN is kept as a salted hash and can be checked', () async {
      final container = world.container();
      addTearDown(container.dispose);
      final controller = container.read(appLockProvider.notifier);

      await controller.setPin('482913');
      expect(container.read(appLockProvider).hasPin, isTrue);
      final kept = world.store.read('pin')!;
      expect(kept, isNot(contains('482913')));

      expect(controller.checkPin('482913').ok, isTrue);
      expect(controller.checkPin('000000').ok, isFalse);
    });

    test(
      'turning it on leaves the app open; a restart finds it locked',
      () async {
        final container = world.container();
        addTearDown(container.dispose);
        final controller = container.read(appLockProvider.notifier);
        await controller.setPin('482913');
        await controller.enable(LockMethod.pin);
        expect(container.read(appLockProvider).enabled, isTrue);
        expect(container.read(appLockProvider).locked, isFalse);

        // A new run reads the same storage.
        final restarted = world.container();
        addTearDown(restarted.dispose);
        final state = restarted.read(appLockProvider);
        expect(state.enabled, isTrue);
        expect(state.locked, isTrue);
        expect(state.method, LockMethod.pin);
        expect(state.hasPin, isTrue);
      },
    );

    test('a PIN lock whose PIN is gone is off', () async {
      world.store.write('app_enabled', '1');
      world.store.write('app_method', 'pin');
      final container = world.container();
      addTearDown(container.dispose);
      expect(container.read(appLockProvider).enabled, isFalse);
      expect(container.read(appLockProvider).locked, isFalse);
    });

    test('the PIN method cannot be turned on without a PIN', () async {
      final container = world.container();
      addTearDown(container.dispose);
      await expectLater(
        container.read(appLockProvider.notifier).enable(LockMethod.pin),
        throwsStateError,
      );
    });

    group('wrong PINs', () {
      late ProviderContainerHolder holder;

      setUp(() async {
        holder = ProviderContainerHolder(world);
        await holder.controller.setPin('482913');
      });

      tearDown(() => holder.dispose());

      test('count down to a wait, and the wait is kept', () {
        final controller = holder.controller;
        for (var i = 1; i <= 4; i++) {
          final result = controller.checkPin('111111');
          expect(result.ok, isFalse);
          expect(result.isWaiting, isFalse);
          expect(result.triesLeft, 5 - i);
        }
        final fifth = controller.checkPin('111111');
        expect(fifth.isWaiting, isTrue);
        expect(
          fifth.waitUntil,
          world.clock.now.add(const Duration(seconds: 30)),
        );

        // While waiting, even the right PIN is not looked at.
        expect(controller.checkPin('482913').isWaiting, isTrue);
        expect(controller.checkPin('482913').ok, isFalse);

        // The wait is over.
        world.clock.advance(const Duration(seconds: 31));
        expect(controller.checkPin('482913').ok, isTrue);
        expect(holder.container.read(appLockProvider).failedAttempts, 0);
      });

      test('are remembered across a restart', () {
        for (var i = 0; i < 5; i++) {
          holder.controller.checkPin('111111');
        }
        final restarted = world.container();
        addTearDown(restarted.dispose);
        final state = restarted.read(appLockProvider);
        expect(state.failedAttempts, 5);
        expect(
          state.waitUntil,
          world.clock.now.add(const Duration(seconds: 30)),
        );
        expect(
          restarted.read(appLockProvider.notifier).checkPin('482913').isWaiting,
          isTrue,
        );
      });

      test('wait longer each round', () {
        final controller = holder.controller;
        for (var i = 0; i < 5; i++) {
          controller.checkPin('111111');
        }
        world.clock.advance(const Duration(seconds: 31));
        for (var i = 0; i < 4; i++) {
          expect(controller.checkPin('111111').isWaiting, isFalse);
        }
        final tenth = controller.checkPin('111111');
        expect(
          tenth.waitUntil,
          world.clock.now.add(const Duration(minutes: 1)),
        );
      });

      test('a right PIN forgives the wrong ones', () {
        final controller = holder.controller;
        controller.checkPin('111111');
        controller.checkPin('111111');
        expect(controller.checkPin('482913').ok, isTrue);
        expect(controller.checkPin('111111').triesLeft, 4);
      });
    });

    group('when it locks', () {
      Future<(ProviderContainer, AppLockController)> turnedOn(
        AppLockTimeout timeout,
      ) async {
        final container = world.container();
        addTearDown(container.dispose);
        final controller = container.read(appLockProvider.notifier);
        await controller.setPin('482913');
        await controller.enable(LockMethod.pin);
        await controller.setTimeout(timeout);
        return (container, controller);
      }

      test('not before the time is up', () async {
        final (container, controller) = await turnedOn(
          AppLockTimeout.fiveMinutes,
        );
        controller.appLeft();
        world.clock.advance(const Duration(minutes: 4, seconds: 59));
        controller.appReturned();
        expect(container.read(appLockProvider).locked, isFalse);
      });

      test('once the time is up', () async {
        final (container, controller) = await turnedOn(
          AppLockTimeout.fiveMinutes,
        );
        controller.appLeft();
        world.clock.advance(const Duration(minutes: 5));
        controller.appReturned();
        expect(container.read(appLockProvider).locked, isTrue);
      });

      test('at once when the person chose Immediately', () async {
        final (container, controller) = await turnedOn(
          AppLockTimeout.immediately,
        );
        controller.appLeft();
        expect(container.read(appLockProvider).locked, isTrue);
      });

      test('leaving twice counts from the first time', () async {
        final (container, controller) = await turnedOn(
          AppLockTimeout.oneMinute,
        );
        controller.appLeft();
        world.clock.advance(const Duration(seconds: 40));
        controller.appLeft();
        world.clock.advance(const Duration(seconds: 30));
        controller.appReturned();
        expect(container.read(appLockProvider).locked, isTrue);
      });

      test('returning without having left does nothing', () async {
        final (container, controller) = await turnedOn(
          AppLockTimeout.immediately,
        );
        controller.appReturned();
        expect(container.read(appLockProvider).locked, isFalse);
      });

      test('never when the lock is off', () async {
        final container = world.container();
        addTearDown(container.dispose);
        final controller = container.read(appLockProvider.notifier);
        controller.appLeft();
        world.clock.advance(const Duration(hours: 5));
        controller.appReturned();
        controller.lockNow();
        expect(container.read(appLockProvider).locked, isFalse);
      });

      test('lock now locks, unlock opens', () async {
        final (container, controller) = await turnedOn(AppLockTimeout.oneHour);
        controller.lockNow();
        expect(container.read(appLockProvider).locked, isTrue);
        controller.unlock();
        expect(container.read(appLockProvider).locked, isFalse);
      });

      test('the prompt itself is not leaving', () async {
        final container = world.container();
        addTearDown(container.dispose);
        final controller = container.read(appLockProvider.notifier);
        await controller.setTimeout(AppLockTimeout.immediately);
        await controller.enable(LockMethod.system);
        world.system.hold = Completer<SystemAuthResult>();
        final asking = controller.unlockWithSystem();
        await Future<void>.delayed(Duration.zero);
        expect(controller.isAuthenticating, isTrue);
        // The app goes inactive while Face ID is up.
        controller.appLeft();
        expect(container.read(appLockProvider).locked, isFalse);
        world.system.hold!.complete(SystemAuthResult.success);
        await asking;
        expect(controller.isAuthenticating, isFalse);
        controller.appReturned();
        expect(container.read(appLockProvider).locked, isFalse);
      });
    });

    group('the device prompt', () {
      test('opens the app when it passes', () async {
        final container = world.container();
        addTearDown(container.dispose);
        final controller = container.read(appLockProvider.notifier);
        await controller.enable(LockMethod.system);
        controller.lockNow();
        expect(await controller.unlockWithSystem(), SystemAuthResult.success);
        expect(container.read(appLockProvider).locked, isFalse);
        expect(world.system.reasons, ['Unlock WeCord']);
      });

      test('leaves it locked when it fails or is cancelled', () async {
        final container = world.container();
        addTearDown(container.dispose);
        final controller = container.read(appLockProvider.notifier);
        await controller.enable(LockMethod.system);
        controller.lockNow();
        world.system.answers.addAll([
          SystemAuthResult.failed,
          SystemAuthResult.canceled,
        ]);
        expect(await controller.unlockWithSystem(), SystemAuthResult.failed);
        expect(await controller.unlockWithSystem(), SystemAuthResult.canceled);
        expect(container.read(appLockProvider).locked, isTrue);
      });

      test('prefers the device and falls back to a PIN', () async {
        final container = world.container();
        addTearDown(container.dispose);
        final controller = container.read(appLockProvider.notifier);
        expect(await controller.preferredMethod(), LockMethod.system);
        world.system.available = false;
        expect(await controller.preferredMethod(), LockMethod.pin);
      });
    });

    group('settings', () {
      test('the timeout is kept', () async {
        final container = world.container();
        addTearDown(container.dispose);
        await container
            .read(appLockProvider.notifier)
            .setTimeout(AppLockTimeout.fifteenMinutes);
        final restarted = world.container();
        addTearDown(restarted.dispose);
        expect(
          restarted.read(appLockProvider).timeout,
          AppLockTimeout.fifteenMinutes,
        );
      });

      test('turning it off keeps or drops the PIN', () async {
        final container = world.container();
        addTearDown(container.dispose);
        final controller = container.read(appLockProvider.notifier);
        await controller.setPin('482913');
        await controller.enable(LockMethod.pin);
        await controller.disable(keepPin: true);
        expect(container.read(appLockProvider).enabled, isFalse);
        expect(container.read(appLockProvider).hasPin, isTrue);
        await controller.enable(LockMethod.pin);
        await controller.disable(keepPin: false);
        expect(container.read(appLockProvider).hasPin, isFalse);
        expect(world.store.read('pin'), isNull);
      });

      test('a new PIN replaces the old and clears the wrong tries', () async {
        final container = world.container();
        addTearDown(container.dispose);
        final controller = container.read(appLockProvider.notifier);
        await controller.setPin('111111');
        controller.checkPin('000000');
        await controller.setPin('222222');
        expect(container.read(appLockProvider).failedAttempts, 0);
        expect(controller.checkPin('111111').ok, isFalse);
        expect(controller.checkPin('222222').ok, isTrue);
      });
    });

    test('signing out takes the lock away', () async {
      final container = world.container();
      addTearDown(container.dispose);
      // The lock must be read to listen.
      final controller = container.read(appLockProvider.notifier);
      await controller.setPin('482913');
      await controller.enable(LockMethod.pin);
      container.listen(authStateProvider, (previous, next) {});
      await Future<void>.delayed(Duration.zero);

      world.auth.signedOut();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(appLockProvider), const AppLockState());
      expect(world.store.keys, isEmpty);
    });
  });
}

class ProviderContainerHolder {
  ProviderContainerHolder(LockWorld world) : container = world.container() {
    controller = container.read(appLockProvider.notifier);
  }

  final ProviderContainer container;
  late final AppLockController controller;

  void dispose() => container.dispose();
}
