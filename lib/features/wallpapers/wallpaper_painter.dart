import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:wecord/features/wallpapers/wallpaper_presets.dart';

/// Draws a built-in wallpaper: the base gradient, soft blobs, a quiet
/// pattern and paper grain. It paints once into a repaint boundary and only
/// again when the size or the tone changes.
class WallpaperPainter extends CustomPainter {
  WallpaperPainter({required this.preset, required this.brightness})
    : tone = preset.toneFor(brightness);

  final WallpaperPreset preset;
  final Brightness brightness;
  final WallpaperTone tone;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final rect = Offset.zero & size;
    final colors = tone.colors;
    final base = Paint();
    if (colors.length == 1) {
      base.color = colors.first;
    } else {
      base.shader = LinearGradient(
        begin: preset.begin,
        end: preset.end,
        colors: colors,
      ).createShader(rect);
    }
    canvas.drawRect(rect, base);

    final longSide = math.max(size.width, size.height);
    for (final blob in tone.blobs) {
      final center = blob.center.alongSize(size);
      final radius = blob.radius * longSide;
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [
            blob.color.withValues(alpha: blob.alpha),
            blob.color.withValues(alpha: 0),
          ],
          const [0, 1],
        );
      canvas.drawRect(rect, paint);
    }

    switch (tone.pattern) {
      case WallpaperPattern.none:
        break;
      case WallpaperPattern.dots:
        _paintDots(canvas, size);
      case WallpaperPattern.grid:
        _paintGrid(canvas, size);
    }

    final strength = tone.grain;
    if (strength > 0) {
      final tile = _grainTile(brightness);
      if (tile != null) {
        final paint = Paint()
          ..shader = ImageShader(
            tile,
            TileMode.repeated,
            TileMode.repeated,
            // The tile is 128 pixels; shown at half size the grain is about
            // a pixel on a 2x screen.
            Float64List.fromList(
              (Matrix4.identity()..scaleByDouble(0.5, 0.5, 1, 1)).storage,
            ),
          )
          ..color = Colors.white.withValues(alpha: strength.clamp(0, 1));
        canvas.drawRect(rect, paint);
      }
    }
  }

  void _paintDots(Canvas canvas, Size size) {
    const spacing = 22.0;
    final paint = Paint()
      ..color = tone.patternColor.withValues(alpha: tone.patternAlpha)
      ..isAntiAlias = true;
    final points = <Offset>[];
    var row = 0;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      final shift = row.isOdd ? spacing / 2 : 0.0;
      for (var x = spacing / 2 + shift; x < size.width; x += spacing) {
        points.add(Offset(x, y));
      }
      row++;
    }
    paint
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  void _paintGrid(Canvas canvas, Size size) {
    const spacing = 34.0;
    final paint = Paint()
      ..color = tone.patternColor.withValues(alpha: tone.patternAlpha)
      ..strokeWidth = 0.8
      ..isAntiAlias = true;
    for (var x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(WallpaperPainter oldPainter) =>
      oldPainter.preset.id != preset.id || oldPainter.brightness != brightness;
}

final _grainTiles = <Brightness, ui.Image?>{};

/// A 128 pixel tile of fine speckles (dark on light wallpapers, light on
/// dark ones), made once per theme. Null when the platform cannot draw one
/// synchronously; the wallpaper is then simply smooth.
ui.Image? _grainTile(Brightness brightness) {
  if (_grainTiles.containsKey(brightness)) {
    return _grainTiles[brightness];
  }
  ui.Image? tile;
  try {
    const side = 128;
    final random = math.Random(0x57ECD);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final speck = brightness == Brightness.dark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF3A3328);
    final alphaMax = brightness == Brightness.dark ? 0.055 : 0.07;
    final paint = Paint();
    for (var i = 0; i < 2600; i++) {
      paint.color = speck.withValues(alpha: random.nextDouble() * alphaMax);
      canvas.drawRect(
        Rect.fromLTWH(
          random.nextInt(side).toDouble(),
          random.nextInt(side).toDouble(),
          1,
          1,
        ),
        paint,
      );
    }
    final picture = recorder.endRecording();
    tile = picture.toImageSync(side, side);
    picture.dispose();
  } on Object {
    tile = null;
  }
  _grainTiles[brightness] = tile;
  return tile;
}
