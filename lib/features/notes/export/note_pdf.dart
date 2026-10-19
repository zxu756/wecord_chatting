import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:wecord/features/notes/export/simple_pdf.dart';
import 'package:wecord/features/notes/note_merge.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_table.dart';
import 'package:wecord/features/notes/note_text_ops.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

/// Loads the picture of an image block, or null when it cannot be had.
typedef NotePictureLoader = Future<ui.Image?> Function(NoteBlock block);

const _pageWidth = 595.0;
const _pageHeight = 842.0;
const _marginX = 52.0;
const _marginTop = 56.0;
const _marginBottom = 64.0;
const _contentWidth = _pageWidth - _marginX * 2;
const _pageBottom = _pageHeight - _marginBottom;
const _ink = Color(0xFF14151A);
const _muted = Color(0xFF6B6F7B);
const _line = Color(0xFFD5D8DF);
const _soft = Color(0xFFF1F2F5);
const _link = Color(0xFF2F5BD8);

/// The pages of a note as a PDF, drawn with the device's own fonts (so
/// Chinese, emoji and the rest come out right) and put in the file as
/// pictures, see [buildImagePdf].
///
/// Layout: A4, a title, then the blocks in order; text breaks between lines,
/// a table between rows, a picture is scaled to fit and never split; page
/// numbers at the bottom. [scale] is pixels per point (2 is 144 dpi).
Future<Uint8List> buildNotePdf({
  required String title,
  required String icon,
  required List<NoteBlock> blocks,
  NotePictureLoader? loadPicture,
  double scale = 2,
  String untitled = 'Untitled',
}) async {
  final layout = _Layout();
  final heading = title.trim().isEmpty ? untitled : title.trim();
  layout.addText(
    _plainSpan(
      '${icon.isEmpty ? '' : '$icon '}$heading',
      _style(26, bold: true),
    ),
    gapBefore: 0,
    gapAfter: 10,
  );

  final numbers = listNumbers(blocks);
  for (final (index, block) in blocks.indexed) {
    switch (block.kind) {
      case NoteBlockKind.heading1:
        layout.addText(_spans(block, _style(21, bold: true)), gapBefore: 14);
      case NoteBlockKind.heading2:
        layout.addText(_spans(block, _style(17, bold: true)), gapBefore: 11);
      case NoteBlockKind.heading3:
        layout.addText(_spans(block, _style(14.5, bold: true)), gapBefore: 8);
      case NoteBlockKind.paragraph:
        layout.addText(_spans(block, _style(11.5)), gapBefore: 3);
      case NoteBlockKind.bullet:
        layout.addText(
          _spans(block, _style(11.5)),
          gapBefore: 3,
          indent: 18,
          marker: '•',
        );
      case NoteBlockKind.numbered:
        layout.addText(
          _spans(block, _style(11.5)),
          gapBefore: 3,
          indent: 22,
          marker: '${numbers[index]}.',
        );
      case NoteBlockKind.todo:
        layout.addText(
          _spans(
            block,
            _style(11.5, struck: block.checked, muted: block.checked),
          ),
          gapBefore: 3,
          indent: 20,
          marker: block.checked ? '☑' : '☐',
        );
      case NoteBlockKind.quote:
        layout.addText(
          _spans(block, _style(11.5, italic: true, muted: true)),
          gapBefore: 4,
          indent: 14,
          bar: true,
        );
      case NoteBlockKind.code:
        layout.addText(
          TextSpan(text: block.text, style: _style(10, mono: true)),
          gapBefore: 5,
          indent: 10,
          box: true,
        );
      case NoteBlockKind.divider:
        layout.addDivider();
      case NoteBlockKind.image:
        final picture = loadPicture == null ? null : await loadPicture(block);
        layout.addPicture(picture, '${block.props['name'] ?? ''}');
      case NoteBlockKind.table:
        layout.addTable(NoteTable.fromProps(block.props));
    }
  }

  final pages = layout.finish();
  final result = <PdfPageImage>[];
  for (final (index, ops) in pages.indexed) {
    result.add(await _renderPage(ops, index + 1, pages.length, scale));
  }
  layout.dispose();
  return buildImagePdf(result, title: heading);
}

// ----------------------------------------------------------------- text --

TextStyle _style(
  double size, {
  bool bold = false,
  bool italic = false,
  bool mono = false,
  bool muted = false,
  bool struck = false,
}) {
  return TextStyle(
    fontFamily: mono ? 'JetBrains Mono' : 'Plus Jakarta Sans',
    fontFamilyFallback: WeCordTheme.fontFamilyFallback,
    fontSize: size,
    height: mono ? 1.45 : 1.5,
    fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    color: muted ? _muted : _ink,
    decoration: struck ? TextDecoration.lineThrough : null,
  );
}

