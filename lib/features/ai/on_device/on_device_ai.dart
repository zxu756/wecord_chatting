import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/ai/ai_models.dart';

/// Why the device's own language model can't be used right now (roadmap F8:
/// Apple Intelligence through the Foundation Models framework).
enum OnDeviceAiUnavailable {
  /// The web, Android, Windows and Linux have no on-device model.
  unsupportedPlatform,

  /// Before iOS 26 / macOS 26.
  osTooOld,

  /// The hardware can't run Apple Intelligence (an iPhone before the 15 Pro,
  /// an Intel Mac, a region where it isn't offered).
  deviceNotEligible,

  /// Apple Intelligence is switched off in the system Settings.
  notEnabled,

  /// The model is still downloading or preparing.
  modelNotReady,

  /// Anything else, or the check itself failed.
  unknown;

  static OnDeviceAiUnavailable fromCode(Object? code) {
    return switch (code) {
      'os_too_old' => osTooOld,
      'device_not_eligible' => deviceNotEligible,
      'not_enabled' => notEnabled,
      'model_not_ready' => modelNotReady,
      _ => unknown,
    };
  }

  /// Whether the person can do something about it (turn Apple Intelligence
  /// on, wait for the download). The others will not change on this device.
  bool get canChange =>
      this == notEnabled || this == modelNotReady || this == unknown;
}

/// Whether the on-device model can answer right now.
@immutable
class OnDeviceAiStatus {
  const OnDeviceAiStatus.available() : reason = null;

  const OnDeviceAiStatus.unavailable(OnDeviceAiUnavailable this.reason);

  /// Null when the model is available.
  final OnDeviceAiUnavailable? reason;

  bool get available => reason == null;

  @override
  bool operator ==(Object other) =>
      other is OnDeviceAiStatus && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

/// The model stopped being available between the check and the request. The
/// caller goes to the server, as if the model had not been available.
class OnDeviceAiUnavailableException implements Exception {
  const OnDeviceAiUnavailableException(this.reason);

  final OnDeviceAiUnavailable reason;

  @override
  String toString() => 'OnDeviceAiUnavailableException($reason)';
}

/// The model was available but could not process the text.
class OnDeviceAiFailedException implements Exception {
  const OnDeviceAiFailedException(this.kind);

  final OnDeviceAiFailureKind kind;

  @override
  String toString() => 'OnDeviceAiFailedException($kind)';
}

/// The device's own language model. Nothing a backend is given leaves the
/// device. The Mac and iPhone apps use the system's model through
/// `OnDeviceAiPlugin`; everywhere else there is none.
abstract interface class OnDeviceAiBackend {
  /// Whether the platform can have such a model at all (iOS and macOS, not
  /// the web). The settings only offer the choice where this is true.
  bool get isSupportedPlatform;

  /// Whether the model can answer now. Never throws and never starts a
  /// download.
  Future<OnDeviceAiStatus> availability();

  /// Bullet points for [lines] ("Name: text", oldest first). With [merge] the
  /// lines are the bullets of earlier summaries of parts of one chat.
  Future<String> summarize({
    required List<String> lines,
    required AiLanguage language,
    required bool recent,
    bool merge = false,
  });

  /// [text] rewritten as [mode] asks (never [AiRewriteMode.translate]).
  Future<String> rewrite({required AiRewriteMode mode, required String text});

  /// [text] translated into [target].
  Future<String> translate({required String text, required AiLanguage target});
}

/// Where there is no on-device model.
class NoOnDeviceAiBackend implements OnDeviceAiBackend {
  const NoOnDeviceAiBackend();

  @override
  bool get isSupportedPlatform => false;

  @override
  Future<OnDeviceAiStatus> availability() async =>
      const OnDeviceAiStatus.unavailable(
        OnDeviceAiUnavailable.unsupportedPlatform,
      );

  @override
  Future<String> summarize({
    required List<String> lines,
    required AiLanguage language,
    required bool recent,
    bool merge = false,
  }) => Future.error(
    const OnDeviceAiUnavailableException(
      OnDeviceAiUnavailable.unsupportedPlatform,
    ),
  );

  @override
  Future<String> rewrite({required AiRewriteMode mode, required String text}) =>
      Future.error(
        const OnDeviceAiUnavailableException(
          OnDeviceAiUnavailable.unsupportedPlatform,
        ),
      );

  @override
  Future<String> translate({
    required String text,
    required AiLanguage target,
  }) => Future.error(
    const OnDeviceAiUnavailableException(
      OnDeviceAiUnavailable.unsupportedPlatform,
    ),
  );
}

/// Apple's Foundation Models through the Runner apps' `OnDeviceAiPlugin`
/// (channel `wecord/on_device_ai`; see OnDeviceAiPlugin.swift for the calls).
class NativeOnDeviceAiBackend implements OnDeviceAiBackend {
  const NativeOnDeviceAiBackend({
    this._channel = const MethodChannel('wecord/on_device_ai'),
  });

  final MethodChannel _channel;

  @override
  bool get isSupportedPlatform => true;

