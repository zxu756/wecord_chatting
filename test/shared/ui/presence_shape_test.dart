import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

const _dot = Color(0xFF2E9D67);
const _ring = Color(0xFFFFFFFF);
const _size = 40.0;

/// The pixel at ([x], [y]) of a [shape] dot, 40 wide.
Future<Color> _pixel(
  WidgetTester tester,
  PresenceShape shape,
  int x,
  int y,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: WeCordTheme.light(),
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: PresenceDot(
            color: _dot,
            size: _size,
            ringWidth: 4,
            ringColor: _ring,
            shape: shape,
          ),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final offset = (y * image.width + x) * 4;
    final color = Color.fromARGB(
      data.getUint8(offset + 3),
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
    image.dispose();
    return color;
  }))!;
}

bool _is(Color actual, Color expected) =>
    (actual.r - expected.r).abs() < 0.05 &&
    (actual.g - expected.g).abs() < 0.05 &&
    (actual.b - expected.b).abs() < 0.05;

void main() {
  testWidgets('a solid dot is one color all through', (tester) async {
    expect(
      _is(await _pixel(tester, PresenceShape.solid, 20, 20), _dot),
      isTrue,
    );
    expect(
      _is(await _pixel(tester, PresenceShape.solid, 14, 14), _dot),
      isTrue,
    );
  });

  testWidgets('idle is a crescent: a bite out of the top left', (tester) async {
    expect(
      _is(await _pixel(tester, PresenceShape.crescent, 14, 14), _ring),
      isTrue,
    );
    // The rest of the dot is still the status color.
    expect(
      _is(await _pixel(tester, PresenceShape.crescent, 30, 30), _dot),
      isTrue,
    );
  });

  testWidgets('do not disturb is a bar across the middle', (tester) async {
    expect(_is(await _pixel(tester, PresenceShape.bar, 20, 20), _ring), isTrue);
    expect(_is(await _pixel(tester, PresenceShape.bar, 20, 12), _dot), isTrue);
  });

  testWidgets('offline is a hollow ring', (tester) async {
    expect(
      _is(await _pixel(tester, PresenceShape.ring, 20, 20), _ring),
      isTrue,
    );
    expect(_is(await _pixel(tester, PresenceShape.ring, 30, 30), _dot), isTrue);
  });

  test('each status has its own shape, and offline reads as offline', () {
    expect(presenceShapeOf(PresenceStatus.online), PresenceShape.solid);
    expect(presenceShapeOf(PresenceStatus.idle), PresenceShape.crescent);
    expect(presenceShapeOf(PresenceStatus.doNotDisturb), PresenceShape.bar);
    expect(presenceShapeOf(PresenceStatus.invisible), PresenceShape.ring);
    expect(presenceShapeOf(null), PresenceShape.ring);
    expect(presenceLabelOf(null), 'Offline');
    expect(presenceLabelOf(PresenceStatus.invisible), 'Offline');
    expect(presenceLabelOf(PresenceStatus.idle), 'Idle');
  });
}