TextSpan _plainSpan(String text, TextStyle style) =>
    TextSpan(text: text, style: style);

/// A block's text with its formatting drawn.
TextSpan _spans(NoteBlock block, TextStyle base) {
  final text = block.text;
  if (text.isEmpty || block.marks.isEmpty) {
    return TextSpan(text: text, style: base);
  }
  final cuts = <int>{0, text.length};
  for (final mark in block.marks) {
    cuts
      ..add(mark.start.clamp(0, text.length))
      ..add(mark.end.clamp(0, text.length));
  }
  final points = cuts.toList()..sort();
  final sets = marksToCharSets(text.length, block.marks);
  final children = <InlineSpan>[];
  for (var i = 0; i + 1 < points.length; i++) {
    final from = points[i];
    final to = points[i + 1];
    if (from == to) {
      continue;
    }
    var style = const TextStyle();
    final decorations = <TextDecoration>[];
    for (final type in sets[from]) {
      if (type == NoteMark.bold) {
        style = style.copyWith(fontWeight: FontWeight.w800);
      } else if (type == NoteMark.italic) {
        style = style.copyWith(fontStyle: FontStyle.italic);
      } else if (type == NoteMark.strike) {
        decorations.add(TextDecoration.lineThrough);
      } else if (type == NoteMark.code) {
        style = style.copyWith(
          fontFamily: 'JetBrains Mono',
          fontSize: (base.fontSize ?? 12) * 0.9,
          backgroundColor: _soft,
        );
      } else if (type.startsWith(NoteMark.linkPrefix)) {
        style = style.copyWith(color: _link);
        decorations.add(TextDecoration.underline);
      } else if (type.startsWith(NoteMark.mentionPrefix)) {
        style = style.copyWith(color: _link, fontWeight: FontWeight.w700);
      }
    }
    if (decorations.isNotEmpty) {
      style = style.copyWith(decoration: TextDecoration.combine(decorations));
    }
    children.add(TextSpan(text: text.substring(from, to), style: style));
  }
  return TextSpan(style: base, children: children);
}

// --------------------------------------------------------------- layout --

typedef _Paint = void Function(ui.Canvas canvas, double top);

class _Op {
  const _Op(this.height, this.gapBefore, this.paint);

  final double height;
  final double gapBefore;
  final _Paint paint;
}

class _PlacedOp {
  const _PlacedOp(this.top, this.paint);

  final double top;
  final _Paint paint;
}

/// Puts blocks on pages: each is cut into pieces that are never split
/// (a line of text, a row of a table, a picture).
class _Layout {
  final _ops = <_Op>[];
  final _painters = <TextPainter>[];

  void dispose() {
    for (final painter in _painters) {
      painter.dispose();
    }
  }

