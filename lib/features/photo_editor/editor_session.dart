import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Matrix4;
import 'package:wecord/features/photo_editor/crop_math.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';
import 'package:wecord/features/photo_editor/editor_render.dart';

/// The four tools of the editor.
enum EditorTool { draw, text, mosaic, crop }

/// Everything the editor screen is doing: the tool and its settings, the
/// document with its history, the zoom of the view and what is selected.
/// Widgets send it view coordinates (pixels of the canvas on screen); it
/// turns them into picture coordinates.
class EditorSession extends ChangeNotifier {
  EditorSession({required this.assets, EditorDocument? initial})
    : controller = EditorController(initial ?? const EditorDocument()) {
    controller.addListener(notifyListeners);
  }

  final EditorAssets assets;
  final EditorController controller;

  EditorTool _tool = EditorTool.draw;
  int _penColor = EditorPalette.defaultColor;
  StrokeWidth _penWidth = StrokeWidth.medium;
  MosaicKind _mosaicKind = MosaicKind.pixelate;
  StrokeWidth _mosaicWidth = StrokeWidth.medium;
  int _textColor = EditorPalette.colors.first.argb;
  bool _textPill = false;

  int get penColor => _penColor;
  StrokeWidth get penWidth => _penWidth;
  MosaicKind get mosaicKind => _mosaicKind;
  StrokeWidth get mosaicWidth => _mosaicWidth;
  int get textColor => _textColor;
  bool get textPill => _textPill;

  void setPenColor(int argb) {
    _penColor = argb;
    notifyListeners();
  }

  void setPenWidth(StrokeWidth width) {
    _penWidth = width;
    notifyListeners();
  }

  void setMosaicKind(MosaicKind kind) {
    _mosaicKind = kind;
    notifyListeners();
  }

  void setMosaicWidth(StrokeWidth width) {
    _mosaicWidth = width;
    notifyListeners();
  }

  CropRatio _ratio = CropRatio.free;

  Size _view = Size.zero;
  double _zoom = 1;
  Offset _pan = Offset.zero;

  int? _selectedText;

  TextOverlay? _draft;
  var _draftIsNew = true;

  EditorDocument get document => controller.document;
  Size get sourceSize => assets.size;

  EditorTool get tool => _tool;
  CropRatio get ratio => _ratio;
  double get zoom => _zoom;
  int? get selectedTextId => _selectedText;
  TextOverlay? get selectedText => document.textById(_selectedText);

  /// The text being typed in the entry box, shown on the picture while it
  /// is typed.
  TextOverlay? get draftText => _draft;

  /// The overlay the scene must not draw from the document (it is being
  /// edited).
  int? get editingText => _draft?.id;

  /// Starts typing [item] (a new one, or an existing one to change).
  void startTextEntry(TextOverlay item, {required bool isNew}) {
    _draft = item;
    _draftIsNew = isNew;
    notifyListeners();
  }

  void updateDraft(TextOverlay item) {
    _draft = item;
    notifyListeners();
  }

  /// Ends the entry: with [keep] the text goes on the picture (an empty
  /// text removes the overlay), without it nothing changed.
  void finishTextEntry({required bool keep}) {
    final draft = _draft;
    _draft = null;
    if (draft != null && keep) {
      final empty = draft.text.trim().isEmpty;
      if (_draftIsNew) {
        if (!empty) {
          _textColor = draft.color;
          _textPill = draft.pill;
          addText(draft);
        }
      } else if (empty) {
        removeText(draft.id);
      } else {
        replaceText(draft);
      }
    }
    notifyListeners();
  }

  bool get canUndo => controller.canUndo;
  bool get canRedo => controller.canRedo;

  /// Whether leaving would lose anything.
  bool get hasChanges => controller.isChanged;

  @override
  void dispose() {
    controller.removeListener(notifyListeners);
    controller.dispose();
    assets.dispose();
    super.dispose();
  }

  void selectTool(EditorTool tool) {
    if (tool == _tool) {
      return;
    }
    _tool = tool;
    if (tool != EditorTool.text) {
      _selectedText = null;
    }
    if (tool == EditorTool.crop) {
      _zoom = 1;
      _pan = Offset.zero;
    }
    notifyListeners();
  }

  // The view.

  Size get viewSize => _view;

