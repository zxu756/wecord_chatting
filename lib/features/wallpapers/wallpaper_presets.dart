import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// A quiet pattern laid over a wallpaper's colors.
enum WallpaperPattern { none, dots, grid }

/// A soft round glow of color over the base gradient.
@immutable
class WallpaperBlob {
  const WallpaperBlob({
    required this.center,
    required this.radius,
    required this.color,
    this.alpha = 0.7,
  });

  /// Where it sits in the picture (-1 to 1 on both axes).
  final Alignment center;

  /// Its reach as a fraction of the picture's longer side.
  final double radius;
  final Color color;

  /// How strong it is at its center.
  final double alpha;
}

/// One wallpaper in one theme.
///
/// The colors are deliberately muted and shifted away from every color the
/// chat is made of (bubbles, paper, panels, glass, the accent): in the light
/// theme they are mid-light dusty tones, in the dark theme deep tinted tones
/// that are a little lighter than the bubbles. `wallpaper_presets_test.dart`
/// checks every tone against the token colors, so a preset that comes close
/// to one fails there.
@immutable
class WallpaperTone {
  const WallpaperTone({
    required this.colors,
    this.blobs = const [],
    this.pattern = WallpaperPattern.none,
    this.patternColor = Colors.transparent,
    this.patternAlpha = 0,
    this.grain = 0,
  });

  /// The base gradient's colors, evenly spaced (one color is a flat tone).
  final List<Color> colors;
  final List<WallpaperBlob> blobs;
  final WallpaperPattern pattern;

  /// Dots and grid lines, drawn with [patternAlpha].
  final Color patternColor;
  final double patternAlpha;

  /// Strength of the paper grain, 0 (none) to 1.
  final double grain;

  /// The average of the base colors.
  Color get base {
    var red = 0.0, green = 0.0, blue = 0.0;
    for (final color in colors) {
      red += color.r;
      green += color.g;
      blue += color.b;
    }
    final n = colors.length;
    return Color.from(alpha: 1, red: red / n, green: green / n, blue: blue / n);
  }

  /// Every color a viewer can see at full strength: the gradient's colors,
  /// each blob at its center, and a pattern mark. What the contrast checks
  /// look at.
  List<Color> get samples => [
    ...colors,
    for (final blob in blobs)
      Color.alphaBlend(blob.color.withValues(alpha: blob.alpha), base),
  ];

  /// A dot or grid line on the base.
  Color? get patternSample => pattern == WallpaperPattern.none
      ? null
      : Color.alphaBlend(patternColor.withValues(alpha: patternAlpha), base);
}

/// A built-in wallpaper, drawn in code.
@immutable
class WallpaperPreset {
  const WallpaperPreset({
    required this.id,
    required this.label,
    required this.light,
    required this.dark,
    this.begin = Alignment.topCenter,
    this.end = Alignment.bottomCenter,
  });

  /// Stored in `chat_wallpapers.preset_id`; never changes.
  final String id;
  final String Function() label;
  final WallpaperTone light;
  final WallpaperTone dark;

  /// Direction of the base gradient.
  final Alignment begin;
  final Alignment end;

