import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/app_lock/app_lock_models.dart';
import 'package:wecord/features/app_lock/lock_secret.dart';
import 'package:wecord/features/app_lock/lock_storage.dart';
import 'package:wecord/features/app_lock/system_authenticator.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The time the lock goes by; tests set their own.
final lockClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

// Keys in the lock storage.
const _enabledKey = 'app_enabled';
const _timeoutKey = 'app_timeout';
const _methodKey = 'app_method';
const _pinKey = 'pin';
const _failedKey = 'pin_failed';
const _waitKey = 'pin_wait_until';

/// The app lock: the app asks for Face ID, Touch ID, the device passcode or a
/// PIN when it was out of sight for longer than the person chose, and the PIN
/// that locked chats use on the web.
///
/// Everything is on this device. The PIN is kept as a salted hash; after five
/// wrong tries the app makes the person wait, longer each round. Signing out
/// wipes it all, which is also how a forgotten PIN is dealt with.
final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);

class AppLockController extends Notifier<AppLockState> {
  StoredSecret? _pin;
  DateTime? _leftAt;
  var _authenticating = false;

  /// Whether the lock screen asks the device by itself when it comes up. Not
  /// after "Lock now": the person asked to see the lock.
  var _promptOnShow = true;

  LockStorage get _storage => ref.read(lockStorageProvider);

  DateTime _now() => ref.read(lockClockProvider)();

  @override
  AppLockState build() {
    final storage = ref.read(lockStorageProvider);
    _pin = StoredSecret.decode(storage.read(_pinKey));
    final method = storage.read(_methodKey) == LockMethod.system.name
        ? LockMethod.system
        : LockMethod.pin;
    // A PIN lock whose PIN is gone cannot be opened, so it is off.
    final enabled =
        storage.read(_enabledKey) == '1' &&
        (method == LockMethod.system || _pin != null);
    final waitMs = int.tryParse(storage.read(_waitKey) ?? '');
    // Whoever signs out takes the lock with them.
    ref.listen<AsyncValue<AuthUser?>>(authStateProvider, (previous, next) {
      final hadUser = previous?.value != null;
      if (hadUser && next.hasValue && next.value == null) {
        unawaited(wipe());
      }
    });
    return AppLockState(
      enabled: enabled,
      // A cold start is a return after a long time away.
      locked: enabled,
      timeout: AppLockTimeout.fromName(storage.read(_timeoutKey)),
      method: method,
      hasPin: _pin != null,
      failedAttempts: int.tryParse(storage.read(_failedKey) ?? '') ?? 0,
      waitUntil: waitMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(waitMs),
    );
  }

  /// Whether the system prompt can be used on this device.
  Future<bool> systemAvailable() =>
      ref.read(systemAuthenticatorProvider).isAvailable();

  /// The method a new lock uses: the system's where the device has one, else
  /// the app's PIN.
  Future<LockMethod> preferredMethod() async =>
      await systemAvailable() ? LockMethod.system : LockMethod.pin;

  /// Shows the system prompt. The app going inactive while it shows does not
  /// count as leaving.
  Future<SystemAuthResult> authenticateWithSystem([String? reason]) async {
    _authenticating = true;
    try {
      return await ref
          .read(systemAuthenticatorProvider)
          .authenticate(reason ?? tr('Unlock WeCord'));
    } finally {
      _authenticating = false;
      // Coming back from the prompt is not coming back from the background.
      _leftAt = null;
    }
  }

  /// Whether a system prompt is up (the app going inactive then is the
  /// prompt, not the person leaving).
  bool get isAuthenticating => _authenticating;

  /// Asks the device to unlock the app (Face ID, Touch ID or the passcode).
  Future<SystemAuthResult> unlockWithSystem() async {
    if (_authenticating) {
      return SystemAuthResult.canceled;
    }
    final result = await authenticateWithSystem(tr('Unlock WeCord'));
    if (result == SystemAuthResult.success) {
      unlock();
    }
    return result;
  }

  /// Turns the app lock on with [method]. A PIN must be set first for the
  /// PIN method.
  Future<void> enable(LockMethod method) async {
    if (method == LockMethod.pin && _pin == null) {
      throw StateError('Set a PIN before turning the app lock on.');
    }
    await _storage.write(_enabledKey, '1');
    await _storage.write(_methodKey, method.name);
    // Turning it on from Settings leaves the app open.
    state = state.copyWith(enabled: true, locked: false, method: method);
  }

