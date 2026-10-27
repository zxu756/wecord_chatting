import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:wecord/features/whiteboard/whiteboard_geometry.dart';
import 'package:wecord/features/whiteboard/whiteboard_images.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_painter.dart';

/// The longest side of an exported picture, in pixels.
const whiteboardExportMaxSide = 4096;

/// What an export needs to know about the picture it makes.
class WhiteboardRender {
  const WhiteboardRender({
    required this.width,
    required this.height,
    required this.scale,
    required this.origin,
  });

  final int width;
  final int height;

  /// Pixels per board unit.
  final double scale;

  /// The board point at the top left corner.
  final Offset origin;
}

/// How big the picture of [elements] is, and where it sits. Null when there
/// is nothing to draw.
WhiteboardRender? planWhiteboardRender(
  Iterable<WhiteboardElement> elements, {
  double padding = 40,
  int maxSide = whiteboardExportMaxSide,
  double pixelRatio = 2,
}) {
  final bounds = unionBounds(elements);
  if (bounds == null) {
    return null;
  }
  final area = bounds.inflate(padding);
  var scale = pixelRatio;
  final longest = math.max(area.width, area.height);
  if (longest * scale > maxSide) {
    scale = maxSide / longest;
  }
  return WhiteboardRender(
    width: math.max(1, (area.width * scale).ceil()),
    height: math.max(1, (area.height * scale).ceil()),
    scale: scale,
    origin: area.topLeft,
  );
}

/// The board as a PNG: everything on it, on a plain background, in drawing
/// order. Pictures are fetched first so none is left a gray box. Returns null
/// for an empty board.
Future<Uint8List?> renderWhiteboardPng(
  List<WhiteboardElement> elements,
  WhiteboardImageStore images, {
  Color background = const Color(0xFFFFFFFF),
}) async {
  final plan = planWhiteboardRender(elements);
  if (plan == null) {
    return null;
  }
  await images.preload([
    for (final e in elements)
      if (e.kind == WhiteboardKind.image) e.path,
  ]);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, plan.width.toDouble(), plan.height.toDouble()),
    Paint()..color = background,
  );
  canvas.scale(plan.scale);
  canvas.translate(-plan.origin.dx, -plan.origin.dy);
  for (final element in elements) {
    paintWhiteboardElement(canvas, element, images: images, scale: plan.scale);
  }
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(plan.width, plan.height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
