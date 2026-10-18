import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The model of the photo editor: what has been drawn on a picture, how it
/// is turned and cropped, and the undo history. It knows nothing about
/// widgets, so it is tested on its own.
///
/// Everything is stored in the picture's own pixels ("source space"): the
/// decoded picture, top-left at (0, 0). Turning and cropping are kept apart
/// from the marks, so a mark turns with the picture and a crop can always be
/// widened again.

/// The marks that can be put on a picture.
sealed class EditorItem {
  const EditorItem();
}

/// A free-hand pen line.
@immutable
class PenStroke extends EditorItem {
  const PenStroke({
    required this.points,
    required this.color,
    required this.width,
  });

  /// The path, in source pixels.
  final List<Offset> points;

  /// ARGB.
  final int color;

  /// The line's thickness in source pixels.
  final double width;

  PenStroke withPoint(Offset point) =>
      PenStroke(points: [...points, point], color: color, width: width);
}

/// How a mosaic brush hides what it paints over.
enum MosaicKind { pixelate, blur }

/// A stretch of the mosaic / blur brush.
@immutable
class MosaicStroke extends EditorItem {
  const MosaicStroke({
    required this.points,
    required this.width,
    required this.kind,
  });

  final List<Offset> points;
  final double width;
  final MosaicKind kind;

  MosaicStroke withPoint(Offset point) =>
      MosaicStroke(points: [...points, point], width: width, kind: kind);
}

/// A piece of text laid on the picture. It can be moved, resized and
/// turned.
@immutable
class TextOverlay extends EditorItem {
  const TextOverlay({
    required this.id,
    required this.text,
    required this.color,
    required this.center,
    this.pill = false,
    this.scale = 1,
    this.rotation = 0,
  });

  /// Tells overlays apart while they are being edited.
  final int id;
  final String text;

  /// ARGB. With [pill] this is the fill of the pill behind the text and the
  /// text takes a contrasting color.
  final int color;

  /// The middle of the text, in source pixels.
  final Offset center;

  /// A rounded background behind the text.
  final bool pill;

  /// 1 is the base size (see [TextOverlayMetrics.baseFontSize]).
  final double scale;

  /// Radians, clockwise on the picture.
  final double rotation;

