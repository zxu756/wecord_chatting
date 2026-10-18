import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/photo_editor/crop_math.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

/// The longest side the editor works at. Pictures bigger than this (a 48
/// megapixel photo) are decoded smaller; this still covers the 12 and 24
/// megapixel photos phones take at their full size.
const editorMaxEdge = 4096;

/// A picture opened for editing: the decoded pixels, and the pixelated and
/// blurred copies the mosaic brush shows through.
class EditorAssets {
  EditorAssets._(this.image, this.pixelated, this.blurred, this.block);

  /// The decoded picture, turned upright (the decoder applies the EXIF
  /// orientation).
  final ui.Image image;

  /// The picture shrunk to one pixel per mosaic block; drawn big without
  /// smoothing it becomes the mosaic.
  final ui.Image pixelated;

  /// The picture shrunk and blurred; drawn big with smoothing.
  final ui.Image blurred;

  /// The mosaic block size in source pixels.
  final double block;

  final _text = <String, TextLayout>{};

  Size get size => Size(image.width.toDouble(), image.height.toDouble());

  /// Decodes [bytes], at most [maxEdge] on the long side. Null when the
  /// picture cannot be decoded.
  static Future<EditorAssets?> decode(
    Uint8List bytes, {
    int maxEdge = editorMaxEdge,
  }) async {
    ui.Codec? codec;
    try {
      final size = await readPhotoSize(bytes);
      if (size == null || size.$1 <= 0 || size.$2 <= 0) {
        return null;
      }
      final landscape = size.$1 >= size.$2;
      final longest = landscape ? size.$1 : size.$2;
      final shrink = longest > maxEdge;
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: shrink && landscape ? maxEdge : null,
        targetHeight: shrink && !landscape ? maxEdge : null,
      );
      final image = (await codec.getNextFrame()).image;
      return await fromImage(image);
    } on Object {
      return null;
    } finally {
      codec?.dispose();
    }
  }

  /// Builds the assets for an already decoded [image] (which they own).
  static Future<EditorAssets> fromImage(ui.Image image) async {
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final block = mosaicBlockSize(size);
    final pixelated = await _shrink(image, 1 / block);
    final blurred = await _shrink(image, 1 / 4, blurSigma: 2.5);
    return EditorAssets._(image, pixelated, blurred, block);
  }

  static Future<ui.Image> _shrink(
    ui.Image source,
    double factor, {
    double? blurSigma,
  }) async {
    final width = math.max(1, (source.width * factor).ceil());
    final height = math.max(1, (source.height * factor).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
    if (blurSigma != null) {
      paint.imageFilter = ui.ImageFilter.blur(
        sigmaX: blurSigma,
        sigmaY: blurSigma,
        tileMode: ui.TileMode.clamp,
      );
    }
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      paint,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  /// The laid-out text of [item].
  TextLayout textLayout(TextOverlay item) {
    final key = '${item.text}|${item.color}|${item.pill}';
    final cached = _text[key];
    if (cached != null) {
      return cached;
    }
    if (_text.length > 64) {
      _text.clear();
    }
    return _text[key] = TextLayout.of(item, size);
  }

  void dispose() {
    image.dispose();
    pixelated.dispose();
    blurred.dispose();
  }
}

/// A text overlay laid out at scale 1.
class TextLayout {
  TextLayout._(
    this.painter,
    this.box,
    this.pillPadding,
    this.pillColor,
    this.radius,
  );

  factory TextLayout.of(TextOverlay item, Size source) {
    final fontSize = TextOverlayMetrics.baseFontSize(source);
    final color = Color(
      item.pill ? EditorPalette.onColor(item.color) : item.color,
    );
    final lightText = color.computeLuminance() > 0.45;
    final painter = TextPainter(
      text: TextSpan(
        text: item.text,
        style: TextStyle(
          fontFamily: WeCordTheme.fontFamily,
          fontFamilyFallback: WeCordTheme.fontFamilyFallback,
          fontSize: fontSize,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: color,
          shadows: item.pill
              ? null
              : [
                  Shadow(
                    blurRadius: fontSize * 0.12,
                    offset: Offset(0, fontSize * 0.04),
                    color: lightText
                        ? const Color(0x73000000)
                        : const Color(0x73FFFFFF),
                  ),
                ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: TextOverlayMetrics.maxLineWidth(source));
    final padding = item.pill
        ? EdgeInsets.symmetric(
            horizontal: fontSize * 0.6,
            vertical: fontSize * 0.28,
          )
        : EdgeInsets.zero;
    final box = Size(
      painter.width + padding.horizontal,
      painter.height + padding.vertical,
    );
    return TextLayout._(
      painter,
      box,
      padding,
      Color(item.color),
      math.min(box.height / 2, fontSize * 0.9),
    );
  }

  final TextPainter painter;

  /// The size of the text with its pill's padding.
  final Size box;
  final EdgeInsets pillPadding;
  final Color pillColor;

  /// The corner radius of the pill.
  final double radius;
}

/// Paints the picture with its marks into [canvas], in source space: the
/// canvas must already be set so that (0, 0) is the picture's top-left.
/// [active] is the stroke (or text) being drawn, [skipText] the id of a text
/// overlay of the document that is being edited and so is drawn as [active]
/// instead.
void paintEditorScene(
  ui.Canvas canvas,
  EditorAssets assets,
  EditorDocument document, {
  EditorItem? active,
  int? skipText,
}) {
  final size = assets.size;
  final bounds = ui.Rect.fromLTWH(0, 0, size.width, size.height);
  canvas.save();
  canvas.clipRect(bounds);
  canvas.drawImageRect(
    assets.image,
    bounds,
    bounds,
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  // A text being edited is shown by its draft (the [active] item), not by
  // its old self in the document.
  final items = [
    for (final item in document.items)
      if (!(item is TextOverlay && item.id == skipText)) item,
    ?active,
  ];
  var i = 0;
  while (i < items.length) {
    final item = items[i];
    switch (item) {
      case PenStroke():
        _paintPen(canvas, item);
        i++;
      case MosaicStroke():
        // Strokes of one kind in a row share one layer.
        var end = i + 1;
        while (end < items.length &&
            items[end] is MosaicStroke &&
            (items[end] as MosaicStroke).kind == item.kind) {
          end++;
        }
        _paintMosaic(canvas, assets, [
          for (var k = i; k < end; k++) items[k] as MosaicStroke,
        ]);
        i = end;
      case TextOverlay():
        paintTextOverlay(canvas, assets, item);
        i++;
    }
  }
  canvas.restore();
}

ui.Path _linePath(List<ui.Offset> points) {
  final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
  if (points.length == 2) {
    path.lineTo(points[1].dx, points[1].dy);
  } else {
    // Smooth the corners of a hand-drawn line: curve through the middles.
    for (var i = 1; i < points.length - 1; i++) {
      final mid = ui.Offset(
        (points[i].dx + points[i + 1].dx) / 2,
        (points[i].dy + points[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
  }
  return path;
}

void _paintPen(ui.Canvas canvas, PenStroke stroke) {
  if (stroke.points.isEmpty) {
    return;
  }
  if (stroke.points.length == 1) {
    canvas.drawCircle(
      stroke.points.first,
      stroke.width / 2,
      ui.Paint()
        ..color = ui.Color(stroke.color)
        ..isAntiAlias = true,
    );
    return;
  }
  canvas.drawPath(
    _linePath(stroke.points),
    ui.Paint()
      ..color = ui.Color(stroke.color)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = stroke.width
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..isAntiAlias = true,
  );
}

void _paintMosaic(
  ui.Canvas canvas,
  EditorAssets assets,
  List<MosaicStroke> strokes,
) {
  var area = ui.Rect.zero;
  var first = true;
  for (final stroke in strokes) {
    for (final point in stroke.points) {
      final box = ui.Rect.fromCircle(
        center: point,
        radius: stroke.width / 2 + 2,
      );
      area = first ? box : area.expandToInclude(box);
      first = false;
    }
  }
  if (first) {
    return;
  }
  final size = assets.size;
  final full = ui.Rect.fromLTWH(0, 0, size.width, size.height);
  area = area.intersect(full);
  if (area.isEmpty) {
    return;
  }
  final pixelate = strokes.first.kind == MosaicKind.pixelate;
  final effect = pixelate ? assets.pixelated : assets.blurred;
  canvas.saveLayer(area, ui.Paint());
  // The brush's shape, as a mask...
  final mask = ui.Paint()
    ..color = const ui.Color(0xFF000000)
    ..isAntiAlias = true;
  for (final stroke in strokes) {
    if (stroke.points.length == 1) {
      canvas.drawCircle(stroke.points.first, stroke.width / 2, mask);
    } else if (stroke.points.isNotEmpty) {
      canvas.drawPath(
        _linePath(stroke.points),
        mask
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = stroke.width
          ..strokeCap = ui.StrokeCap.round
          ..strokeJoin = ui.StrokeJoin.round,
      );
      mask.style = ui.PaintingStyle.fill;
    }
  }
  // ...and the shrunk picture drawn big, kept where the mask is.
  final scale = pixelate ? assets.block : 4.0;
  canvas.drawImageRect(
    effect,
    ui.Rect.fromLTWH(0, 0, effect.width.toDouble(), effect.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, effect.width * scale, effect.height * scale),
    ui.Paint()
      ..blendMode = ui.BlendMode.srcIn
      ..filterQuality = pixelate
          ? ui.FilterQuality.none
          : ui.FilterQuality.high,
  );
  canvas.restore();
}

/// Paints one text overlay (moved, turned and scaled) into the canvas.
void paintTextOverlay(ui.Canvas canvas, EditorAssets assets, TextOverlay item) {
  if (item.text.isEmpty) {
    return;
  }
  final layout = assets.textLayout(item);
  canvas.save();
  canvas.translate(item.center.dx, item.center.dy);
  canvas.rotate(item.rotation);
  canvas.scale(item.scale);
  final box = layout.box;
  if (item.pill) {
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(
          center: ui.Offset.zero,
          width: box.width,
          height: box.height,
        ),
        ui.Radius.circular(layout.radius),
      ),
      ui.Paint()
        ..color = layout.pillColor
        ..isAntiAlias = true,
    );
  }
  layout.painter.paint(
    canvas,
    ui.Offset(-layout.painter.width / 2, -layout.painter.height / 2),
  );
  canvas.restore();
}

/// The edited picture as a JPEG.
class EditedPhoto {
  const EditedPhoto({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Draws the edits onto the picture, turned and cropped, and encodes it as
/// a JPEG with [prepareJpegPhoto]. At most [maxEdge] on the long side; the
/// file is kept under the chat's size limit. Null when it cannot be made.
Future<EditedPhoto?> renderEditedPhoto({
  required EditorAssets assets,
  required EditorDocument document,
  required String fileName,
  required int maxEdge,
  int quality = photoJpegQuality,
}) async {
  var edge = maxEdge;
  var q = quality;
  for (var attempt = 0; attempt < 4; attempt++) {
    final png = await _renderPng(assets, document, edge);
    if (png == null) {
      return null;
    }
    final prepared = await prepareJpegPhoto(
      bytes: png.bytes,
      fileName: fileName,
      maxEdge: edge,
      quality: q,
    );
    if (prepared == null) {
      return null;
    }
    if (prepared.bytes.length <= maxChatFileBytes) {
      return EditedPhoto(
        bytes: prepared.bytes,
        width: prepared.width,
        height: prepared.height,
      );
    }
    // Over the limit: a little less quality, then a smaller picture.
    if (q > 70) {
      q = 70;
    } else {
      edge = (edge * 0.75).round();
    }
  }
  return null;
}

Future<({Uint8List bytes, int width, int height})?> _renderPng(
  EditorAssets assets,
  EditorDocument document,
  int maxEdge,
) async {
  final turned = rotatedSize(assets.size, document.quarterTurns);
  final region = document.crop ?? ui.Offset.zero & turned;
  final out = outputSize(region.size, maxEdge);
  final scale = out.width / region.width;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(scale);
  canvas.translate(-region.left, -region.top);
  canvas.transform(sourceToRotated(assets.size, document.quarterTurns).storage);
  paintEditorScene(canvas, assets, document);
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(out.width.round(), out.height.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      return null;
    }
    return (
      bytes: data.buffer.asUint8List(),
      width: image.width,
      height: image.height,
    );
  } on Object {
    return null;
  } finally {
    image?.dispose();
    picture.dispose();
  }
}
