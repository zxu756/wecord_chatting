import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

const _densityKey = 'wecord.appearance.density';

/// Where the Density choice is kept; tests swap in memory.
abstract interface class DensityStore {
  Future<WeCordDensity?> load();

  Future<void> save(WeCordDensity density);
}

class SharedPreferencesDensityStore implements DensityStore {
  const SharedPreferencesDensityStore();

  @override
  Future<WeCordDensity?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final name = preferences.getString(_densityKey);
    return WeCordDensity.values.where((d) => d.name == name).firstOrNull;
  }

  @override
  Future<void> save(WeCordDensity density) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_densityKey, density.name);
  }
}

class InMemoryDensityStore implements DensityStore {
  InMemoryDensityStore([this._density]);

  WeCordDensity? _density;

  @override
  Future<WeCordDensity?> load() async => _density;

  @override
  Future<void> save(WeCordDensity density) async => _density = density;
}

final densityStoreProvider = Provider<DensityStore>(
  (ref) => const SharedPreferencesDensityStore(),
);

/// Comfortable, Default or Compact lists and messages, remembered on this
/// device. Default until the saved choice has loaded.
final densityProvider = NotifierProvider<DensityController, WeCordDensity>(
  DensityController.new,
);

class DensityController extends Notifier<WeCordDensity> {
  var _changed = false;

  @override
  WeCordDensity build() {
    ref.read(densityStoreProvider).load().then((density) {
      // A choice made while loading wins over the saved one.
      if (density != null && !_changed) {
        state = density;
      }
    }, onError: (Object _) {});
    return WeCordDensity.standard;
  }

  Future<void> set(WeCordDensity density) async {
    _changed = true;
    state = density;
    try {
      await ref.read(densityStoreProvider).save(density);
    } on Object {
      // Still applies for this session.
    }
  }
}