  @override
  Future<OnDeviceAiStatus> availability() async {
    try {
      final info = await _channel.invokeMapMethod<String, Object?>(
        'availability',
      );
      if (info == null) {
        return const OnDeviceAiStatus.unavailable(
          OnDeviceAiUnavailable.unknown,
        );
      }
      if (info['available'] == true) {
        return const OnDeviceAiStatus.available();
      }
      return OnDeviceAiStatus.unavailable(
        OnDeviceAiUnavailable.fromCode(info['reason']),
      );
    } on MissingPluginException {
      return const OnDeviceAiStatus.unavailable(
        OnDeviceAiUnavailable.unsupportedPlatform,
      );
    } on Object {
      return const OnDeviceAiStatus.unavailable(OnDeviceAiUnavailable.unknown);
    }
  }

  Future<String> _text(String method, Map<String, Object?> arguments) async {
    try {
      final answer = await _channel.invokeMapMethod<String, Object?>(
        method,
        arguments,
      );
      final text = answer?['text'];
      if (text is! String || text.trim().isEmpty) {
        throw const OnDeviceAiFailedException(OnDeviceAiFailureKind.failed);
      }
      return text.trim();
    } on MissingPluginException {
      throw const OnDeviceAiUnavailableException(
        OnDeviceAiUnavailable.unsupportedPlatform,
      );
    } on PlatformException catch (error) {
      if (error.code == 'unavailable') {
        throw OnDeviceAiUnavailableException(
          OnDeviceAiUnavailable.fromCode(error.message),
        );
      }
      throw OnDeviceAiFailedException(
        OnDeviceAiFailureKind.fromCode(error.code),
      );
    }
  }

  @override
  Future<String> summarize({
    required List<String> lines,
    required AiLanguage language,
    required bool recent,
    bool merge = false,
  }) {
    return _text('summarize', {
      'lines': lines,
      'language': language.code,
      'recent': recent,
      'merge': merge,
    });
  }

  @override
  Future<String> rewrite({required AiRewriteMode mode, required String text}) {
    return _text('rewrite', {'mode': mode.code, 'text': text});
  }

  @override
  Future<String> translate({required String text, required AiLanguage target}) {
    return _text('translate', {'text': text, 'target': target.code});
  }
}

bool get _isApple =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// The on-device model of this platform: Apple's on iOS and macOS, none
/// elsewhere. Tests swap in a fake.
final onDeviceAiBackendProvider = Provider<OnDeviceAiBackend>(
  (ref) =>
      _isApple ? const NativeOnDeviceAiBackend() : const NoOnDeviceAiBackend(),
);

/// Whether the on-device model can answer now. Read again by invalidating
/// (the settings do when they open): Apple Intelligence can be switched on,
/// or finish downloading, while the app runs.
final onDeviceAiStatusProvider = FutureProvider<OnDeviceAiStatus>(
  (ref) => ref.watch(onDeviceAiBackendProvider).availability(),
);

/// Where "Prefer on-device AI" is kept; tests swap in memory.
abstract interface class OnDeviceAiPreferenceStore {
  Future<bool?> load();

  Future<void> save(bool enabled);
}

const _preferKey = 'wecord.ai.prefer_on_device';

class SharedPreferencesOnDeviceAiPreferenceStore
    implements OnDeviceAiPreferenceStore {
  const SharedPreferencesOnDeviceAiPreferenceStore();

  @override
  Future<bool?> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_preferKey);
  }

  @override
  Future<void> save(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_preferKey, enabled);
  }
}

class InMemoryOnDeviceAiPreferenceStore implements OnDeviceAiPreferenceStore {
  InMemoryOnDeviceAiPreferenceStore([this._enabled]);

  bool? _enabled;

  @override
  Future<bool?> load() async => _enabled;

  @override
  Future<void> save(bool enabled) async => _enabled = enabled;
}

final onDeviceAiPreferenceStoreProvider = Provider<OnDeviceAiPreferenceStore>(
  (ref) => const SharedPreferencesOnDeviceAiPreferenceStore(),
);

/// Settings → AI → "Prefer on-device AI": on by default, kept on this device.
/// On, summaries, rewriting and translation use the device's own model when it
/// can answer, so the text never leaves the device and does not count against
/// the daily limit; otherwise they use the server, as before. It only matters
/// where [OnDeviceAiBackend.isSupportedPlatform] is true.
final preferOnDeviceAiProvider = NotifierProvider<PreferOnDeviceAi, bool>(
  PreferOnDeviceAi.new,
);

class PreferOnDeviceAi extends Notifier<bool> {
  var _changed = false;

  @override
  bool build() {
    ref.read(onDeviceAiPreferenceStoreProvider).load().then((stored) {
      // A choice made while loading wins over the saved one.
      if (stored != null && !_changed && ref.mounted) {
        state = stored;
      }
    }, onError: (Object _) {});
    return true;
  }

  Future<void> set(bool enabled) async {
    _changed = true;
    state = enabled;
    try {
      await ref.read(onDeviceAiPreferenceStoreProvider).save(enabled);
    } on Object {
      // Still applies for this session.
    }
  }
}
