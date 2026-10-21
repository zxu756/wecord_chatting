import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// How a system prompt (Face ID, Touch ID, the device passcode) ended.
enum SystemAuthResult {
  /// The person proved who they are.
  success,

  /// They closed the prompt, or the system did (a call came in).
  canceled,

  /// The prompt was shown and they did not pass.
  failed,

  /// Too many wrong tries: the system asks them to wait or to use the
  /// passcode.
  lockedOut,

  /// The device has no way to ask: no passcode set, or the web.
  unavailable,
}

/// The device's own way to ask "is this you": Face ID or Touch ID, and the
/// device passcode as the way back when the face or finger does not work. The
/// web has none, so it uses the app's PIN.
abstract interface class SystemAuthenticator {
  /// Whether this device can ask. False on the web and on a device with no
  /// passcode set.
  Future<bool> isAvailable();

  /// Shows the system prompt with [reason] as its text.
  Future<SystemAuthResult> authenticate(String reason);
}

/// The `local_auth` plugin: Face ID and Touch ID on iPhone and Mac, with the
/// passcode (or the Mac's password) as the way back.
class LocalAuthSystemAuthenticator implements SystemAuthenticator {
  LocalAuthSystemAuthenticator([this._plugin]);

  LocalAuthentication? _plugin;

  LocalAuthentication get _auth => _plugin ??= LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb) {
      return false;
    }
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<SystemAuthResult> authenticate(String reason) async {
    if (kIsWeb) {
      return SystemAuthResult.unavailable;
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        // The passcode is the backup when the face or finger fails.
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return ok ? SystemAuthResult.success : SystemAuthResult.failed;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.authInProgress ||
        LocalAuthExceptionCode.userRequestedFallback =>
          SystemAuthResult.canceled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => SystemAuthResult.lockedOut,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
        LocalAuthExceptionCode.uiUnavailable => SystemAuthResult.unavailable,
        _ => SystemAuthResult.failed,
      };
    } on Object {
      return SystemAuthResult.unavailable;
    }
  }
}

/// The device's prompt; tests replace it.
final systemAuthenticatorProvider = Provider<SystemAuthenticator>(
  (ref) => LocalAuthSystemAuthenticator(),
);

/// Whether the device can show the system prompt (asked once).
final systemAuthAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(systemAuthenticatorProvider).isAvailable(),
);