  TextPainter _painter(InlineSpan span, double width) {
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: width);
    _painters.add(painter);
    return painter;
  }

  void addText(
    InlineSpan span, {
    double gapBefore = 3,
    double gapAfter = 0,
    double indent = 0,
    String? marker,
    bool bar = false,
    bool box = false,
  }) {
    final padding = box ? 8.0 : 0.0;
    final painter = _painter(span, _contentWidth - indent - padding * 2);
    final lines = painter.computeLineMetrics();
    final style = span.style;
    if (lines.isEmpty) {
      // An empty line still takes its place.
      final height = (style?.fontSize ?? 12) * (style?.height ?? 1.5);
      _ops.add(_Op(height, gapBefore, (canvas, top) {}));
      return;
    }
    var lineTop = 0.0;
    for (final (index, line) in lines.indexed) {
      final from = lineTop;
      final height = line.height;
      lineTop += height;
      final first = index == 0;
      final last = index == lines.length - 1;
      _ops.add(
        _Op(
          height + (box ? (first ? padding : 0) + (last ? padding : 0) : 0),
          first ? gapBefore : 0,
          (canvas, top) {
            final inset = box && first ? padding : 0.0;
            if (box) {
              canvas.drawRect(
                Rect.fromLTWH(
                  indent - padding,
                  top,
                  _contentWidth - indent + padding,
                  height + (first ? padding : 0) + (last ? padding : 0),
                ),
                Paint()..color = _soft,
              );
            }
            if (bar) {
              canvas.drawRect(
                Rect.fromLTWH(0, top, 2.5, height),
                Paint()..color = _line,
              );
            }
            if (first && marker != null) {
              final markerPainter = _painter(
                TextSpan(
                  text: marker,
                  style: (style ?? const TextStyle()).copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
                indent,
              );
              markerPainter.paint(canvas, Offset(0, top));
            }
            canvas.save();
            canvas.clipRect(
              Rect.fromLTWH(
                indent + padding,
                top + inset,
                _contentWidth,
                height,
              ),
            );
            painter.paint(canvas, Offset(indent + padding, top + inset - from));
            canvas.restore();
          },
        ),
      );
    }
    if (gapAfter > 0) {
      _ops.add(_Op(0, gapAfter, (canvas, top) {}));
    }
  }

  void addDivider() {
    _ops.add(
      _Op(1, 12, (canvas, top) {
        canvas.drawRect(
          Rect.fromLTWH(0, top, _contentWidth, 1),
          Paint()..color = _line,
        );
      }),
    );
    _ops.add(_Op(0, 6, (canvas, top) {}));
  }

  void addPicture(ui.Image? picture, String name) {
    if (picture == null) {
      addText(
        _plainSpan(
          '[${name.isEmpty ? 'picture' : name}]',
          _style(10.5, muted: true),
        ),
        gapBefore: 4,
      );
      return;
    }
    final ratio = picture.width / math.max(1, picture.height);
    var width = math.min(_contentWidth, picture.width.toDouble());
    var height = width / ratio;
    final limit = (_pageBottom - _marginTop) * 0.85;
    if (height > limit) {
      height = limit;
      width = height * ratio;
    }
    _ops.add(
      _Op(height, 6, (canvas, top) {
        canvas.drawImageRect(
          picture,
          Rect.fromLTWH(
            0,
            0,
            picture.width.toDouble(),
            picture.height.toDouble(),
          ),
          Rect.fromLTWH(0, top, width, height),
          Paint()..filterQuality = FilterQuality.medium,
        );
      }),
    );
  }

  void addTable(NoteTable table) {
    final columns = table.columns.length;
    const pad = 5.0;
    final columnWidth = _contentWidth / columns;
    var first = true;
    for (final (r, cells) in table.textRows.indexed) {
      final isHeader = table.header && r == 0;
      final painters = [
        for (final cell in cells)
          _painter(
            TextSpan(
              text: cell,
              style: _style(10.5, bold: isHeader),
            ),
            columnWidth - pad * 2,
          ),
      ];
      final height =
          painters.fold<double>(
            0,
            (tallest, p) => math.max(tallest, p.height),
          ) +
          pad * 2;
      _ops.add(
        _Op(height, first ? 6 : 0, (canvas, top) {
          if (isHeader) {
            canvas.drawRect(
              Rect.fromLTWH(0, top, _contentWidth, height),
              Paint()..color = _soft,
            );
          }
          final border = Paint()
            ..color = _line
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8;
          for (var c = 0; c < columns; c++) {
            final x = c * columnWidth;
            canvas.drawRect(Rect.fromLTWH(x, top, columnWidth, height), border);
            painters[c].paint(canvas, Offset(x + pad, top + pad));
          }
        }),
      );
      first = false;
    }
  }

  /// The pieces on pages: for each page its pieces with their positions.
  List<List<_PlacedOp>> finish() {
    final pages = <List<_PlacedOp>>[[]];
    var y = _marginTop;
    var atTop = true;
    for (final op in _ops) {
      final gap = atTop ? 0.0 : op.gapBefore;
      if (!atTop && y + gap + op.height > _pageBottom) {
        pages.add([]);
        y = _marginTop;
        atTop = true;
      }
      final top = y + (atTop ? 0 : gap);
      pages.last.add(_PlacedOp(top, op.paint));
      y = top + op.height;
      atTop = false;
    }
    return pages;
  }
}

Future<PdfPageImage> _renderPage(
  List<_PlacedOp> ops,
  int number,
  int count,
  double scale,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(scale);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, _pageWidth, _pageHeight),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  canvas.save();
  canvas.translate(_marginX, 0);
  for (final op in ops) {
    op.paint(canvas, op.top);
  }
  canvas.restore();
  final footer = TextPainter(
    text: TextSpan(text: '$number / $count', style: _style(9, muted: true)),
    textDirection: TextDirection.ltr,
  )..layout();
  footer.paint(
    canvas,
    Offset((_pageWidth - footer.width) / 2, _pageHeight - 36),
  );
  footer.dispose();

  final width = (_pageWidth * scale).round();
  final height = (_pageHeight * scale).round();
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (data == null) {
    throw StateError('Could not draw the page.');
  }
  final raster = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: data.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  final jpeg = Uint8List.fromList(img.encodeJpg(raster, quality: 86));
  return PdfPageImage(jpeg: jpeg, pixelWidth: width, pixelHeight: height);
}
