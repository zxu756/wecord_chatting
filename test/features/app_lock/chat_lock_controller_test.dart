import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/app_lock/app_lock_controller.dart';
import 'package:wecord/features/app_lock/chat_lock_controller.dart';
import 'package:wecord/features/app_lock/chat_lock_repository.dart';
import 'package:wecord/features/auth/auth_repository.dart';

import 'lock_fakes.dart';

Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late LockWorld world;

  setUp(() => world = LockWorld());

  Future<(ProviderContainer, ChatLockController)> start() async {
    final container = world.container();
    addTearDown(container.dispose);
    // Listened to, like the app does: the controller then keeps running.
    container.listen(chatLockProvider, (previous, next) {});
    final controller = container.read(chatLockProvider.notifier);
    await _settle();
    return (container, controller);
  }

  test('starts with nothing locked', () async {
    final (container, _) = await start();
    final state = container.read(chatLockProvider);
    expect(state.lockedIds, isEmpty);
    expect(state.hiddenIds, isEmpty);
    expect(state.hideLocked, isFalse);
    expect(state.hasSecretCode, isFalse);
  });

  group('locking', () {
    test('goes to the server and is kept on the device', () async {
      final (container, controller) = await start();
      await controller.lock('chat-1');
      expect(container.read(chatLockProvider).lockedIds, {'chat-1'});
      expect(world.repository.locked, {'chat-1'});
      expect(container.read(lockedConversationIdsProvider), {'chat-1'});

      final restarted = world.container();
      addTearDown(restarted.dispose);
      expect(restarted.read(chatLockProvider).lockedIds, {'chat-1'});
    });

    test('leaves the chat open for the person who just locked it', () async {
      final (container, controller) = await start();
      await controller.lock('chat-1');
      expect(container.read(chatLockProvider).unlockedIds, {'chat-1'});
      expect(controller.isOpen('chat-1'), isTrue);
    });

    test('locking twice asks the server once', () async {
      final (_, controller) = await start();
      await controller.lock('chat-1');
      await controller.lock('chat-1');
      expect(world.repository.calls, 1);
    });

    test('changes nothing when the server cannot be reached', () async {
      final (container, controller) = await start();
      world.repository.failWith = StateError('offline');
      await expectLater(controller.lock('chat-1'), throwsStateError);
      expect(container.read(chatLockProvider).lockedIds, isEmpty);
      expect(world.store.read('chat_ids'), isNull);
    });

    test('unlocking goes to the server too', () async {
      final (container, controller) = await start();
      await controller.lock('chat-1');
      await controller.lock('chat-2');
      await controller.unlock('chat-1');
      expect(container.read(chatLockProvider).lockedIds, {'chat-2'});
      expect(world.repository.locked, {'chat-2'});
      expect(controller.isOpen('chat-1'), isTrue, reason: 'not locked');
      world.repository.failWith = StateError('offline');
      await expectLater(controller.unlock('chat-2'), throwsStateError);
      expect(container.read(chatLockProvider).lockedIds, {'chat-2'});
    });
  });

  group('the server list', () {
    test('replaces what the device kept once it answers', () async {
      world.store.write('chat_ids', '["old"]');
      world.repository.locked.addAll({'a', 'b'});
      final (container, _) = await start();
      expect(container.read(chatLockProvider).lockedIds, {'a', 'b'});
      expect(world.store.read('chat_ids'), contains('"a"'));
    });

    test('is shown at once from the device, offline', () async {
      world.store.write('chat_ids', '["old"]');
      world.repository.failWith = StateError('offline');
      final (container, _) = await start();
      expect(container.read(chatLockProvider).lockedIds, {'old'});
    });

    test('unlocking on another device unlocks here after a refresh', () async {
      world.repository.locked.add('a');
      final (container, controller) = await start();
      expect(container.read(chatLockProvider).lockedIds, {'a'});
      world.repository.locked.clear();
      await controller.refresh();
      expect(container.read(chatLockProvider).lockedIds, isEmpty);
    });

    test('rubbish on the device is nothing', () async {
      world.store.write('chat_ids', 'not json');
      world.repository.failWith = StateError('offline');
      final (container, _) = await start();
      expect(container.read(chatLockProvider).lockedIds, isEmpty);
    });

    test('is not asked for when nobody is signed in', () async {
      final signedOut = LockWorld(signedIn: false);
      signedOut.repository.locked.add('a');
      final container = signedOut.container();
      addTearDown(container.dispose);
      container.listen(chatLockProvider, (previous, next) {});
      container.read(chatLockProvider.notifier);
      await _settle();
      expect(container.read(chatLockProvider).lockedIds, isEmpty);
    });
  });

  group('opening a locked chat', () {
    test('asks until the person proves who they are', () async {
      world.repository.locked.add('a');
      final (container, controller) = await start();
      expect(controller.isOpen('a'), isFalse);
      controller.markOpened('a');
      expect(controller.isOpen('a'), isTrue);
      expect(container.read(chatLockProvider).unlockedIds, {'a'});
    });

    test('stays open for a minute after the chat is left', () async {
      world.repository.locked.add('a');
      final (_, controller) = await start();
      controller.markOpened('a');
      controller.markLeft('a');
      world.clock.advance(const Duration(seconds: 59));
      expect(controller.isOpen('a'), isTrue);
      world.clock.advance(const Duration(seconds: 2));
      expect(controller.isOpen('a'), isFalse);
    });

    test('opening it again before the minute is over keeps it open', () async {
      world.repository.locked.add('a');
      final (_, controller) = await start();
      controller.markOpened('a');
      controller.markLeft('a');
      world.clock.advance(const Duration(seconds: 50));
      controller.markOpened('a');
      world.clock.advance(const Duration(minutes: 10));
      expect(controller.isOpen('a'), isTrue, reason: 'it is on screen');
    });

    test('a chat never opened is not left open by leaving it', () async {
      world.repository.locked.add('a');
      final (_, controller) = await start();
      controller.markLeft('a');
      expect(controller.isOpen('a'), isFalse);
    });

    test('relocking asks again, for one chat or all', () async {
      world.repository.locked.addAll({'a', 'b'});
      final (container, controller) = await start();
      controller.markOpened('a');
      controller.markOpened('b');
      controller.relock('a');
      expect(controller.isOpen('a'), isFalse);
      expect(controller.isOpen('b'), isTrue);
      controller.relockAll();
      expect(controller.isOpen('b'), isFalse);
      expect(container.read(chatLockProvider).unlockedIds, isEmpty);
    });
  });

  group('hiding and the secret code', () {
    test('hidden chats are the locked ones, until the code is typed', () async {
      world.repository.locked.addAll({'a', 'b'});
      final (container, controller) = await start();
      expect(container.read(hiddenConversationIdsProvider), isEmpty);

      await controller.setSecretCode('Open Sesame');
      await controller.setHideLocked(true);
      expect(container.read(hiddenConversationIdsProvider), {'a', 'b'});

      expect(controller.tryReveal('open'), isFalse);
      expect(container.read(hiddenConversationIdsProvider), {'a', 'b'});
      expect(controller.tryReveal('open sesame'), isTrue);
      expect(container.read(hiddenConversationIdsProvider), isEmpty);
      expect(container.read(chatLockProvider).revealed, isTrue);
    });

    test('the code ignores case and the spaces around it', () async {
      final (_, controller) = await start();
      await controller.setSecretCode('Open Sesame');
      await controller.setHideLocked(true);
      expect(controller.tryReveal('  OPEN SESAME '), isTrue);
    });

    test('is kept as a salted hash, never as text', () async {
      final (_, controller) = await start();
      await controller.setSecretCode('Open Sesame');
      final kept = world.store.read('chat_secret')!;
      expect(kept.toLowerCase(), isNot(contains('sesame')));
    });

    test('shows nothing when hiding is off or there is no code', () async {
      final (container, controller) = await start();
      expect(controller.tryReveal('whatever'), isFalse);
      await controller.setSecretCode('letmein');
      expect(controller.tryReveal('letmein'), isFalse, reason: 'not hiding');
      expect(container.read(chatLockProvider).revealed, isFalse);
    });

    test('too short and too long guesses are not even checked', () async {
      final (_, controller) = await start();
      await controller.setSecretCode('abcd');
      await controller.setHideLocked(true);
      expect(controller.tryReveal('abc'), isFalse);
      expect(controller.tryReveal('abcd'), isTrue);
      controller.hideAgain();
      expect(controller.tryReveal('a' * 21), isFalse);
    });

    test('hides again by hand, and when the app was away', () async {
      world.repository.locked.add('a');
      final (container, controller) = await start();
      await controller.setSecretCode('letmein');
      await controller.setHideLocked(true);
      controller.tryReveal('letmein');
      controller.hideAgain();
      expect(container.read(hiddenConversationIdsProvider), {'a'});
      controller.tryReveal('letmein');
      controller.relockAll();
      expect(container.read(hiddenConversationIdsProvider), {'a'});
    });

    test('removing the code forgets it', () async {
      final (container, controller) = await start();
      await controller.setSecretCode('letmein');
      await controller.setHideLocked(true);
      await controller.clearSecretCode();
      expect(container.read(chatLockProvider).hasSecretCode, isFalse);
      expect(controller.tryReveal('letmein'), isFalse);
      expect(world.store.read('chat_secret'), isNull);
    });

    test('settings survive a restart', () async {
      world.repository.failWith = StateError('offline');
      final (_, controller) = await start();
      await controller.setSecretCode('letmein');
      await controller.setHideLocked(true);
      final restarted = world.container();
      addTearDown(restarted.dispose);
      final state = restarted.read(chatLockProvider);
      expect(state.hideLocked, isTrue);
      expect(state.hasSecretCode, isTrue);
      expect(state.revealed, isFalse);
      expect(
        restarted.read(chatLockProvider.notifier).tryReveal('letmein'),
        isTrue,
      );
    });
  });

  group('signing out', () {
    test('takes the device settings with it', () async {
      world.repository.locked.add('a');
      final (container, controller) = await start();
      await controller.setSecretCode('letmein');
      await controller.setHideLocked(true);
      // The app lock listens too.
      container.read(appLockProvider);

      world.auth.signedOut();
      await _settle();

      final state = container.read(chatLockProvider);
      expect(state.lockedIds, isEmpty);
      expect(state.hideLocked, isFalse);
      expect(state.hasSecretCode, isFalse);
      expect(world.store.read('chat_ids'), isNull);
      expect(world.store.read('chat_secret'), isNull);
    });

    test('another person signing in starts from their own list', () async {
      world.repository.locked.add('a');
      final (container, _) = await start();
      expect(container.read(chatLockProvider).lockedIds, {'a'});

      world.repository.locked
        ..clear()
        ..add('z');
      world.auth.signInAs(const AuthUser(id: 'user-2'));
      await _settle();

      expect(container.read(chatLockProvider).lockedIds, {'z'});
    });
  });

  test('the in-memory server keeps a list', () async {
    final repository = InMemoryChatLockRepository({'a'});
    await repository.setLocked('b', locked: true);
    await repository.setLocked('a', locked: false);
    expect(await repository.load(), {'b'});
  });
}
