import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/app_lock/app_lock_gate.dart';
import 'package:wecord/features/app_lock/chat_lock_controller.dart';
import 'package:wecord/features/app_lock/chat_lock_gate.dart';
import 'package:wecord/features/app_lock/hidden_chats_section.dart';
import 'package:wecord/features/app_lock/lock_secret.dart';
import 'package:wecord/features/app_lock/pin_pad.dart';
import 'package:wecord/features/app_lock/system_authenticator.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../mobile/phone_test_support.dart';
import 'lock_fakes.dart';

/// The app lock covering the app, and a locked chat asking before it opens.
void main() {
  late PhoneWorld world;
  late LockWorld lock;

  Future<void> open(
    WidgetTester tester, {
    String location = '/home',
    Object? extra,
  }) async {
    usePhoneViewport(tester, notchedPhone);
    world.extraOverrides = lock.lockOverrides;
    await world.open(tester, location, extra: extra);
  }

  setUp(() {
    world = PhoneWorld();
    lock = LockWorld();
  });

  final list = find.byKey(const ValueKey('phone-messages-list'));
  final lockScreen = find.byKey(AppLockScreen.screenKey);

  group('the app lock', () {
    testWidgets('covers the app until the PIN is typed', (tester) async {
      lock.appLockOn(pin: '482913');
      await open(tester);

      expect(lockScreen, findsOneWidget);
      expect(find.text('WeCord is locked'), findsOneWidget);
      // Nothing of the app can be seen, read or tapped, but it is still there.
      expect(list, findsNothing);
      expect(find.byKey(const ValueKey('home-dm-dm-1')), findsNothing);
      expect(list.hitTestable(), findsNothing);

      await typePin(tester, '482913');
      expect(lockScreen, findsNothing);
      expect(list, findsOneWidget);
    });

    testWidgets('a wrong PIN says how many tries are left', (tester) async {
      lock.appLockOn(pin: '482913');
      await open(tester);

      await typePin(tester, '111111');
      expect(lockScreen, findsOneWidget);
      expect(find.text('Wrong PIN. 4 tries left.'), findsOneWidget);
      // The keypad is empty again.
      await typePin(tester, '222222');
      expect(find.text('Wrong PIN. 3 tries left.'), findsOneWidget);
    });

    testWidgets('five wrong PINs make the person wait', (tester) async {
      lock.appLockOn(pin: '482913');
      await open(tester);

      for (var i = 0; i < 5; i++) {
        await typePin(tester, '111111');
      }
      expect(
        find.textContaining('Too many tries. Try again in 0:30'),
        findsOneWidget,
      );
      // Even the right PIN is not taken meanwhile: the keys are off.
      await tester.tap(find.byKey(PinPad.digitKey(4)));
      await tester.pump();
      expect(lockScreen, findsOneWidget);
    });

    testWidgets('covers a chat opened from a link or a notification', (
      tester,
    ) async {
      lock.appLockOn(pin: '482913');
      await open(
        tester,
        location: '/chats/dm-1',
        extra: const ChatThreadRouteExtra(
          title: 'Bart the Bold',
          type: ConversationType.direct,
        ),
      );
      expect(lockScreen, findsOneWidget);
      await typePin(tester, '482913');
      expect(find.byType(ChatThreadScreen), findsOneWidget);
    });

    testWidgets('asks the device at once, and again by button', (tester) async {
      lock.appLockOn();
      lock.system.answers.add(SystemAuthResult.canceled);
      await open(tester);

      expect(lock.system.reasons, ['Unlock WeCord']);
      expect(lockScreen, findsOneWidget);
      expect(find.byKey(AppLockScreen.unlockKey), findsOneWidget);

      await tester.tap(find.byKey(AppLockScreen.unlockKey));
      await settle(tester);
      expect(lock.system.reasons, hasLength(2));
      expect(lockScreen, findsNothing);
      expect(list, findsOneWidget);
    });

    testWidgets('opens at once when the device says yes', (tester) async {
      lock.appLockOn();
      await open(tester);
      expect(lockScreen, findsNothing);
      expect(list, findsOneWidget);
    });

    testWidgets('a device that can no longer ask offers signing out', (
      tester,
    ) async {
      lock.appLockOn();
      lock.system.available = false;
      await open(tester);
      expect(find.byKey(AppLockScreen.unlockKey), findsNothing);
      expect(
        find.textContaining('This device can no longer check who you are'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('forgot-pin')), findsOneWidget);
    });

    testWidgets('locks again after the app was away for the chosen time', (
      tester,
    ) async {
      lock.appLockOn(pin: '482913');
      await open(tester);
      await typePin(tester, '482913');
      expect(lockScreen, findsNothing);

      final binding = tester.binding;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }
      lock.clock.advance(const Duration(seconds: 30));
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }
      await settle(tester);
      expect(lockScreen, findsNothing, reason: 'half a minute is not enough');

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }
      lock.clock.advance(const Duration(minutes: 2));
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }
      await settle(tester);
      expect(lockScreen, findsOneWidget);
      expect(list, findsNothing);
    });

    testWidgets('does not cover the sign-in page', (tester) async {
      lock.appLockOn(pin: '482913');
      world.auth.user = null;
      await open(tester);
      expect(lockScreen, findsNothing);
      expect(find.text('Sign in'), findsWidgets);
    });
  });

  group('a locked chat', () {
    ChatThreadRouteExtra extra() => const ChatThreadRouteExtra(
      title: 'Bart the Bold',
      type: ConversationType.direct,
    );

    testWidgets('opens only after the device says yes', (tester) async {
      lock.repository.locked.add('dm-1');
      lock.system.answers.add(SystemAuthResult.canceled);
      await open(tester, location: '/chats/dm-1', extra: extra());

      expect(find.byKey(ChatLockGate.promptKey), findsOneWidget);
      expect(find.text('This chat is locked'), findsOneWidget);
      // Not the name, not the messages; the chat page is not even built.
      expect(find.text('Bart the Bold'), findsNothing);
      expect(find.byType(ChatThreadScreen), findsNothing);

      await tester.tap(find.byKey(ChatLockGate.unlockKey));
      await settle(tester);
      expect(find.byKey(ChatLockGate.promptKey), findsNothing);
      expect(find.byType(ChatThreadScreen), findsOneWidget);
      expect(lock.system.reasons.last, 'Unlock this chat');
    });

    testWidgets('asks at once when it comes up', (tester) async {
      lock.repository.locked.add('dm-1');
      await open(tester, location: '/chats/dm-1', extra: extra());
      expect(lock.system.reasons, ['Unlock this chat']);
      expect(find.byType(ChatThreadScreen), findsOneWidget);
    });

    testWidgets('asks for the PIN where there is one', (tester) async {
      lock.store.write('chat_ids', '["dm-1"]');
      lock.repository.locked.add('dm-1');
      lock.appLockOn(pin: '482913');
      lock.store.write('app_enabled', null);
      await open(tester, location: '/chats/dm-1', extra: extra());

      expect(find.byKey(ChatLockGate.promptKey), findsOneWidget);
      expect(find.text('Enter your PIN to open it.'), findsOneWidget);
      await typePin(tester, '111111');
      expect(find.byType(ChatThreadScreen), findsNothing);
      await typePin(tester, '482913');
      expect(find.byType(ChatThreadScreen), findsOneWidget);
    });

    testWidgets('a device with no way to ask makes a PIN first', (
      tester,
    ) async {
      lock.repository.locked.add('dm-1');
      lock.system.available = false;
      await open(tester, location: '/chats/dm-1', extra: extra());

      expect(
        find.text('Set a PIN on this device to open your locked chats.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ChatLockGate.unlockKey));
      await settle(tester);
      expect(find.text('Choose a PIN'), findsOneWidget);
      await typePin(tester, '654321');
      expect(find.text('Enter it again'), findsOneWidget);
      await typePin(tester, '654321');
      expect(find.byType(ChatThreadScreen), findsOneWidget);
    });

    testWidgets('an unlocked chat opens as always', (tester) async {
      await open(tester, location: '/chats/dm-1', extra: extra());
      expect(find.byKey(ChatLockGate.promptKey), findsNothing);
      expect(lock.system.reasons, isEmpty);
      expect(find.byType(ChatThreadScreen), findsOneWidget);
    });

    testWidgets('can be locked from the chat\'s More menu', (tester) async {
      await open(tester, location: '/chats/dm-1', extra: extra());
      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await tester.pumpAndSettle();
      expect(find.text('Lock chat'), findsOneWidget);
      await tester.tap(find.text('Lock chat'));
      await settle(tester);

      expect(lock.repository.locked, {'dm-1'});
      expect(find.textContaining('Chat locked.'), findsOneWidget);
      // The chat stays open for the person who just locked it.
      expect(find.byType(ChatThreadScreen), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await tester.pumpAndSettle();
      expect(find.text('Unlock chat'), findsOneWidget);
    });

    testWidgets('can be unlocked from the menu after proving who you are', (
      tester,
    ) async {
      lock.repository.locked.add('dm-1');
      await open(tester, location: '/chats/dm-1', extra: extra());
      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock chat'));
      await settle(tester);
      expect(lock.repository.locked, isEmpty);
      expect(find.text('Chat unlocked'), findsOneWidget);
    });

    testWidgets('stays locked when the person does not pass', (tester) async {
      lock.repository.locked.add('dm-1');
      lock.system.answers.addAll([
        SystemAuthResult.success,
        SystemAuthResult.failed,
      ]);
      await open(tester, location: '/chats/dm-1', extra: extra());
      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock chat'));
      await settle(tester);
      expect(lock.repository.locked, {'dm-1'});
    });

    testWidgets('tells the person when the server cannot be reached', (
      tester,
    ) async {
      await open(tester, location: '/chats/dm-1', extra: extra());
      lock.repository.failWith = StateError('offline');
      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lock chat'));
      await settle(tester);
      expect(
        find.text(
          'Could not change the lock. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(lock.repository.locked, isEmpty);
    });
  });

  group('the chat list', () {
    final bart = find.byKey(const ValueKey('home-dm-dm-1'));
    final group = find.byKey(const ValueKey('home-dm-group-1'));

    testWidgets('shows no message for a locked chat', (tester) async {
      lock.repository.locked.add('dm-1');
      lock.store.write('chat_ids', '["dm-1"]');
      await open(tester);

      expect(bart, findsOneWidget);
      expect(
        find.descendant(of: bart, matching: find.text('Locked chat')),
        findsOneWidget,
      );
      expect(find.textContaining('release notes'), findsNothing);
      // Another chat is as it was.
      expect(
        find.descendant(of: group, matching: find.textContaining('Trailhead')),
        findsOneWidget,
      );
      // The row still says how many are unread: a number, not words.
      expect(
        find.descendant(of: bart, matching: find.text('99+')),
        findsOneWidget,
      );
    });

    testWidgets('leaves a hidden chat out until the code is typed', (
      tester,
    ) async {
      lock.repository.locked.add('dm-1');
      lock.store.write('chat_ids', '["dm-1"]');
      lock.store.write('chat_hide', '1');
      lock.store.write('chat_secret', StoredSecret.of('letmein').encode());
      await open(tester);

      expect(bart, findsNothing);
      expect(group, findsOneWidget);

      // Typing the code in search shows the hidden chats there and in the list.
      world.router.go(GlobalMessageSearchScreen.path);
      await settle(tester);
      expect(find.byKey(HiddenChatsSection.sectionKey), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('message-search-field')),
        'letmei',
      );
      await settle(tester);
      expect(find.byKey(HiddenChatsSection.sectionKey), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('message-search-field')),
        'letmein',
      );
      await settle(tester);
      expect(find.byKey(HiddenChatsSection.sectionKey), findsOneWidget);
      expect(find.byKey(const ValueKey('hidden-chat-dm-1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('hidden-chats-hide-again')));
      await settle(tester);
      expect(find.byKey(HiddenChatsSection.sectionKey), findsNothing);
    });

    testWidgets('shows a hidden chat locked once the code was typed', (
      tester,
    ) async {
      lock.repository.locked.add('dm-1');
      lock.store.write('chat_ids', '["dm-1"]');
      lock.store.write('chat_hide', '1');
      lock.store.write('chat_secret', StoredSecret.of('letmein').encode());
      await open(tester);
      final container = ProviderScope.containerOf(tester.element(list));
      expect(
        container.read(chatLockProvider.notifier).tryReveal('letmein'),
        isTrue,
      );
      await settle(tester);

      expect(bart, findsOneWidget);
      expect(
        find.descendant(of: bart, matching: find.text('Locked chat')),
        findsOneWidget,
      );
    });

    testWidgets('the long-press menu offers Lock chat', (tester) async {
      await open(tester);
      await tester.longPress(bart);
      await settle(tester);
      expect(find.text('Lock chat'), findsOneWidget);
      await tester.tap(find.text('Lock chat'));
      await settle(tester);
      expect(lock.repository.locked, {'dm-1'});
      expect(
        find.descendant(of: bart, matching: find.text('Locked chat')),
        findsOneWidget,
      );
    });
  });
}