  WallpaperTone toneFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

Color _c(int value) => Color(0xFF000000 | value);

/// The wallpapers, in the order the picker shows them.
final List<WallpaperPreset> wallpaperPresets = List.unmodifiable([
  WallpaperPreset(
    id: 'grain',
    label: () => tr('Grain'),
    light: WallpaperTone(colors: [_c(0xD4CEBF)], grain: 1),
    dark: WallpaperTone(colors: [_c(0x45413B)], grain: 1),
  ),
  WallpaperPreset(
    id: 'sand',
    label: () => tr('Sand'),
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    light: WallpaperTone(colors: [_c(0xDCCFB6), _c(0xD6C7AB)], grain: 0.6),
    dark: WallpaperTone(colors: [_c(0x4A4337), _c(0x40392E)], grain: 0.6),
  ),
  WallpaperPreset(
    id: 'dawn',
    label: () => tr('Dawn'),
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    light: WallpaperTone(colors: [_c(0xE4C6B0), _c(0xDCBFC0)], grain: 0.4),
    dark: WallpaperTone(colors: [_c(0x4D3A38), _c(0x45353F)], grain: 0.4),
  ),
  WallpaperPreset(
    id: 'dusk',
    label: () => tr('Dusk'),
    light: WallpaperTone(colors: [_c(0xCDC5DA), _c(0xD9C2CB)], grain: 0.4),
    dark: WallpaperTone(colors: [_c(0x3D3850), _c(0x48384A)], grain: 0.4),
  ),
  WallpaperPreset(
    id: 'lagoon',
    label: () => tr('Lagoon'),
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    light: WallpaperTone(colors: [_c(0xBCD2CF), _c(0xC6D4DA)], grain: 0.4),
    dark: WallpaperTone(colors: [_c(0x2F4545), _c(0x2E4049)], grain: 0.4),
  ),
  WallpaperPreset(
    id: 'sage',
    label: () => tr('Sage'),
    light: WallpaperTone(colors: [_c(0xC4D1BC), _c(0xCED6C0)], grain: 0.5),
    dark: WallpaperTone(colors: [_c(0x3A4636), _c(0x353F33)], grain: 0.5),
  ),
  WallpaperPreset(
    id: 'mist',
    label: () => tr('Mist'),
    light: WallpaperTone(colors: [_c(0xC5CED9), _c(0xD0D5DD)], grain: 0.4),
    dark: WallpaperTone(colors: [_c(0x363E4C), _c(0x3B4150)], grain: 0.4),
  ),
  WallpaperPreset(
    id: 'clay',
    label: () => tr('Clay'),
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    light: WallpaperTone(colors: [_c(0xDBBDAC), _c(0xD4B7A8)], grain: 0.6),
    dark: WallpaperTone(colors: [_c(0x4E3C32), _c(0x4A382C)], grain: 0.6),
  ),
  WallpaperPreset(
    id: 'glow',
    label: () => tr('Glow'),
    light: WallpaperTone(
      colors: [_c(0xDCCDB8)],
      blobs: [
        WallpaperBlob(
          center: Alignment(-0.7, -0.8),
          radius: 0.8,
          color: _c(0xE8C3B0),
          alpha: 0.85,
        ),
        WallpaperBlob(
          center: Alignment(0.9, 0.7),
          radius: 0.85,
          color: _c(0xDDBDC4),
          alpha: 0.8,
        ),
      ],
      grain: 0.5,
    ),
    dark: WallpaperTone(
      colors: [_c(0x473F34)],
      blobs: [
        WallpaperBlob(
          center: Alignment(-0.7, -0.8),
          radius: 0.8,
          color: _c(0x553E36),
          alpha: 0.85,
        ),
        WallpaperBlob(
          center: Alignment(0.9, 0.7),
          radius: 0.85,
          color: _c(0x493A45),
          alpha: 0.8,
        ),
      ],
      grain: 0.5,
    ),
  ),
  WallpaperPreset(
    id: 'haze',
    label: () => tr('Haze'),
    light: WallpaperTone(
      colors: [_c(0xC6D1D3)],
      blobs: [
        WallpaperBlob(
          center: Alignment(0.8, -0.8),
          radius: 0.8,
          color: _c(0xB8D0CF),
          alpha: 0.85,
        ),
        WallpaperBlob(
          center: Alignment(-0.9, 0.8),
          radius: 0.85,
          color: _c(0xCAC3DA),
          alpha: 0.8,
        ),
      ],
      grain: 0.5,
    ),
    dark: WallpaperTone(
      colors: [_c(0x34424A)],
      blobs: [
        WallpaperBlob(
          center: Alignment(0.8, -0.8),
          radius: 0.8,
          color: _c(0x2D4647),
          alpha: 0.85,
        ),
        WallpaperBlob(
          center: Alignment(-0.9, 0.8),
          radius: 0.85,
          color: _c(0x3E3A52),
          alpha: 0.8,
        ),
      ],
      grain: 0.5,
    ),
  ),
  WallpaperPreset(
    id: 'dots',
    label: () => tr('Dots'),
    light: WallpaperTone(
      colors: [_c(0xD1CCC0)],
      pattern: WallpaperPattern.dots,
      patternColor: _c(0x8E8778),
      patternAlpha: 0.3,
    ),
    dark: WallpaperTone(
      colors: [_c(0x43403F)],
      pattern: WallpaperPattern.dots,
      patternColor: _c(0xCFC8BE),
      patternAlpha: 0.08,
    ),
  ),
  WallpaperPreset(
    id: 'grid',
    label: () => tr('Grid'),
    light: WallpaperTone(
      colors: [_c(0xCBD3CC)],
      pattern: WallpaperPattern.grid,
      patternColor: _c(0x7F8C82),
      patternAlpha: 0.2,
    ),
    dark: WallpaperTone(
      colors: [_c(0x33403A)],
      pattern: WallpaperPattern.grid,
      patternColor: _c(0xBBCBC1),
      patternAlpha: 0.1,
    ),
  ),
]);

/// The built-in wallpaper called [id]; null for an id this version does not
/// know (made by a newer version of the app).
WallpaperPreset? wallpaperPresetById(String? id) {
  for (final preset in wallpaperPresets) {
    if (preset.id == id) {
      return preset;
    }
  }
  return null;
}