  void setViewSize(Size size) {
    if (size != _view) {
      _view = size;
      // Called while laying out; listeners rebuild on the next frame.
      _pan = fit.clampPan(_pan);
    }
  }

  Size get turnedSize => rotatedSize(sourceSize, document.quarterTurns);

  Rect get fullRect => Offset.zero & turnedSize;

  /// The crop, or the whole turned picture.
  Rect get cropRect => document.crop ?? fullRect;

  /// What the view shows: the crop, or while cropping the whole picture.
  Rect get region => _tool == EditorTool.crop ? fullRect : cropRect;

  /// The picture keeps clear of the canvas edge while cropping, so the
  /// crop's handles can be reached.
  double get inset => _tool == EditorTool.crop ? 22 : 0;

  ViewFit get fit => ViewFit(
    view: _view,
    region: region,
    zoom: _zoom,
    pan: _pan,
    inset: inset,
  );

  /// Maps picture pixels to the canvas.
  Matrix4 get sourceToView =>
      fit.turnedToView
        ..multiply(sourceToRotated(sourceSize, document.quarterTurns));

  Offset viewToSource(Offset point) {
    final inverse = Matrix4.copy(sourceToView)..invert();
    return transformPoint(inverse, point);
  }

  Offset sourceToViewPoint(Offset point) => transformPoint(sourceToView, point);

  /// The crop rectangle on the canvas.
  Rect get cropRectInView => Rect.fromPoints(
    fit.toView(cropRect.topLeft),
    fit.toView(cropRect.bottomRight),
  );

  void zoomAbout(Offset focal, double newZoom) {
    if (_tool == EditorTool.crop) {
      return;
    }
    final next = fit.zoomedAbout(focal, newZoom);
    _zoom = next.zoom;
    _pan = next.pan;
    notifyListeners();
  }

  void panBy(Offset delta) {
    if (_tool == EditorTool.crop || _zoom <= 1) {
      return;
    }
    _pan = fit.clampPan(_pan + delta);
    notifyListeners();
  }

  void resetZoom() {
    if (_zoom != 1 || _pan != Offset.zero) {
      _zoom = 1;
      _pan = Offset.zero;
      notifyListeners();
    }
  }

  // Pinching: the picture follows two fingers.

  double _pinchZoom = 1;
  Offset _pinchPan = Offset.zero;
  Offset _pinchFocal = Offset.zero;

  void beginPinch(Offset focal) {
    _pinchZoom = _zoom;
    _pinchPan = _pan;
    _pinchFocal = focal;
  }

  void updatePinch(Offset focal, double scale) {
    if (_tool == EditorTool.crop) {
      return;
    }
    final start = ViewFit(
      view: _view,
      region: region,
      zoom: _pinchZoom,
      pan: _pinchPan,
      inset: inset,
    );
    final turned = start.toTurned(_pinchFocal);
    final zoom = (_pinchZoom * scale).clamp(1.0, ViewFit.maxZoom).toDouble();
    final probe = ViewFit(
      view: _view,
      region: region,
      zoom: zoom,
      inset: inset,
    );
    final pan = focal - probe.toView(turned);
    _zoom = zoom;
    _pan = probe.clampPan(pan);
    notifyListeners();
  }

  // Strokes.

  EditorItem? get activeItem => controller.activeItem;

  void beginStroke(Offset viewPoint) {
    final point = viewToSource(viewPoint);
    if (_tool == EditorTool.draw) {
      controller.startStroke(
        PenStroke(
          points: [point],
          color: penColor,
          width: penWidth.penFor(sourceSize),
        ),
      );
    } else if (_tool == EditorTool.mosaic) {
      controller.startStroke(
        MosaicStroke(
          points: [point],
          width: mosaicWidth.brushFor(sourceSize),
          kind: mosaicKind,
        ),
      );
    }
  }

  void extendStroke(Offset viewPoint) {
    final active = controller.activeItem;
    final List<Offset> points;
    if (active is PenStroke) {
      points = active.points;
    } else if (active is MosaicStroke) {
      points = active.points;
    } else {
      return;
    }
    final point = viewToSource(viewPoint);
    // Skip samples closer than a screen pixel to the last.
    final minStep = 1 / fit.scale;
    if ((point - points.last).distance < minStep) {
      return;
    }
    controller.extendStroke(point);
  }

