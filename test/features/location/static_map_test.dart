import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/location/map_config.dart';
import 'package:wecord/features/location/static_map.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'location_fakes.dart';

/// Asks FakeTileProvider for pictures and writes down the URL it would have
/// fetched for each.
class _RecordingTiles extends FakeTileProvider {
  final urls = <String>[];

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    urls.add(getTileUrl(coordinates, options));
    return super.getImage(coordinates, options);
  }
}

const _example = MapConfig(
  tileUrl: 'https://tiles.example.test/{z}/{x}/{y}.png?key=abc',
  attribution: '© Example Maps',
  attributionUrl: 'https://maps.example.test/copyright',
);

Widget _app(
  _RecordingTiles tiles, {
  MapConfig config = _example,
  ThemeData? theme,
  LatLng center = westminster,
}) {
  return ProviderScope(
    overrides: [
      mapTileProviderProvider.overrideWithValue(tiles),
      mapConfigProvider.overrideWithValue(config),
    ],
    child: MaterialApp(
      theme: theme ?? WeCordTheme.light(),
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: const ValueKey('shot'),
            child: StaticMap(center: center, width: 248, height: 134),
          ),
        ),
      ),
    ),
  );
}

Future<ByteData> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    return image.toByteData(format: ui.ImageByteFormat.rawRgba);
  }))!;
}

void main() {
  testWidgets('draws a few tiles from the configured server, not a live map', (
    tester,
  ) async {
    final tiles = _RecordingTiles();
    await tester.pumpWidget(_app(tiles));
    await settleMaps(tester);

    expect(find.byType(FlutterMap), findsNothing);
    expect(find.byType(TileLayer), findsNothing);
    // 248 x 134 at zoom 15.5 needs a handful of tiles, never a screenful.
    expect(tiles.urls, isNotEmpty);
    expect(tiles.urls.length, lessThanOrEqualTo(6));
    for (final url in tiles.urls) {
      expect(
        url,
        matches(r'^https://tiles\.example\.test/16/\d+/\d+\.png\?key=abc$'),
      );
    }
    // The tile that holds the place (Westminster at zoom 16: x 32745, y 21793) is among them.
    expect(
      tiles.urls,
      contains('https://tiles.example.test/16/32745/21793.png?key=abc'),
    );
    // Drawn once: more frames do not ask for them again.
    final asked = tiles.urls.length;
    await tester.pump(const Duration(seconds: 1));
    expect(tiles.urls.length, asked);
  });

  testWidgets('the required credit stays on the picture', (tester) async {
    await tester.pumpWidget(_app(_RecordingTiles()));
    await settleMaps(tester);
    expect(find.text('© Example Maps'), findsOneWidget);
    expect(find.byKey(const ValueKey('map-attribution')), findsOneWidget);
  });

  testWidgets('paints the tiles under the pin', (tester) async {
    await tester.pumpWidget(_app(_RecordingTiles()));
    await settleMaps(tester);
    final data = await _pixels(tester);
    // The fake tiles are pale (a street plan on 238, 234, 224); the plain
    // background colour behind a tile that has not arrived is darker.
    expect(
      data.getUint8(0) + data.getUint8(1) + data.getUint8(2),
      greaterThan(650),
    );
    // More than one colour appears: streets, parks and water.
    final colours = <int>{};
    for (var i = 0; i + 4 <= data.lengthInBytes; i += 4 * 97) {
      colours.add(data.getUint32(i));
    }
    expect(colours.length, greaterThan(2));
  });

  testWidgets('dark mode draws the tiles inverted', (tester) async {
    await tester.pumpWidget(_app(_RecordingTiles()));
    await settleMaps(tester);
    final light = await _pixels(tester);

    await tester.pumpWidget(_app(_RecordingTiles(), theme: WeCordTheme.dark()));
    await settleMaps(tester);
    final dark = await _pixels(tester);
    expect(
      dark.getUint8(0) + dark.getUint8(1) + dark.getUint8(2),
      lessThan(light.getUint8(0) + light.getUint8(1) + light.getUint8(2)),
    );
  });

  testWidgets('a new place or tile server loads the new tiles', (tester) async {
    final tiles = _RecordingTiles();
    await tester.pumpWidget(_app(tiles));
    await settleMaps(tester);
    final first = tiles.urls.length;
    await tester.pumpWidget(_app(tiles, center: const LatLng(48.8584, 2.2945)));
    await settleMaps(tester);
    expect(tiles.urls.length, greaterThan(first));
    await tester.pumpWidget(
      _app(
        tiles,
        config: const MapConfig(
          tileUrl: 'https://other.example.test/{z}/{x}/{y}.png',
        ),
        center: const LatLng(48.8584, 2.2945),
      ),
    );
    await settleMaps(tester);
    expect(tiles.urls.last, startsWith('https://other.example.test/'));
  });

  testWidgets('wraps around the date line and stays on the map at the poles', (
    tester,
  ) async {
    final tiles = _RecordingTiles();
    await tester.pumpWidget(_app(tiles, center: const LatLng(0, 179.9999)));
    await settleMaps(tester);
    expect(tiles.urls, isNotEmpty);
    for (final url in tiles.urls) {
      final x = int.parse(RegExp(r'/16/(\d+)/').firstMatch(url)!.group(1)!);
      expect(x, inInclusiveRange(0, 65535));
    }
    final pole = _RecordingTiles();
    await tester.pumpWidget(_app(pole, center: const LatLng(89, 0)));
    await settleMaps(tester);
    for (final url in pole.urls) {
      final y = int.parse(
        RegExp(r'/16/\d+/(\d+)\.').firstMatch(url)!.group(1)!,
      );
      expect(y, inInclusiveRange(0, 65535));
    }
  });
}
