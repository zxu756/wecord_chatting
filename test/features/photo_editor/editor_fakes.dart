import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/photo_editor/editor_render.dart';

/// A picture of [width] x [height] whose pixel at (x, y) is [color].
Future<ui.Image> makeImage(
  int width,
  int height,
  int Function(int x, int y) color,
) {
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final argb = color(x, y);
      final i = (y * width + x) * 4;
      pixels[i] = (argb >> 16) & 255;
      pixels[i + 1] = (argb >> 8) & 255;
      pixels[i + 2] = argb & 255;
      pixels[i + 3] = (argb >> 24) & 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Colors that change at every pixel, so a mosaic or a blur shows.
int gradient(int x, int y) {
  final r = (x * 5) % 256;
  final g = (y * 7) % 256;
  final b = ((x + y) * 3) % 256;
  return 0xFF000000 | (r << 16) | (g << 8) | b;
}

/// Editor assets for a [width] x [height] test picture.
Future<EditorAssets> makeAssets(
  WidgetTester tester, {
  int width = 120,
  int height = 80,
  int Function(int x, int y) color = gradient,
}) async {
  final assets = await tester.runAsync(() async {
    final image = await makeImage(width, height, color);
    return EditorAssets.fromImage(image);
  });
  return assets!;
}

/// The RGBA pixels of an encoded picture.
Future<({Uint8List rgba, int width, int height})> decodePixels(
  Uint8List bytes,
) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = (
    rgba: data!.buffer.asUint8List(),
    width: image.width,
    height: image.height,
  );
  image.dispose();
  codec.dispose();
  return result;
}