  void endStroke() => controller.endStroke();

  /// A tap with the pen or brush makes a dot.
  void dot(Offset viewPoint) {
    beginStroke(viewPoint);
    endStroke();
  }

  // Text.

  Size measureText(TextOverlay item) => assets.textLayout(item).box;

  TextOverlay? hitText(Offset viewPoint) {
    // A touch is not exact: allow a few screen pixels around the text.
    final slop = 10 / (fit.scale * 1);
    return hitTestTexts(
      document,
      viewToSource(viewPoint),
      measureText,
      slop: slop,
    );
  }

  void selectText(int? id) {
    if (_selectedText != id) {
      _selectedText = id;
      notifyListeners();
    }
  }

  /// A new text overlay in the middle of the view (or at [viewPoint]).
  TextOverlay newText(String text, {Offset? viewPoint}) {
    final center = viewToSource(
      viewPoint ?? Offset(_view.width / 2, _view.height / 2),
    );
    return TextOverlay(
      id: controller.newTextId(),
      text: text,
      color: textColor,
      pill: textPill,
      center: _insideSource(center),
    );
  }

  Offset _insideSource(Offset point) => Offset(
    point.dx.clamp(0, sourceSize.width).toDouble(),
    point.dy.clamp(0, sourceSize.height).toDouble(),
  );

  void addText(TextOverlay item) {
    controller.commit(document.withItem(item));
    _selectedText = item.id;
    notifyListeners();
  }

  void replaceText(TextOverlay item) {
    controller.commit(document.withReplacedText(item));
  }

  void removeText(int id) {
    controller.commit(document.withoutText(id));
    if (_selectedText == id) {
      _selectedText = null;
    }
    notifyListeners();
  }

  void setTextColor(int argb) {
    _textColor = argb;
    final selected = selectedText;
    if (selected != null) {
      replaceText(selected.copyWith(color: argb));
    }
    notifyListeners();
  }

  void setTextPill(bool value) {
    _textPill = value;
    final selected = selectedText;
    if (selected != null) {
      replaceText(selected.copyWith(pill: value));
    }
    notifyListeners();
  }

  /// Makes the selected text [factor] times bigger.
  void scaleSelectedText(double factor) {
    final selected = selectedText;
    if (selected != null) {
      replaceText(
        selected.copyWith(
          scale: (selected.scale * factor).clamp(minTextScale, maxTextScale),
        ),
      );
    }
  }

  void rotateSelectedText(double radians) {
    final selected = selectedText;
    if (selected != null) {
      replaceText(selected.copyWith(rotation: selected.rotation + radians));
    }
  }

  void nudgeSelectedText(Offset sourceDelta) {
    final selected = selectedText;
    if (selected != null) {
      replaceText(selected.copyWith(center: selected.center + sourceDelta));
    }
  }

  // Moving, resizing and turning a text with fingers.

  TextOverlay? _textStart;
  Offset _textStartFocal = Offset.zero;

  void beginTextGesture(TextOverlay item, Offset viewFocal) {
    _selectedText = item.id;
    _textStart = item;
    _textStartFocal = viewToSource(viewFocal);
    controller.beginChange();
    notifyListeners();
  }

  /// [scale] and [rotation] are those of two fingers since the gesture
  /// began (1 and 0 for one finger).
  void updateTextGesture(
    Offset viewFocal, {
    double scale = 1,
    double rotation = 0,
  }) {
    final start = _textStart;
    if (start == null) {
      return;
    }
    final delta = viewToSource(viewFocal) - _textStartFocal;
    controller.update(
      document.withReplacedText(
        start.copyWith(
          center: start.center + delta,
          scale: (start.scale * scale).clamp(minTextScale, maxTextScale),
          rotation: start.rotation + rotation,
        ),
      ),
    );
  }

  /// Dragging the corner handle of the selected text: the distance from
  /// the text's middle sets its size, the direction its angle.
  void updateTextHandle(Offset viewPoint) {
    final start = _textStart;
    if (start == null) {
      return;
    }
    final center = start.center;
    final from = _textStartFocal - center;
    final to = viewToSource(viewPoint) - center;
    if (from.distance < 1e-6 || to.distance < 1e-6) {
      return;
    }
    final scale = to.distance / from.distance;
    final rotation = to.direction - from.direction;
    controller.update(
      document.withReplacedText(
        start.copyWith(
          scale: (start.scale * scale).clamp(minTextScale, maxTextScale),
          rotation: start.rotation + rotation,
        ),
      ),
    );
  }