  /// Turns the app lock off. The caller has asked the person to prove it is
  /// them. The PIN stays while chats are locked with it ([keepPin]).
  Future<void> disable({required bool keepPin}) async {
    await _storage.write(_enabledKey, null);
    await _storage.write(_methodKey, null);
    state = state.copyWith(enabled: false, locked: false);
    if (!keepPin) {
      await removePin();
    }
  }

  Future<void> setTimeout(AppLockTimeout timeout) async {
    await _storage.write(_timeoutKey, timeout.name);
    state = state.copyWith(timeout: timeout);
  }

  /// Keeps [pin] (as a salted hash) and forgets the failed tries.
  Future<void> setPin(String pin) async {
    final secret = StoredSecret.of(pin);
    _pin = secret;
    await _storage.write(_pinKey, secret.encode());
    await _clearFailures();
    state = state.copyWith(hasPin: true, failedAttempts: 0, waitUntil: null);
  }

  Future<void> removePin() async {
    _pin = null;
    await _storage.write(_pinKey, null);
    await _clearFailures();
    state = state.copyWith(hasPin: false, failedAttempts: 0, waitUntil: null);
  }

  /// Checks [pin], counting a wrong one. After five wrong tries in a row the
  /// answer is [PinResult.waiting] until the wait is over, and a try then is
  /// not even looked at.
  PinResult checkPin(String pin) {
    final secret = _pin;
    if (secret == null) {
      return const PinResult.wrong(pinTriesBeforeWait);
    }
    final now = _now();
    final until = state.waitUntil;
    if (until != null && now.isBefore(until)) {
      return PinResult.waiting(until);
    }
    if (secret.accepts(pin)) {
      unawaited(_clearFailures());
      state = state.copyWith(failedAttempts: 0, waitUntil: null);
      return const PinResult.accepted();
    }
    final failures = state.failedAttempts + 1;
    final wait = pinWaitAfter(failures);
    final waitUntil = wait == null ? null : now.add(wait);
    unawaited(_storage.write(_failedKey, '$failures'));
    unawaited(
      _storage.write(
        _waitKey,
        waitUntil == null ? null : '${waitUntil.millisecondsSinceEpoch}',
      ),
    );
    state = state.copyWith(failedAttempts: failures, waitUntil: waitUntil);
    return waitUntil == null
        ? PinResult.wrong(state.triesLeft)
        : PinResult.waiting(waitUntil);
  }

  Future<void> _clearFailures() async {
    await _storage.write(_failedKey, null);
    await _storage.write(_waitKey, null);
  }

  /// Opens the app after the system prompt or the PIN passed.
  void unlock() {
    state = state.copyWith(locked: false);
  }

  /// Covers the app now (the "Lock now" button).
  void lockNow() {
    if (state.enabled) {
      _promptOnShow = false;
      state = state.copyWith(locked: true);
    }
  }

  /// Whether the lock screen that just came up asks the device at once; it
  /// does, except right after "Lock now".
  bool takePromptOnShow() {
    final prompt = _promptOnShow;
    _promptOnShow = true;
    return prompt;
  }

  /// The app went out of sight (the background, or on a computer another
  /// window in front).
  void appLeft() {
    if (_authenticating) {
      return;
    }
    _leftAt ??= _now();
    if (state.enabled && state.timeout == AppLockTimeout.immediately) {
      state = state.copyWith(locked: true);
    }
  }

  /// The app is in front again: locks it when it was away for longer than
  /// the person chose.
  void appReturned() {
    final left = _leftAt;
    _leftAt = null;
    if (left == null || !state.enabled || state.locked) {
      return;
    }
    if (_now().difference(left) >= state.timeout.duration) {
      state = state.copyWith(locked: true);
    }
  }

  /// Forgets the lock and every PIN try: after signing out (a forgotten PIN
  /// is dealt with by signing out), the next person starts without one.
  Future<void> wipe() async {
    _pin = null;
    for (final key in [
      _enabledKey,
      _timeoutKey,
      _methodKey,
      _pinKey,
      _failedKey,
      _waitKey,
    ]) {
      await _storage.write(key, null);
    }
    state = const AppLockState();
  }
}
