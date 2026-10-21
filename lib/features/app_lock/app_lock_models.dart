import 'package:wecord/shared/l10n/l10n.dart';

/// How long the app may be out of sight before it asks again.
enum AppLockTimeout {
  immediately(Duration.zero),
  oneMinute(Duration(minutes: 1)),
  fiveMinutes(Duration(minutes: 5)),
  fifteenMinutes(Duration(minutes: 15)),
  oneHour(Duration(hours: 1));

  const AppLockTimeout(this.duration);

  final Duration duration;

  String get label => switch (this) {
    immediately => tr('Immediately'),
    oneMinute => tr('After 1 minute'),
    fiveMinutes => tr('After 5 minutes'),
    fifteenMinutes => tr('After 15 minutes'),
    oneHour => tr('After 1 hour'),
  };

  static AppLockTimeout fromName(String? name) {
    return AppLockTimeout.values.where((t) => t.name == name).firstOrNull ??
        AppLockTimeout.oneMinute;
  }
}

/// What proves the person is the owner of the device.
enum LockMethod {
  /// Face ID, Touch ID or the device passcode (iPhone and Mac).
  system,

  /// A PIN of the app's own (the web, and a device with no passcode).
  pin,
}

/// How many wrong PINs in a row are allowed before the app makes the person
/// wait.
const pinTriesBeforeWait = 5;

/// The length of a PIN.
const pinLength = 6;

/// How long to wait after [failures] wrong PINs in a row: nothing until the
/// fifth, then 30 seconds, 1 minute, 5 minutes, and 15 minutes for every five
/// after that. Null when the person may try again at once.
Duration? pinWaitAfter(int failures) {
  if (failures <= 0 || failures % pinTriesBeforeWait != 0) {
    return null;
  }
  const waits = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];
  final round = failures ~/ pinTriesBeforeWait;
  return waits[(round - 1).clamp(0, waits.length - 1)];
}

/// What the app lock is doing.
class AppLockState {
  const AppLockState({
    this.enabled = false,
    this.locked = false,
    this.timeout = AppLockTimeout.oneMinute,
    this.method = LockMethod.pin,
    this.hasPin = false,
    this.failedAttempts = 0,
    this.waitUntil,
  });

  /// The app asks to be unlocked.
  final bool enabled;

  /// The app is covered right now.
  final bool locked;
  final AppLockTimeout timeout;
  final LockMethod method;

  /// A PIN is set (chats can be locked with a PIN alone, without the app
  /// lock).
  final bool hasPin;

  /// Wrong PINs in a row.
  final int failedAttempts;

  /// After too many wrong PINs, when the next try is allowed.
  final DateTime? waitUntil;

  /// How many tries are left before the next wait.
  int get triesLeft => pinTriesBeforeWait - failedAttempts % pinTriesBeforeWait;

  AppLockState copyWith({
    bool? enabled,
    bool? locked,
    AppLockTimeout? timeout,
    LockMethod? method,
    bool? hasPin,
    int? failedAttempts,
    Object? waitUntil = _keep,
  }) {
    return AppLockState(
      enabled: enabled ?? this.enabled,
      locked: locked ?? this.locked,
      timeout: timeout ?? this.timeout,
      method: method ?? this.method,
      hasPin: hasPin ?? this.hasPin,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      waitUntil: identical(waitUntil, _keep)
          ? this.waitUntil
          : waitUntil as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppLockState &&
      other.enabled == enabled &&
      other.locked == locked &&
      other.timeout == timeout &&
      other.method == method &&
      other.hasPin == hasPin &&
      other.failedAttempts == failedAttempts &&
      other.waitUntil == waitUntil;

  @override
  int get hashCode => Object.hash(
    enabled,
    locked,
    timeout,
    method,
    hasPin,
    failedAttempts,
    waitUntil,
  );
}

const Object _keep = Object();

/// How a PIN try ended.
class PinResult {
  const PinResult._(this.ok, this.waitUntil, this.triesLeft);

  const PinResult.accepted() : this._(true, null, pinTriesBeforeWait);

  /// Wrong, with [triesLeft] tries before the next wait.
  const PinResult.wrong(int triesLeft) : this._(false, null, triesLeft);

  /// Not tried: the person must wait until [waitUntil].
  const PinResult.waiting(DateTime waitUntil) : this._(false, waitUntil, 0);

  final bool ok;
  final DateTime? waitUntil;
  final int triesLeft;

  bool get isWaiting => waitUntil != null;
}