  void endTextGesture() {
    _textStart = null;
    controller.commitChange();
  }

  /// The corners of [item]'s box on the canvas, clockwise from top-left.
  List<Offset> textCornersInView(TextOverlay item) {
    final box = measureText(item);
    final cos = math.cos(item.rotation);
    final sin = math.sin(item.rotation);
    Offset corner(double x, double y) {
      final sx = x * item.scale;
      final sy = y * item.scale;
      return sourceToViewPoint(
        item.center + Offset(sx * cos - sy * sin, sx * sin + sy * cos),
      );
    }

    final hw = box.width / 2;
    final hh = box.height / 2;
    return [corner(-hw, -hh), corner(hw, -hh), corner(hw, hh), corner(-hw, hh)];
  }

  // Cropping.

  CropHandle? _cropHandle;
  Rect _cropStart = Rect.zero;

  double? get _aspect {
    final rect = cropRect;
    return _ratio.aspect(portrait: rect.height > rect.width);
  }

  void beginCrop(CropHandle handle) {
    _cropHandle = handle;
    _cropStart = cropRect;
    controller.beginChange();
  }

  /// [viewDelta] is how far the pointer has moved since [beginCrop].
  void dragCropBy(Offset viewDelta) {
    final handle = _cropHandle;
    if (handle == null) {
      return;
    }
    final delta = viewDelta / fit.scale;
    final next = dragCrop(
      _cropStart,
      handle,
      delta,
      fullRect,
      aspect: _aspect,
      minSize: math.max(24, 48 / fit.scale),
    );
    controller.update(document.copyWith(crop: _normalizedCrop(next)));
  }

  void endCrop() {
    _cropHandle = null;
    controller.commitChange();
  }

  Rect? _normalizedCrop(Rect rect) {
    final full = fullRect;
    const slack = 0.5;
    if ((rect.left - full.left).abs() < slack &&
        (rect.top - full.top).abs() < slack &&
        (rect.right - full.right).abs() < slack &&
        (rect.bottom - full.bottom).abs() < slack) {
      return null;
    }
    return rect;
  }

  /// Fixes the crop to [ratio]; choosing the same one again turns it
  /// between landscape and portrait.
  void setRatio(CropRatio ratio) {
    final current = cropRect;
    if (ratio == CropRatio.free) {
      _ratio = ratio;
      notifyListeners();
      return;
    }
    var portrait = current.height > current.width;
    if (ratio == _ratio && ratio != CropRatio.square) {
      portrait = !portrait;
    }
    final aspect = ratio.aspect(portrait: portrait)!;
    final bounds = ratio == _ratio && ratio != CropRatio.square
        ? fullRect
        : current;
    final fitted = fitAspect(bounds, aspect);
    final moved = clampRect(
      fitted.shift(current.center - fitted.center),
      fullRect,
    );
    _ratio = ratio;
    controller.commit(document.copyWith(crop: _normalizedCrop(moved)));
  }

  /// Turns the picture a quarter turn clockwise.
  void rotateClockwise() {
    final turned = turnedSize;
    controller.commit(
      document.copyWith(
        quarterTurns: (document.quarterTurns + 1) % 4,
        crop: rotateCropClockwise(document.crop, turned),
      ),
    );
    _pan = Offset.zero;
    _zoom = 1;
  }

  /// Takes back the turn and the crop (marks stay).
  void resetCrop() {
    _ratio = CropRatio.free;
    controller.commit(document.copyWith(quarterTurns: 0, crop: null));
  }

  bool get canResetCrop => document.quarterTurns != 0 || document.crop != null;

  /// Nudges the crop with the keyboard: [delta] in picture pixels moves it;
  /// with [resize] the bottom-right corner moves instead.
  void nudgeCrop(Offset delta, {bool resize = false}) {
    final start = cropRect;
    beginCrop(resize ? CropHandle.bottomRight : CropHandle.move);
    _cropStart = start;
    dragCropBy(delta * fit.scale);
    endCrop();
  }

  void undo() => controller.undo();
  void redo() => controller.redo();
}
