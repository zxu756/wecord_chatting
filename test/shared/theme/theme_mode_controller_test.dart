import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/theme/theme_mode_controller.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

void main() {
  ProviderContainer containerWith(ThemeModeStore store) {
    final container = ProviderContainer(
      overrides: [themeModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('follows the system until the saved choice loads', () async {
    final container = containerWith(InMemoryThemeModeStore(ThemeMode.dark));

    expect(container.read(themeModeProvider), ThemeMode.system);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('a new choice applies at once and is saved', () async {
    final store = InMemoryThemeModeStore();
    final container = containerWith(store);

    await container.read(themeModeProvider.notifier).set(ThemeMode.light);

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(await store.load(), ThemeMode.light);
  });

  test('the dark theme is dark', () {
    expect(WeCordTheme.dark().brightness, Brightness.dark);
    expect(WeCordTheme.light().brightness, Brightness.light);
  });
}
