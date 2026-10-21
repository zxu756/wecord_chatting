import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/app_lock/app_lock_controller.dart';
import 'package:wecord/features/app_lock/app_lock_models.dart';
import 'package:wecord/features/app_lock/lock_secret.dart';
import 'package:wecord/features/app_lock/chat_lock_repository.dart';
import 'package:wecord/features/app_lock/lock_storage.dart';
import 'package:wecord/features/app_lock/pin_pad.dart';
import 'package:wecord/features/app_lock/system_authenticator.dart';
import 'package:wecord/features/auth/auth_repository.dart';

/// A device prompt that answers as told.
class FakeSystemAuthenticator implements SystemAuthenticator {
  FakeSystemAuthenticator({this.available = true});

  bool available;

  /// What the next prompts answer, first first; success when empty.
  final answers = <SystemAuthResult>[];
  final reasons = <String>[];

  /// Holds the prompt open until completed (the app goes inactive meanwhile).
  Completer<SystemAuthResult>? hold;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<SystemAuthResult> authenticate(String reason) async {
    reasons.add(reason);
    if (!available) {
      return SystemAuthResult.unavailable;
    }
    final pending = hold;
    if (pending != null) {
      return pending.future;
    }
    return answers.isEmpty ? SystemAuthResult.success : answers.removeAt(0);
  }
}

/// The time the lock goes by, moved by the test.
class LockClock {
  LockClock([DateTime? start]) : now = start ?? DateTime(2026, 10, 21, 12);

  DateTime now;

  void advance(Duration by) => now = now.add(by);

  DateTime call() => now;
}

/// The lock's collaborators, as fakes, and the overrides that install them.
class LockWorld {
  LockWorld({
    LockStorage? storage,
    FakeSystemAuthenticator? system,
    InMemoryChatLockRepository? repository,
    LockClock? clock,
    this.signedIn = true,
  }) : store = storage ?? InMemoryLockStorage(),
       system = system ?? FakeSystemAuthenticator(),
       repository = repository ?? InMemoryChatLockRepository(),
       clock = clock ?? LockClock();

  final LockStorage store;
  final FakeSystemAuthenticator system;
  final InMemoryChatLockRepository repository;
  final LockClock clock;
  final bool signedIn;

  late final FakeLockAuth auth = FakeLockAuth(signedIn: signedIn);

  /// Everything but the sign-in, for tests that bring their own.
  List<Override> get lockOverrides => [
    lockStorageProvider.overrideWithValue(store),
    systemAuthenticatorProvider.overrideWithValue(system),
    chatLockRepositoryProvider.overrideWithValue(repository),
    lockClockProvider.overrideWithValue(clock.call),
  ];

  List<Override> get overrides => [
    ...lockOverrides,
    authRepositoryProvider.overrideWithValue(auth),
  ];

  /// The app lock on, as a run of the app finds it: a PIN, or the device.
  void appLockOn({String? pin, AppLockTimeout? timeout}) {
    store.write('app_enabled', '1');
    store.write('app_method', pin == null ? 'system' : 'pin');
    if (pin != null) {
      store.write('pin', StoredSecret.of(pin).encode());
    }
    if (timeout != null) {
      store.write('app_timeout', timeout.name);
    }
  }

  ProviderContainer container() => ProviderContainer(overrides: overrides);
}

/// Sign-in and sign-out, as the auth state stream tells them.
class FakeLockAuth implements AuthRepository {
  FakeLockAuth({bool signedIn = true})
    : user = signedIn ? const AuthUser(id: 'user-1') : null;

  AuthUser? user;
  final _changes = StreamController<AuthUser?>.broadcast(sync: true);
  var signOutCalls = 0;

  void signInAs(AuthUser next) {
    user = next;
    _changes.add(next);
  }

  void signedOut() {
    user = null;
    _changes.add(null);
  }

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield user;
    yield* _changes.stream;
  }

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signOut() async {
    signOutCalls++;
    signedOut();
  }

  @override
  Future<void> ensureCurrentUserProfile() async {}

  @override
  Future<void> signUp(
    String email,
    String password,
    String username,
    String displayName,
  ) async {}
}

/// Types [pin] on the keypad on screen.
Future<void> typePin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.byKey(PinPad.digitKey(int.parse(digit))));
    await tester.pump();
  }
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
