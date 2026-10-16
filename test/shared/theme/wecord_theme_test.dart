import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/theme/glass_effects_controller.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

void main() {
  group('WeCordTheme', () {
    test('carries the tokens for its brightness', () {
      expect(WeCordTheme.light().extension<WeCordTokens>(), WeCordTokens.light);
      expect(WeCordTheme.dark().extension<WeCordTokens>(), WeCordTokens.dark);
    });

    test('maps the palette onto the Material roles', () {
      final light = WeCordTheme.light().colorScheme;
      expect(light.primary, const Color(0xFF2F6BF6));
      expect(light.onSurface, const Color(0xFF17171A));
      expect(light.surface, Colors.white);
      expect(light.error, const Color(0xFFE12F35));

      final dark = WeCordTheme.dark().colorScheme;
      expect(dark.primary, const Color(0xFF6E95FF));
      expect(dark.surface, const Color(0xFF1B1B1E));
      expect(dark.onSurface, const Color(0xFFF3F2EF));
    });

    test('uses the bundled font with a CJK fallback and no ripples', () {
      final theme = WeCordTheme.light();
      expect(theme.textTheme.bodyMedium?.fontFamily, WeCordTheme.fontFamily);
      expect(
        theme.textTheme.bodyMedium?.fontFamilyFallback,
        WeCordTheme.fontFamilyFallback,
      );
      expect(WeCordTheme.fontFamilyFallback, isNotEmpty);
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(theme.textTheme.headlineLarge?.fontSize, 26);
      expect(theme.textTheme.headlineLarge?.fontWeight, FontWeight.w800);
    });

    test('tokens interpolate between themes', () {
      final halfway = WeCordTokens.light.lerp(WeCordTokens.dark, 0.5);
      expect(
        halfway.colors.panel,
        Color.lerp(Colors.white, const Color(0xFF1B1B1E), 0.5),
      );
    });

    testWidgets('tokens fall back by brightness without the extension', (
      tester,
    ) async {
      late WeCordTokens tokens;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) {
              tokens = context.tokens;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(tokens, WeCordTokens.dark);
    });
  });

  group('glass effects', () {
    ProviderContainer containerWith(GlassEffectsStore store) {
      final container = ProviderContainer(
        overrides: [glassEffectsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('are on until a saved choice loads', () async {
      final container = containerWith(InMemoryGlassEffectsStore(false));

      expect(container.read(glassEffectsProvider), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(glassEffectsProvider), isFalse);
    });

    test('a new choice applies at once and is saved', () async {
      final store = InMemoryGlassEffectsStore();
      final container = containerWith(store);

      await container.read(glassEffectsProvider.notifier).set(false);

      expect(container.read(glassEffectsProvider), isFalse);
      expect(await store.load(), isFalse);
    });

    testWidgets('turn solid when off, or when the platform reduces motion', (
      tester,
    ) async {
      Future<bool> glassFor({
        required bool setting,
        bool disableAnimations = false,
        bool highContrast = false,
      }) async {
        late bool glass;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              disableAnimations: disableAnimations,
              highContrast: highContrast,
            ),
            child: WeCordAppearance(
              glassEffects: setting,
              child: Builder(
                builder: (context) {
                  glass = WeCordAppearance.glassOf(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
        return glass;
      }

      expect(await glassFor(setting: true), isTrue);
      expect(await glassFor(setting: false), isFalse);
      expect(await glassFor(setting: true, disableAnimations: true), isFalse);
      expect(await glassFor(setting: true, highContrast: true), isFalse);
    });
  });
}
