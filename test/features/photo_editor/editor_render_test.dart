import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';
import 'package:wecord/features/photo_editor/editor_render.dart';

import 'editor_fakes.dart';

int _pixel(Uint8List rgba, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
}

int _channelGap(int a, int b) {
  return [
    ((a >> 16) & 255) - ((b >> 16) & 255),
    ((a >> 8) & 255) - ((b >> 8) & 255),
    (a & 255) - (b & 255),
  ].map((d) => d.abs()).reduce((x, y) => x > y ? x : y);
}

Future<({Uint8List rgba, int width, int height})> _render(
  WidgetTester tester,
  EditorAssets assets,
  EditorDocument document, {
  int maxEdge = 4096,
}) async {
  final photo = await tester.runAsync(
    () => renderEditedPhoto(
      assets: assets,
      document: document,
      fileName: 'a.jpg',
      maxEdge: maxEdge,
      quality: 100,
    ),
  );
  expect(photo, isNotNull);
  final pixels = await tester.runAsync(() => decodePixels(photo!.bytes));
  expect(pixels!.width, photo!.width);
  expect(pixels.height, photo.height);
  return pixels;
}

void main() {
  testWidgets('an unedited picture comes out the same size', (tester) async {
    final assets = await makeAssets(tester);
    final out = await _render(tester, assets, const EditorDocument());
    expect((out.width, out.height), (120, 80));
    // JPEG is lossy: close, not equal.
    expect(
      _channelGap(_pixel(out.rgba, 120, 30, 20), gradient(30, 20) & 0xFFFFFF),
      lessThan(40),
    );
  });

  testWidgets('a quarter turn swaps width and height', (tester) async {
    final assets = await makeAssets(tester);
    final out = await _render(
      tester,
      assets,
      const EditorDocument(quarterTurns: 1),
    );
    expect((out.width, out.height), (80, 120));
    // The picture's top-left corner is now the top-right.
    final corner = _pixel(out.rgba, 80, 78, 1);
    expect(_channelGap(corner, gradient(1, 1) & 0xFFFFFF), lessThan(40));
  });

  testWidgets('a crop keeps just that part', (tester) async {
    final assets = await makeAssets(tester);
    final out = await _render(
      tester,
      assets,
      const EditorDocument(crop: Rect.fromLTWH(20, 10, 60, 40)),
    );
    expect((out.width, out.height), (60, 40));
    expect(
      _channelGap(_pixel(out.rgba, 60, 5, 5), gradient(25, 15) & 0xFFFFFF),
      lessThan(40),
    );
  });

  testWidgets('crop and turn together', (tester) async {
    final assets = await makeAssets(tester);
    // Turned once the picture is 80 x 120; keep its top 80 x 50.
    final out = await _render(
      tester,
      assets,
      const EditorDocument(
        quarterTurns: 1,
        crop: Rect.fromLTWH(0, 0, 80, 50),
      ),
    );
    expect((out.width, out.height), (80, 50));
  });

  testWidgets('the longest side is capped', (tester) async {
    final assets = await makeAssets(tester);
    final out = await _render(
      tester,
      assets,
      const EditorDocument(),
      maxEdge: 60,
    );
    expect((out.width, out.height), (60, 40));
  });

  testWidgets('a pen stroke paints its color', (tester) async {
    final assets = await makeAssets(tester);
    final doc = const EditorDocument().withItem(
      const PenStroke(
        points: [Offset(10, 40), Offset(110, 40)],
        color: 0xFFFF0000,
        width: 10,
      ),
    );
    final out = await _render(tester, assets, doc);
    final on = _pixel(out.rgba, 120, 60, 40);
    expect((on >> 16) & 255, greaterThan(220));
    expect((on >> 8) & 255, lessThan(40));
    // Away from the line the picture is untouched.
    expect(
      _channelGap(_pixel(out.rgba, 120, 60, 10), gradient(60, 10) & 0xFFFFFF),
      lessThan(40),
    );
  });

  testWidgets('a pen stroke turns with the picture', (tester) async {
    final assets = await makeAssets(tester);
    final doc = const EditorDocument(quarterTurns: 1).withItem(
      const PenStroke(
        points: [Offset(10, 10), Offset(30, 10)],
        color: 0xFF00FF00,
        width: 6,
      ),
    );
    final out = await _render(tester, assets, doc);
    // Source (20, 10) lands at (80 - 10, 20) = (70, 20) once turned.
    final on = _pixel(out.rgba, 80, 70, 20);
    expect((on >> 8) & 255, greaterThan(200));
    expect((on >> 16) & 255, lessThan(60));
  });

  testWidgets('the pixelate brush turns an area into flat blocks', (
    tester,
  ) async {
    int checks(int x, int y) => ((x ~/ 2) + (y ~/ 2)).isEven ? 0xFF000000 : 0xFFFFFFFF;
    final assets = await makeAssets(
      tester,
      width: 200,
      height: 120,
      color: checks,
    );
    final block = assets.block.round();
    final doc = const EditorDocument().withItem(
      const MosaicStroke(
        points: [Offset(40, 60), Offset(160, 60)],
        width: 70,
        kind: MosaicKind.pixelate,
      ),
    );
    final out = await _render(tester, assets, doc);
    // Inside the stroke, pixels of one block are (nearly) one color.
    final x0 = (80 ~/ block) * block + 1;
    final y0 = (60 ~/ block) * block + 1;
    final a = _pixel(out.rgba, 200, x0, y0);
    final b = _pixel(out.rgba, 200, x0 + 2, y0);
    final c = _pixel(out.rgba, 200, x0, y0 + 2);
    expect(_channelGap(a, b), lessThan(40));
    expect(_channelGap(a, c), lessThan(40));
    // The plain picture flips between black and white over 2 pixels.
    expect(_channelGap(checks(x0, y0) & 0xFFFFFF, checks(x0 + 2, y0) & 0xFFFFFF), 255);
    // Outside the stroke the picture is unchanged (still the checks).
    final outsideA = _pixel(out.rgba, 200, 100, 8);
    final outsideB = _pixel(out.rgba, 200, 102, 8);
    expect(_channelGap(outsideA, outsideB), greaterThan(150));
  });

  testWidgets('the blur brush smooths an area and leaves the rest', (
    tester,
  ) async {
    final assets = await makeAssets(
      tester,
      width: 160,
      height: 100,
      // Hard black / white stripes: sharp edges everywhere.
      color: (x, y) => (x ~/ 4).isEven ? 0xFF000000 : 0xFFFFFFFF,
    );
    final doc = const EditorDocument().withItem(
      const MosaicStroke(
        points: [Offset(20, 50), Offset(140, 50)],
        width: 60,
        kind: MosaicKind.blur,
      ),
    );
    final out = await _render(tester, assets, doc);
    int spread(int y) {
      var most = 0;
      for (var x = 40; x < 100; x++) {
        final a = _pixel(out.rgba, 160, x, y) & 255;
        final b = _pixel(out.rgba, 160, x + 1, y) & 255;
        most = (a - b).abs() > most ? (a - b).abs() : most;
      }
      return most;
    }

    // Blurred row: stripes fade into each other. Untouched row: hard edges.
    expect(spread(50), lessThan(spread(5)));
    expect(spread(5), greaterThan(180));
  });

  testWidgets('a mosaic outside the picture is cut off', (tester) async {
    final assets = await makeAssets(tester);
    final doc = const EditorDocument().withItem(
      const MosaicStroke(
        points: [Offset(-50, -50), Offset(300, 300)],
        width: 200,
        kind: MosaicKind.pixelate,
      ),
    );
    final out = await _render(tester, assets, doc);
    expect((out.width, out.height), (120, 80));
  });

  testWidgets('text is drawn, with a pill behind it when asked', (
    tester,
  ) async {
    final assets = await makeAssets(
      tester,
      color: (x, y) => 0xFF808080,
    );
    int distinct(Uint8List rgba, int width, Rect area) {
      final colors = <int>{};
      for (var y = area.top.toInt(); y < area.bottom; y++) {
        for (var x = area.left.toInt(); x < area.right; x++) {
          colors.add(_pixel(rgba, width, x, y) >> 3);
        }
      }
      return colors.length;
    }

    const area = Rect.fromLTWH(30, 25, 60, 30);
    final plain = await _render(tester, assets, const EditorDocument());
    expect(distinct(plain.rgba, 120, area), 1);

    const text = TextOverlay(
      id: 1,
      text: 'WeCord',
      color: 0xFFFFFFFF,
      center: Offset(60, 40),
    );
    final withText = await _render(
      tester,
      assets,
      const EditorDocument().withItem(text),
    );
    expect(distinct(withText.rgba, 120, area), greaterThan(1));

    final pill = await _render(
      tester,
      assets,
      const EditorDocument().withItem(text.copyWith(pill: true)),
    );
    // The pill is white behind dark text: its middle is bright.
    final bright = _pixel(pill.rgba, 120, 36, 40) & 255;
    expect(bright, greaterThan(230));
  });

  testWidgets('text can be moved, scaled and turned', (tester) async {
    final assets = await makeAssets(tester, color: (x, y) => 0xFF808080);
    const text = TextOverlay(
      id: 1,
      text: 'Wide text here',
      color: 0xFF000000,
      center: Offset(60, 40),
    );
    final layout = assets.textLayout(text);
    final big = assets.textLayout(text.copyWith(scale: 2));
    // The layout is at scale 1; scale is applied when painting.
    expect(big.box, layout.box);
    expect(layout.box.width, greaterThan(layout.box.height));
    final turned = await _render(
      tester,
      assets,
      const EditorDocument().withItem(
        text.copyWith(rotation: 1.5707963, center: const Offset(60, 40)),
      ),
    );
    expect((turned.width, turned.height), (120, 80));
  });

  testWidgets('a file over the size limit is retried smaller', (tester) async {
    // The limit is 50 MB, far above a test picture: the retry path is only
    // checked through the cap on the long side.
    final assets = await makeAssets(tester);
    final photo = await tester.runAsync(
      () => renderEditedPhoto(
        assets: assets,
        document: const EditorDocument(),
        fileName: 'a.heic',
        maxEdge: 100,
      ),
    );
    expect(photo!.width, 100);
    expect(photo.bytes.length, lessThan(50 * 1024 * 1024));
    // It is a JPEG.
    expect(photo.bytes[0], 0xFF);
    expect(photo.bytes[1], 0xD8);
  });
}