  TextOverlay copyWith({
    String? text,
    int? color,
    Offset? center,
    bool? pill,
    double? scale,
    double? rotation,
  }) {
    return TextOverlay(
      id: id,
      text: text ?? this.text,
      color: color ?? this.color,
      center: center ?? this.center,
      pill: pill ?? this.pill,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextOverlay &&
      other.id == id &&
      other.text == text &&
      other.color == color &&
      other.center == center &&
      other.pill == pill &&
      other.scale == scale &&
      other.rotation == rotation;

  @override
  int get hashCode =>
      Object.hash(id, text, color, center, pill, scale, rotation);
}

/// The text scale limits.
const minTextScale = 0.3;
const maxTextScale = 6.0;

/// A picture with its edits. Immutable: every change makes a new one, which
/// is what the undo history keeps.
@immutable
class EditorDocument {
  const EditorDocument({
    this.quarterTurns = 0,
    this.crop,
    this.items = const [],
  });

  /// How many quarter turns clockwise the picture is turned (0 to 3).
  final int quarterTurns;

  /// What is kept of the turned picture, in the turned picture's pixels;
  /// null keeps all of it.
  final Rect? crop;

  final List<EditorItem> items;

  /// Nothing was done: sending this is sending the original.
  bool get isUnedited => quarterTurns == 0 && crop == null && items.isEmpty;

  EditorDocument copyWith({
    int? quarterTurns,
    Object? crop = _keep,
    List<EditorItem>? items,
  }) {
    return EditorDocument(
      quarterTurns: quarterTurns ?? this.quarterTurns,
      crop: identical(crop, _keep) ? this.crop : crop as Rect?,
      items: items ?? this.items,
    );
  }

  EditorDocument withItem(EditorItem item) => copyWith(items: [...items, item]);

  EditorDocument withoutItem(EditorItem item) =>
      copyWith(items: [...items.where((other) => other != item)]);

  /// Swaps the text overlay with [replacement]'s id for [replacement].
  EditorDocument withReplacedText(TextOverlay replacement) {
    return copyWith(
      items: [
        for (final item in items)
          if (item is TextOverlay && item.id == replacement.id)
            replacement
          else
            item,
      ],
    );
  }

  EditorDocument withoutText(int id) => copyWith(
    items: [
      for (final item in items)
        if (!(item is TextOverlay && item.id == id)) item,
    ],
  );

  TextOverlay? textById(int? id) {
    if (id == null) {
      return null;
    }
    for (final item in items) {
      if (item is TextOverlay && item.id == id) {
        return item;
      }
    }
    return null;
  }

  Iterable<TextOverlay> get texts => items.whereType<TextOverlay>();

  /// Pen lines, mosaic stretches and text overlays, in the order drawn.
  int get markCount => items.length;

  @override
  bool operator ==(Object other) =>
      other is EditorDocument &&
      other.quarterTurns == quarterTurns &&
      other.crop == crop &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(quarterTurns, crop, Object.hashAll(items));
}

const _keep = Object();

/// The edit session: the current [document], the active stroke being drawn,
/// and the undo / redo history.
///
/// A drag that changes the document many times (moving a text, a crop
/// handle) calls [beginChange], [update] for each step and [commitChange],
/// so the whole drag is one step of the history.
class EditorController extends ChangeNotifier {
  EditorController([EditorDocument initial = const EditorDocument()])
    : _document = initial;

  /// How many steps the history keeps.
  static const maxHistory = 100;

  EditorDocument _document;
  final _undo = <EditorDocument>[];
  final _redo = <EditorDocument>[];
  EditorDocument? _changeStart;
  EditorItem? _active;
  int _nextTextId = 1;

  EditorDocument get document => _document;

  /// The stroke the finger or mouse is drawing right now, not yet part of
  /// the document.
  EditorItem? get activeItem => _active;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Whether the document differs from where this session started (or from
  /// the document it was given).
  bool get isChanged => _undo.isNotEmpty || _active != null;

  int newTextId() => _nextTextId++;

  /// Makes [next] the document as one step.
  void commit(EditorDocument next) {
    if (next == _document) {
      return;
    }
    _push(_document);
    _document = next;
    _redo.clear();
    notifyListeners();
  }

  void _push(EditorDocument value) {
    _undo.add(value);
    if (_undo.length > maxHistory) {
      _undo.removeAt(0);
    }
  }

  void beginChange() {
    _changeStart = _document;
  }

  /// Shows [next] without a history step; finish with [commitChange].
  void update(EditorDocument next) {
    _document = next;
    notifyListeners();
  }

  void commitChange() {
    final start = _changeStart;
    _changeStart = null;
    if (start != null && start != _document) {
      _push(start);
      _redo.clear();
      notifyListeners();
    }
  }

  /// Puts back what [beginChange] saw.
  void cancelChange() {
    final start = _changeStart;
    _changeStart = null;
    if (start != null && start != _document) {
      _document = start;
      notifyListeners();
    }
  }

  // Strokes.

  void startStroke(EditorItem item) {
    _active = item;
    notifyListeners();
  }

  void extendStroke(Offset point) {
    final active = _active;
    if (active is PenStroke) {
      _active = active.withPoint(point);
    } else if (active is MosaicStroke) {
      _active = active.withPoint(point);
    } else {
      return;
    }
    notifyListeners();
  }

  /// Adds the stroke being drawn to the document.
  void endStroke() {
    final active = _active;
    _active = null;
    if (active == null) {
      return;
    }
    commit(_document.withItem(active));
    notifyListeners();
  }

  void cancelStroke() {
    if (_active != null) {
      _active = null;
      notifyListeners();
    }
  }

  // History.

  void undo() {
    cancelStroke();
    if (_undo.isEmpty) {
      return;
    }
    _redo.add(_document);
    _document = _undo.removeLast();
    notifyListeners();
  }

  void redo() {
    cancelStroke();
    if (_redo.isEmpty) {
      return;
    }
    _undo.add(_document);
    _document = _redo.removeLast();
    notifyListeners();
  }

  /// Back to the untouched picture, as one step that can be undone.
  void reset() {
    commit(const EditorDocument());
  }
}

/// The colors of the pen, the text and the brush: content colors for
/// marking up a photo, not part of the app's palette.
class EditorPalette {
  const EditorPalette._();

  static const colors = <({int argb, String name})>[
    (argb: 0xFFFFFFFF, name: 'White'),
    (argb: 0xFF17171A, name: 'Black'),
    (argb: 0xFFE12F35, name: 'Red'),
    (argb: 0xFFFF8A1F, name: 'Orange'),
    (argb: 0xFFFFD60A, name: 'Yellow'),
    (argb: 0xFF30B96B, name: 'Green'),
    (argb: 0xFF2F6BF6, name: 'Blue'),
    (argb: 0xFF9B5DE5, name: 'Purple'),
  ];

  /// The default pen and text color.
  static const defaultColor = 0xFFE12F35;

  /// Black or white text on a pill of [argb], whichever reads better.
  static int onColor(int argb) {
    return Color(argb).computeLuminance() > 0.45 ? 0xFF17171A : 0xFFFFFFFF;
  }
}

/// The three line widths, as a fraction of the picture's shorter side.
enum StrokeWidth {
  thin(0.006, 0.05),
  medium(0.012, 0.085),
  thick(0.024, 0.14);

  const StrokeWidth(this.pen, this.brush);

  final double pen;
  final double brush;

  /// Pen thickness in source pixels for a picture of [size].
  double penFor(Size size) => math.max(2, size.shortestSide * pen);

  /// Brush thickness in source pixels.
  double brushFor(Size size) => math.max(8, size.shortestSide * brush);
}

/// The size of the blocks of the mosaic, in source pixels.
double mosaicBlockSize(Size size) =>
    math.max(6, (size.shortestSide / 48).roundToDouble());

/// How a text overlay is measured. [baseFontSize] is relative to the
/// picture so text looks the same on a small and a large picture.
class TextOverlayMetrics {
  const TextOverlayMetrics._();

  static double baseFontSize(Size source) =>
      math.max(14, source.shortestSide * 0.07);

  /// The widest a line may be before it wraps (at scale 1).
  static double maxLineWidth(Size source) => source.shortestSide * 0.9;
}

/// The point of [item] hit by [point] (source pixels), given the size of
/// the item's box at scale 1.
bool textHitTest(TextOverlay item, Size box, Offset point, {double slop = 0}) {
  final local = _toTextLocal(item, point);
  return local.dx.abs() <= box.width / 2 + slop &&
      local.dy.abs() <= box.height / 2 + slop;
}

Offset _toTextLocal(TextOverlay item, Offset point) {
  final d = point - item.center;
  final cos = math.cos(-item.rotation);
  final sin = math.sin(-item.rotation);
  return Offset(
    (d.dx * cos - d.dy * sin) / item.scale,
    (d.dx * sin + d.dy * cos) / item.scale,
  );
}

/// The topmost text overlay under [point], given [measure] for each one's
/// box at scale 1.
TextOverlay? hitTestTexts(
  EditorDocument document,
  Offset point,
  Size Function(TextOverlay) measure, {
  double slop = 0,
}) {
  for (final item in document.items.reversed) {
    if (item is TextOverlay &&
        textHitTest(item, measure(item), point, slop: slop)) {
      return item;
    }
  }
  return null;
}
