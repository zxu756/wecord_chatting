import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';

/// Where the voice input choices are kept on this device; tests swap in
/// memory.
abstract interface class VoiceInputStore {
  /// Settings → Chats → "Show voice input"; null until it was ever changed.
  Future<bool?> loadShow();

  Future<void> saveShow(bool show);

  /// Whether the person agreed to their browser's speech service hearing
  /// what they say (the web asks once).
  Future<bool> loadBrowserConsent();

  Future<void> saveBrowserConsent();
}

const _showKey = 'wecord.voice_input.show';
const _browserConsentKey = 'wecord.voice_input.browser_consent';

class SharedPreferencesVoiceInputStore implements VoiceInputStore {
  const SharedPreferencesVoiceInputStore();

  @override
  Future<bool?> loadShow() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_showKey);
  }

  @override
  Future<void> saveShow(bool show) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_showKey, show);
  }

  @override
  Future<bool> loadBrowserConsent() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_browserConsentKey) ?? false;
  }

  @override
  Future<void> saveBrowserConsent() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_browserConsentKey, true);
  }
}

class InMemoryVoiceInputStore implements VoiceInputStore {
  InMemoryVoiceInputStore({this.show, this.browserConsent = false});

  bool? show;
  bool browserConsent;

  @override
  Future<bool?> loadShow() async => show;

  @override
  Future<void> saveShow(bool show) async => this.show = show;

  @override
  Future<bool> loadBrowserConsent() async => browserConsent;

  @override
  Future<void> saveBrowserConsent() async => browserConsent = true;
}

final voiceInputStoreProvider = Provider<VoiceInputStore>(
  (ref) => const SharedPreferencesVoiceInputStore(),
);

/// Settings → Chats → "Show voice input": on unless the person turns it off,
/// kept on this device.
final showVoiceInputProvider = NotifierProvider<ShowVoiceInputController, bool>(
  ShowVoiceInputController.new,
);

class ShowVoiceInputController extends Notifier<bool> {
  var _changed = false;

  @override
  bool build() {
    ref.read(voiceInputStoreProvider).loadShow().then((show) {
      // A choice made while loading wins over the saved one.
      if (show != null && !_changed && ref.mounted) {
        state = show;
      }
    }, onError: (Object _) {});
    return true;
  }

  Future<void> set(bool show) async {
    _changed = true;
    state = show;
    try {
      await ref.read(voiceInputStoreProvider).saveShow(show);
    } on Object {
      // Still applies for this session.
    }
  }
}

/// Whether this platform can dictate at all (the Settings row only shows
/// where it can).
final voiceInputSupportedProvider = Provider<bool>(
  (ref) => ref.watch(voiceRecognizerProvider).isSupported,
);

/// Whether the composer offers voice input: the platform can do it and the
/// person did not switch it off.
final voiceInputAvailableProvider = Provider<bool>(
  (ref) =>
      ref.watch(voiceInputSupportedProvider) &&
      ref.watch(showVoiceInputProvider),
);
