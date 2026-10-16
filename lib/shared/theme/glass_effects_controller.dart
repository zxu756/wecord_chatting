import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _glassEffectsKey = 'wecord.appearance.glass_effects';

/// Where the Glass effects choice is kept; tests swap in memory.
abstract interface class GlassEffectsStore {
  Future<bool?> load();

  Future<void> save(bool enabled);
}

class SharedPreferencesGlassEffectsStore implements GlassEffectsStore {
  const SharedPreferencesGlassEffectsStore();

  @override
  Future<bool?> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_glassEffectsKey);
  }

  @override
  Future<void> save(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_glassEffectsKey, enabled);
  }
}

class InMemoryGlassEffectsStore implements GlassEffectsStore {
  InMemoryGlassEffectsStore([this._enabled]);

  bool? _enabled;

  @override
  Future<bool?> load() async => _enabled;

  @override
  Future<void> save(bool enabled) async => _enabled = enabled;
}

final glassEffectsStoreProvider = Provider<GlassEffectsStore>(
  (ref) => const SharedPreferencesGlassEffectsStore(),
);

/// Whether floating bars and menus use translucent, blurred glass (on by
/// default) or solid fills, remembered on this device.
final glassEffectsProvider = NotifierProvider<GlassEffectsController, bool>(
  GlassEffectsController.new,
);

class GlassEffectsController extends Notifier<bool> {
  var _changed = false;

  @override
  bool build() {
    ref.read(glassEffectsStoreProvider).load().then((enabled) {
      // A choice made while loading wins over the saved one.
      if (enabled != null && !_changed) {
        state = enabled;
      }
    }, onError: (Object _) {});
    return true;
  }

  Future<void> set(bool enabled) async {
    _changed = true;
    state = enabled;
    try {
      await ref.read(glassEffectsStoreProvider).save(enabled);
    } on Object {
      // Still applies for this session.
    }
  }
}

/// App-wide appearance choices that widgets below read without Riverpod
/// (the app puts one above every route). Defaults apply without one.
class WeCordAppearance extends InheritedWidget {
  const WeCordAppearance({
    required this.glassEffects,
    required super.child,
    super.key,
  });

  /// The Glass effects setting. Glass also turns solid when the platform
  /// asks for less motion or more contrast; see [glassOf].
  final bool glassEffects;

  static WeCordAppearance? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WeCordAppearance>();

  /// Whether glass surfaces should blur here: the setting is on and the
  /// platform doesn't ask for high contrast or reduced transparency
  /// (Flutter reports the latter through disableAnimations/highContrast).
  static bool glassOf(BuildContext context) {
    final enabled = maybeOf(context)?.glassEffects ?? true;
    if (!enabled) {
      return false;
    }
    final media = MediaQuery.maybeOf(context);
    return !(media?.highContrast ?? false) &&
        !(media?.disableAnimations ?? false);
  }

  @override
  bool updateShouldNotify(WeCordAppearance oldWidget) =>
      glassEffects != oldWidget.glassEffects;
}
