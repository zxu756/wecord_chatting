import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What Care mode (the elders' mode, Settings → Appearance) does on this
/// device. Care mode is one switch; the other three are its options, which
/// only matter while it is on.
@immutable
class CareModeSettings {
  const CareModeSettings({
    this.enabled = false,
    this.simpleHome = true,
    this.readAloud = true,
    this.highContrast = false,
  });

  /// Bigger text and tap areas everywhere, and the options below unless they
  /// were turned off.
  final bool enabled;

  /// The phone home keeps only Messages, Contacts and Moments: no circle
  /// rail, no folders, no shortcuts to saved messages, the agenda or dailies;
  /// the chat's menus keep the everyday entries.
  final bool simpleHome;

  /// "Read aloud" in a text message's long-press menu.
  final bool readAloud;

  /// The high contrast colors, whatever the phone's own setting says.
  final bool highContrast;

  /// Care mode is on and the simple home is wanted.
  bool get simplifies => enabled && simpleHome;

  /// Care mode is on and reading aloud is wanted.
  bool get readsAloud => enabled && readAloud;

  /// Care mode is on and the high contrast colors are wanted.
  bool get forcesHighContrast => enabled && highContrast;

  CareModeSettings copyWith({
    bool? enabled,
    bool? simpleHome,
    bool? readAloud,
    bool? highContrast,
  }) {
    return CareModeSettings(
      enabled: enabled ?? this.enabled,
      simpleHome: simpleHome ?? this.simpleHome,
      readAloud: readAloud ?? this.readAloud,
      highContrast: highContrast ?? this.highContrast,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CareModeSettings &&
      other.enabled == enabled &&
      other.simpleHome == simpleHome &&
      other.readAloud == readAloud &&
      other.highContrast == highContrast;

  @override
  int get hashCode => Object.hash(enabled, simpleHome, readAloud, highContrast);
}

const _enabledKey = 'wecord.care_mode.enabled';
const _simpleHomeKey = 'wecord.care_mode.simple_home';
const _readAloudKey = 'wecord.care_mode.read_aloud';
const _highContrastKey = 'wecord.care_mode.high_contrast';

/// Where the choices are kept on this device. [initial] is read at once: the
/// app reads it before the first frame, so a person who turned Care mode on
/// never sees the normal sizes flash by.
abstract interface class CareModeStore {
  CareModeSettings get initial;

  Future<void> save(CareModeSettings settings);
}

class SharedPreferencesCareModeStore implements CareModeStore {
  SharedPreferencesCareModeStore._(this._preferences, this.initial);

  /// Reads the saved choices. An unreadable store is an empty one.
  static Future<SharedPreferencesCareModeStore> open() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return SharedPreferencesCareModeStore._(
        preferences,
        CareModeSettings(
          enabled: preferences.getBool(_enabledKey) ?? false,
          simpleHome: preferences.getBool(_simpleHomeKey) ?? true,
          readAloud: preferences.getBool(_readAloudKey) ?? true,
          highContrast: preferences.getBool(_highContrastKey) ?? false,
        ),
      );
    } on Object {
      return SharedPreferencesCareModeStore._(null, const CareModeSettings());
    }
  }

  final SharedPreferences? _preferences;

  @override
  final CareModeSettings initial;

  @override
  Future<void> save(CareModeSettings settings) async {
    final preferences = _preferences;
    if (preferences == null) {
      return;
    }
    await preferences.setBool(_enabledKey, settings.enabled);
    await preferences.setBool(_simpleHomeKey, settings.simpleHome);
    await preferences.setBool(_readAloudKey, settings.readAloud);
    await preferences.setBool(_highContrastKey, settings.highContrast);
  }
}

/// Keeps the choices in memory: the default before the app opens the
/// device's store, and what tests use.
class InMemoryCareModeStore implements CareModeStore {
  InMemoryCareModeStore([this.initial = const CareModeSettings()]);

  @override
  CareModeSettings initial;

  /// What was saved last.
  CareModeSettings? saved;

  @override
  Future<void> save(CareModeSettings settings) async => saved = settings;
}

final careModeStoreProvider = Provider<CareModeStore>(
  (ref) => InMemoryCareModeStore(),
);

/// The Care mode choices, remembered on this device.
final careModeProvider = NotifierProvider<CareModeController, CareModeSettings>(
  CareModeController.new,
);

class CareModeController extends Notifier<CareModeSettings> {
  @override
  CareModeSettings build() => ref.read(careModeStoreProvider).initial;

  /// The one switch. Turning it off keeps the options for next time.
  Future<void> setEnabled(bool enabled) =>
      _set(state.copyWith(enabled: enabled));

  Future<void> setSimpleHome(bool value) =>
      _set(state.copyWith(simpleHome: value));

  Future<void> setReadAloud(bool value) =>
      _set(state.copyWith(readAloud: value));

  Future<void> setHighContrast(bool value) =>
      _set(state.copyWith(highContrast: value));

  Future<void> _set(CareModeSettings next) async {
    state = next;
    try {
      await ref.read(careModeStoreProvider).save(next);
    } on Object {
      // Still applies for this session.
    }
  }
}
