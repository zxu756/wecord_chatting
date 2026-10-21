// The app lock and chat lock, for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool: the lock
// screen with the PIN keypad and with the device's prompt, making a PIN, the
// settings page and its pickers, a locked chat asking to be opened, the chat
// list with a locked chat, the hidden chats shown after the secret code, and
// the chat actions with Lock chat.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/app_lock/lock_secret.dart';
import 'package:wecord/features/app_lock/system_authenticator.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/app_lock/lock_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

const _pin = '482913';

LockWorld _lock(PhoneWorld world, {void Function(LockWorld)? setUp}) {
  final lock = LockWorld();
  setUp?.call(lock);
  world.extraOverrides = lock.lockOverrides;
  return lock;
}

/// Locks the sample chats the lists and settings show.
void _someLockedChats(LockWorld lock) {
  lock.repository.locked.addAll({'dm-1', 'group-1'});
  lock.store.write('chat_ids', '["dm-1","group-1"]');
}

Future<void> _openSettings(
  WidgetTester tester,
  PhoneWorld world, {
  void Function(LockWorld)? setUp,
  bool unlockWithPin = false,
}) async {
  _lock(world, setUp: setUp);
  await world.open(tester, '/me');
  if (unlockWithPin) {
    await typePin(tester, _pin);
  }
  final tile = find.byKey(const ValueKey('app-lock-tile'));
  await scrollIntoView(tester, tile);
  await tester.ensureVisible(tile);
  await settle(tester);
  await tester.tap(tile);
  await settle(tester);
}

void _fullSettings(LockWorld lock) {
  lock.appLockOn();
  _someLockedChats(lock);
  lock.store.write('chat_hide', '1');
  lock.store.write('chat_secret', StoredSecret.of('letmein').encode());
}

Future<void> _scrollSettings(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
}

Future<void> _openLockedChat(
  WidgetTester tester,
  PhoneWorld world, {
  void Function(LockWorld)? setUp,
}) async {
  _lock(world, setUp: setUp);
  await world.open(
    tester,
    '/chats/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
}

/// The screens, in the order of the flows.
final appLockA11yScreens = <A11yScreen>[
  A11yScreen('app-lock-pin', (tester, world) async {
    _lock(world, setUp: (lock) => lock.appLockOn(pin: _pin));
    await world.open(tester, '/home');
  }),
  A11yScreen('app-lock-pin-wrong', (tester, world) async {
    _lock(world, setUp: (lock) => lock.appLockOn(pin: _pin));
    await world.open(tester, '/home');
    await typePin(tester, '111111');
  }),
  A11yScreen('app-lock-device', (tester, world) async {
    _lock(
      world,
      setUp: (lock) {
        lock.appLockOn();
        lock.system.answers.add(SystemAuthResult.canceled);
      },
    );
    await world.open(tester, '/home');
  }),
  A11yScreen('app-lock-settings-off', (tester, world) async {
    await _openSettings(tester, world);
  }),
  A11yScreen('app-lock-settings-on', (tester, world) async {
    await _openSettings(tester, world, setUp: _fullSettings);
  }),
  A11yScreen('app-lock-settings-chats', (tester, world) async {
    await _openSettings(tester, world, setUp: _fullSettings);
    await _scrollSettings(
      tester,
      find.byKey(const ValueKey('chat-lock-row-group-1')),
    );
  }),
  A11yScreen('app-lock-settings-pin', (tester, world) async {
    await _openSettings(
      tester,
      world,
      setUp: (lock) {
        lock.system.available = false;
        lock.appLockOn(pin: _pin);
        _someLockedChats(lock);
      },
      unlockWithPin: true,
    );
  }),
  A11yScreen('app-lock-timeout-picker', (tester, world) async {
    await _openSettings(tester, world, setUp: _fullSettings);
    await tester.tap(find.byKey(const ValueKey('app-lock-timeout')));
    await settle(tester);
  }),
  A11yScreen('secret-code-dialog', (tester, world) async {
    await _openSettings(tester, world);
    await _scrollSettings(tester, find.byKey(const ValueKey('chat-lock-hide')));
    await tester.tap(find.byKey(const ValueKey('chat-lock-hide')));
    await settle(tester);
  }),
  A11yScreen('pin-setup', (tester, world) async {
    await _openSettings(
      tester,
      world,
      setUp: (lock) => lock.system.available = false,
    );
    await tester.tap(find.byKey(const ValueKey('app-lock-toggle')));
    await settle(tester);
    await typePin(tester, '4829');
  }),
  A11yScreen('chat-lock-prompt', (tester, world) async {
    await _openLockedChat(
      tester,
      world,
      setUp: (lock) {
        lock.repository.locked.add('dm-1');
        lock.system.answers.add(SystemAuthResult.canceled);
      },
    );
  }),
  A11yScreen('chat-lock-prompt-pin', (tester, world) async {
    await _openLockedChat(
      tester,
      world,
      setUp: (lock) {
        lock.repository.locked.add('dm-1');
        lock.store.write('chat_ids', '["dm-1"]');
        lock.appLockOn(pin: _pin);
        lock.store.write('app_enabled', null);
      },
    );
  }),
  A11yScreen('chat-lock-set-pin', (tester, world) async {
    await _openLockedChat(
      tester,
      world,
      setUp: (lock) {
        lock.repository.locked.add('dm-1');
        lock.system.available = false;
      },
    );
  }),
  A11yScreen('chats-list-locked', (tester, world) async {
    _lock(world, setUp: _someLockedChats);
    await world.open(tester, '/home');
  }),
  A11yScreen('chat-actions-lock', (tester, world) async {
    _lock(world);
    await world.open(tester, '/home');
    await tester.longPress(find.byKey(const ValueKey('home-dm-dm-1')));
    await settle(tester);
  }),
  A11yScreen('hidden-chats-search', (tester, world) async {
    _lock(
      world,
      setUp: (lock) {
        _someLockedChats(lock);
        lock.store.write('chat_hide', '1');
        lock.store.write('chat_secret', StoredSecret.of('letmein').encode());
      },
    );
    await world.open(tester, GlobalMessageSearchScreen.path);
    await tester.enterText(
      find.byKey(const ValueKey('message-search-field')),
      'letmein',
    );
    await settle(tester);
  }),
  A11yScreen(
    'desktop-app-lock-pin',
    (tester, world) async {
      _lock(world, setUp: (lock) => lock.appLockOn(pin: _pin));
      await world.open(tester, '/home');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-app-lock-settings',
    (tester, world) async {
      _lock(world, setUp: _fullSettings);
      await world.open(tester, '/me');
      await tester.tap(find.byKey(const ValueKey('settings-nav-privacy')));
      await settle(tester);
      final tile = find.byKey(const ValueKey('app-lock-tile'));
      await tester.ensureVisible(tile);
      await settle(tester);
      await tester.tap(tile);
      await settle(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-chat-lock-prompt',
    (tester, world) async {
      _lock(
        world,
        setUp: (lock) {
          lock.repository.locked.add('dm-1');
          lock.system.answers.add(SystemAuthResult.canceled);
        },
      );
      await world.open(
        tester,
        '/chats/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
