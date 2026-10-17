import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/wallpapers/wallpaper_backdrop.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';
import 'package:wecord/features/wallpapers/wallpaper_presets.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// How far apart two opaque colors are on a light/dark scale (WCAG ratio).
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

List<double> _lab(Color color) {
  final r = _linear(color.r);
  final g = _linear(color.g);
  final b = _linear(color.b);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

/// How different two colors look (CIE76 delta E; about 2 is the smallest
/// difference an eye notices, 10 reads as clearly another color). Unlike
/// the contrast ratio it also sees a change of hue at the same lightness.
double colorDistance(Color a, Color b) {
  final p = _lab(a);
  final q = _lab(b);
  return math.sqrt(
    math.pow(p[0] - q[0], 2) +
        math.pow(p[1] - q[1], 2) +
        math.pow(p[2] - q[2], 2),
  );
}

/// The least a wallpaper may differ from any surface it meets, as a contrast
/// ratio and as a color distance. A new preset that comes closer fails.
const minSurfaceContrast = 1.2;
const minSurfaceDistance = 9.0;

/// Everything a wallpaper sits next to, under or behind, by name.
Map<String, Color> surfacesNextToWallpaper(WeCordTokens tokens) {
  final c = tokens.colors;
  return {
    'their bubble': WallpaperSurfaces.incomingBubble(tokens),
    'my bubble': WallpaperSurfaces.outgoingBubble(tokens),
    'bubble fill (raised)': c.raised,
    'paper': c.paper,
    'rail': c.rail,
    'sidebar': c.sidebar,
    'panel': c.panel,
    'raisedStrong': c.raisedStrong,
    'well': c.well,
    'glass (header, composer)': tokens.glass.solidFill,
    'glass over panel': Color.alphaBlend(tokens.glass.fill, c.panel),
    'accent': c.accent,
    'accentSoft': c.accentSoft,
    'onInk': c.onInk,
  };
}

void main() {
  final themes = {'light': WeCordTokens.light, 'dark': WeCordTokens.dark};

  test('there are 8 to 12 built-in wallpapers with unique, storable ids', () {
    expect(wallpaperPresets.length, inInclusiveRange(8, 12));
    final ids = wallpaperPresets.map((preset) => preset.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      // The same rule as the check constraint in the migration.
      expect(id, matches(RegExp(r'^[a-z0-9-]{1,40}$')));
    }
    expect(wallpaperPresetById('dawn'), isNotNull);
    expect(wallpaperPresetById('from-the-future'), isNull);
  });

  for (final MapEntry(key: themeName, value: tokens) in themes.entries) {
    group('$themeName wallpapers', () {
      final surfaces = surfacesNextToWallpaper(tokens);

      for (final preset in wallpaperPresets) {
        final tone = preset.toneFor(tokens.brightness);

        test('${preset.id} stands clear of bubbles, surfaces and accent', () {
          for (final sample in tone.samples) {
            for (final MapEntry(key: name, value: surface)
                in surfaces.entries) {
              expect(
                contrast(sample, surface),
                greaterThanOrEqualTo(minSurfaceContrast),
                reason:
                    '${preset.id} $themeName $sample is too close to $name '
                    '(contrast ${contrast(sample, surface).toStringAsFixed(2)})',
              );
              expect(
                colorDistance(sample, surface),
                greaterThanOrEqualTo(minSurfaceDistance),
                reason:
                    '${preset.id} $themeName $sample looks too much like $name '
                    '(distance ${colorDistance(sample, surface).toStringAsFixed(1)})',
              );
            }
          }
        });

        test(
          '${preset.id} is calm: soft blobs, quiet pattern, gentle fade',
          () {
            final base = tone.base;
            for (final sample in tone.samples) {
              expect(
                contrast(sample, base),
                lessThanOrEqualTo(1.2),
                reason: '${preset.id} $themeName has a stop far from its base',
              );
            }
            final mark = tone.patternSample;
            if (mark != null) {
              // Dots and lines are felt, not seen: far weaker than text.
              expect(contrast(mark, base), greaterThan(1.02));
              expect(
                contrast(mark, base),
                lessThanOrEqualTo(1.25),
                reason: '${preset.id} $themeName pattern is too strong',
              );
              expect(tone.patternAlpha, lessThanOrEqualTo(0.3));
            }
            for (final blob in tone.blobs) {
              expect(blob.alpha, lessThanOrEqualTo(0.9));
            }
            expect(tone.grain, inInclusiveRange(0, 1));
          },
        );

        test('${preset.id} keeps ink and the small pills readable', () {
          final pill = Color.alphaBlend(
            WallpaperSurfaces.pill(tokens),
            tone.base,
          );
          for (final sample in tone.samples) {
            expect(contrast(tokens.colors.ink, sample), greaterThan(7));
            // A pill (a date, the typing line) stands out from the picture.
            expect(
              contrast(pill, sample),
              greaterThanOrEqualTo(1.15),
              reason: '${preset.id} $themeName pill blends in',
            );
          }
          final onPill = Color.alphaBlend(
            WallpaperSurfaces.pill(tokens),
            tokens.colors.panel,
          );
          expect(contrast(tokens.colors.muted, onPill), greaterThan(4.5));
        });
      }
    });
  }

  test('both themes cover every preset (light and dark variants)', () {
    for (final preset in wallpaperPresets) {
      expect(preset.light.colors, isNotEmpty);
      expect(preset.dark.colors, isNotEmpty);
      expect(
        preset.light.base.computeLuminance(),
        greaterThan(preset.dark.base.computeLuminance()),
        reason: '${preset.id} light is lighter than dark',
      );
    }
  });

  group('bubbles over any wallpaper', () {
    for (final MapEntry(key: themeName, value: tokens) in themes.entries) {
      test('$themeName bubbles are solid', () {
        expect(WallpaperSurfaces.incomingBubble(tokens).a, 1);
        expect(WallpaperSurfaces.outgoingBubble(tokens).a, 1);
      });
    }

    Color over(Color photo, Color scrim) => Color.alphaBlend(scrim, photo);

    test('light: the veil keeps every gray photo clear of both bubbles', () {
      final scrim = wallpaperPhotoScrim(Brightness.light, defaultPhotoDim);
      final their = WallpaperSurfaces.incomingBubble(WeCordTokens.light);
      final mine = WallpaperSurfaces.outgoingBubble(WeCordTokens.light);
      for (var level = 0; level <= 255; level += 5) {
        final photo = Color.fromARGB(255, level, level, level);
        final shown = over(photo, scrim);
        expect(
          contrast(shown, their),
          greaterThanOrEqualTo(minSurfaceContrast),
          reason: 'photo gray $level against their bubble',
        );
        expect(
          contrast(shown, mine),
          greaterThanOrEqualTo(minSurfaceContrast),
          reason: 'photo gray $level against my bubble',
        );
      }
    });

    test('light: saturated photos stay clear too', () {
      final scrim = wallpaperPhotoScrim(Brightness.light, defaultPhotoDim);
      final their = WallpaperSurfaces.incomingBubble(WeCordTokens.light);
      final mine = WallpaperSurfaces.outgoingBubble(WeCordTokens.light);
      for (final photo in const [
        Color(0xFFFFFF00),
        Color(0xFFFFFFFF),
        Color(0xFF000000),
        Color(0xFF0000FF),
        Color(0xFF001A00),
      ]) {
        final shown = over(photo, scrim);
        expect(contrast(shown, their), greaterThanOrEqualTo(1.15));
        expect(contrast(shown, mine), greaterThanOrEqualTo(1.2));
      }
    });

    test('dark: never less than the minimum dim, however low the slider', () {
      expect(
        wallpaperPhotoScrim(Brightness.dark, 0).a,
        closeTo(minPhotoDim, 0.001),
      );
      expect(
        wallpaperPhotoScrim(Brightness.dark, 5).a,
        closeTo(maxPhotoDim, 0.001),
      );
    });

    test('dark: black and white photos at every dim keep their distance', () {
      final their = WallpaperSurfaces.incomingBubble(WeCordTokens.dark);
      final mine = WallpaperSurfaces.outgoingBubble(WeCordTokens.dark);
      for (final dim in [minPhotoDim, defaultPhotoDim, 0.6, maxPhotoDim]) {
        final scrim = wallpaperPhotoScrim(Brightness.dark, dim);
        final white = over(Colors.white, scrim);
        final black = over(Colors.black, scrim);
        expect(contrast(white, their), greaterThanOrEqualTo(1.5));
        expect(contrast(white, mine), greaterThanOrEqualTo(1.2));
        expect(contrast(black, their), greaterThanOrEqualTo(1.2));
        expect(contrast(black, mine), greaterThanOrEqualTo(10));
      }
    });
  });
}
