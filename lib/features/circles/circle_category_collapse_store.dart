import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final circleCategoryCollapseStoreProvider =
    Provider<CircleCategoryCollapseStore>((ref) {
      return const SharedPreferencesCircleCategoryCollapseStore();
    });

/// Which channel categories of a circle are collapsed on this device.
abstract interface class CircleCategoryCollapseStore {
  Future<Set<String>> load(String circleId);

  Future<void> save(String circleId, Set<String> collapsedCategoryIds);
}

class SharedPreferencesCircleCategoryCollapseStore
    implements CircleCategoryCollapseStore {
  const SharedPreferencesCircleCategoryCollapseStore();

  static String _key(String circleId) =>
      'wecord.circles.$circleId.collapsed_categories';

  @override
  Future<Set<String>> load(String circleId) async {
    final preferences = await SharedPreferences.getInstance();
    return {...?preferences.getStringList(_key(circleId))};
  }

  @override
  Future<void> save(String circleId, Set<String> collapsedCategoryIds) async {
    final preferences = await SharedPreferences.getInstance();
    if (collapsedCategoryIds.isEmpty) {
      await preferences.remove(_key(circleId));
      return;
    }
    await preferences.setStringList(
      _key(circleId),
      [...collapsedCategoryIds]..sort(),
    );
  }
}
