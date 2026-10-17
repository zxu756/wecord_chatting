import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wecord/features/photo_editor/crop_math.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';
import 'package:wecord/features/photo_editor/editor_render.dart';
import 'package:wecord/features/photo_editor/editor_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

enum _Mode { none, stroke, text, textHandle, viewport, crop }

/// The picture with its marks, and everything done to it with fingers, a
/// mouse or a trackpad: drawing and brushing, moving and turning text,
/// dragging crop handles, pinching and scrolling to zoom.
class EditorCanvas extends StatefulWidget {
  const EditorCanvas({
    required this.session,
    required this.onAddText,
    required this.onEditText,
    super.key,
  });

  final EditorSession session;

  /// A tap on an empty spot of the text tool: asks for new text there.
  final void Function(Offset viewPoint) onAddText;

  /// A second tap on the selected text.
  final void Function(TextOverlay item) onEditText;

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends State<EditorCanvas> {
  var _mode = _Mode.none;
  Offset _startFocal = Offset.zero;
  var _trackpad = false;
  final _focus = FocusNode(debugLabel: 'photo-editor-canvas');

  EditorSession get _s => widget.session;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  static const _handleReach = 28.0;
  static const _textHandleReach = 22.0;

  Offset? _textHandlePoint(TextOverlay item) {
    final corners = _s.textCornersInView(item);
    return corners[2];
  }

  Offset? _textDeletePoint(TextOverlay item) =>
      _s.textCornersInView(item).first;

  void _onScaleStart(ScaleStartDetails d) {
    final p = d.localFocalPoint;
    _startFocal = p;
    _trackpad = d.kind == PointerDeviceKind.trackpad;
    _focus.requestFocus();
    final tool = _s.tool;
    if (tool == EditorTool.crop) {
      final handle = cropHandleAt(_s.cropRectInView, p, reach: _handleReach);
      if (handle != null) {
        _mode = _Mode.crop;
        _s.beginCrop(handle);
      } else {
        _mode = _Mode.none;
      }
      return;
    }
    if (_trackpad) {
      _mode = _Mode.viewport;
      _s.beginPinch(p);
      return;
    }
    if (d.pointerCount >= 2) {
      final hit = tool == EditorTool.text ? _s.hitText(p) : null;
      if (hit != null) {
        _mode = _Mode.text;
        _s.beginTextGesture(hit, p);
      } else {
        _mode = _Mode.viewport;
        _s.beginPinch(p);
      }
      return;
    }
    switch (tool) {
      case EditorTool.draw || EditorTool.mosaic:
        _mode = _Mode.stroke;
        _s.beginStroke(p);
      case EditorTool.text:
        final selected = _s.selectedText;
        if (selected != null) {
          final handle = _textHandlePoint(selected);
          if (handle != null && (handle - p).distance <= _textHandleReach) {
            _mode = _Mode.textHandle;
            _s.beginTextGesture(selected, handle);
            return;
          }
        }
        final hit = _s.hitText(p);
        if (hit != null) {
          _mode = _Mode.text;
          _s.beginTextGesture(hit, p);
        } else if (_s.zoom > 1) {
          _mode = _Mode.viewport;
          _s.beginPinch(p);
        } else {
          _mode = _Mode.none;
        }
      case EditorTool.crop:
        break;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final p = d.localFocalPoint;
    switch (_mode) {
      case _Mode.stroke:
        _s.extendStroke(p);
      case _Mode.text:
        _s.updateTextGesture(p, scale: d.scale, rotation: d.rotation);
      case _Mode.textHandle:
        _s.updateTextHandle(p);
      case _Mode.viewport:
        _s.updatePinch(p, d.scale);
      case _Mode.crop:
        _s.dragCropBy(p - _startFocal);
      case _Mode.none:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    switch (_mode) {
      case _Mode.stroke:
        _s.endStroke();
      case _Mode.text || _Mode.textHandle:
        _s.endTextGesture();
      case _Mode.crop:
        _s.endCrop();
      case _Mode.viewport || _Mode.none:
        break;
    }
    _mode = _Mode.none;
  }

  void _onTapUp(TapUpDetails d) {
    final p = d.localPosition;
    _focus.requestFocus();
    switch (_s.tool) {
      case EditorTool.draw || EditorTool.mosaic:
        _s.dot(p);
      case EditorTool.text:
        final selected = _s.selectedText;
        if (selected != null) {
          final delete = _textDeletePoint(selected);
          if (delete != null && (delete - p).distance <= _textHandleReach) {
            _s.removeText(selected.id);
            return;
          }
        }
        final hit = _s.hitText(p);
        if (hit != null) {
          if (hit.id == _s.selectedTextId) {
            widget.onEditText(hit);
          } else {
            _s.selectText(hit.id);
          }
        } else if (_s.selectedTextId != null) {
          _s.selectText(null);
        } else {
          widget.onAddText(p);
        }
      case EditorTool.crop:
        break;
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScaleEvent) {
      // A trackpad pinch in the browser.
      GestureBinding.instance.pointerSignalResolver.register(event, (event) {
        event as PointerScaleEvent;
        _s.zoomAbout(event.localPosition, _s.zoom * event.scale);
      });
      return;
    }
    if (event is! PointerScrollEvent) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      event as PointerScrollEvent;
      final keys = HardwareKeyboard.instance;
      if (keys.isControlPressed || keys.isMetaPressed) {
        // Zoom about the pointer.
        _s.zoomAbout(
          event.localPosition,
          _s.zoom * math.exp(-event.scrollDelta.dy / 240),
        );
      } else {
        _s.panBy(-event.scrollDelta);
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final shift = keys.isShiftPressed;
    if (keys.isMetaPressed || keys.isControlPressed) {
      return KeyEventResult.ignored;
    }
    final step = shift ? 10.0 : 2.0;
    Offset? delta;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        delta = Offset(-step, 0);
      case LogicalKeyboardKey.arrowRight:
        delta = Offset(step, 0);
      case LogicalKeyboardKey.arrowUp:
        delta = Offset(0, -step);
      case LogicalKeyboardKey.arrowDown:
        delta = Offset(0, step);
      default:
        break;
    }
    if (_s.tool == EditorTool.crop && delta != null) {
      // Arrows move the crop; Alt + arrows resize it from the corner.
      _s.nudgeCrop(delta * 4 / _s.fit.scale, resize: keys.isAltPressed);
      return KeyEventResult.handled;
    }
    if (_s.tool == EditorTool.text && _s.selectedText != null) {
      if (delta != null) {
        _s.nudgeSelectedText(delta * 4 / _s.fit.scale);
        return KeyEventResult.handled;
      }
      switch (event.logicalKey) {
        case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
          _s.removeText(_s.selectedTextId!);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
          widget.onEditText(_s.selectedText!);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.equal || LogicalKeyboardKey.add:
          _s.scaleSelectedText(1.1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.minus:
          _s.scaleSelectedText(1 / 1.1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.bracketLeft:
          _s.rotateSelectedText(-math.pi / 36);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.bracketRight:
          _s.rotateSelectedText(math.pi / 36);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.escape:
          _s.selectText(null);
          return KeyEventResult.handled;
        default:
          break;
      }
    }
    return KeyEventResult.ignored;
  }

  MouseCursor _cursorFor(Offset? point) {
    if (_s.tool == EditorTool.crop && point != null) {
      final handle = cropHandleAt(_s.cropRectInView, point, reach: _handleReach);
      return switch (handle) {
        CropHandle.topLeft || CropHandle.bottomRight =>
          SystemMouseCursors.resizeUpLeftDownRight,
        CropHandle.topRight || CropHandle.bottomLeft =>
          SystemMouseCursors.resizeUpRightDownLeft,
        CropHandle.top || CropHandle.bottom => SystemMouseCursors.resizeUpDown,
        CropHandle.left || CropHandle.right =>
          SystemMouseCursors.resizeLeftRight,
        CropHandle.move => SystemMouseCursors.move,
        null => SystemMouseCursors.basic,
      };
    }
    if (_s.tool == EditorTool.draw || _s.tool == EditorTool.mosaic) {
      return SystemMouseCursors.precise;
    }
    if (_s.tool == EditorTool.text && point != null) {
      return _s.hitText(point) != null
          ? SystemMouseCursors.move
          : SystemMouseCursors.text;
    }
    return SystemMouseCursors.basic;
  }

  Offset? _hoverPoint;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        _s.setViewSize(constraints.biggest);
        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Semantics(
            container: true,
            image: true,
            label: tr(
              'Photo being edited. Draw with a finger, a mouse or a trackpad.',
            ),
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: MouseRegion(
                cursor: _cursorFor(_hoverPoint),
                onHover: (event) {
                  final before = _cursorFor(_hoverPoint);
                  _hoverPoint = event.localPosition;
                  if (_cursorFor(_hoverPoint) != before) {
                    setState(() {});
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  onTapUp: _onTapUp,
                  child: ClipRect(
                    child: CustomPaint(
                      size: constraints.biggest,
                      painter: EditorScenePainter(
                        session: _s,
                        handleColor: tokens.colors.accent,
                        chrome: Colors.white,
                        chromeShadow: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints the scene for the screen: the picture as it will be sent, the
/// crop overlay while cropping, the selection of a text.
class EditorScenePainter extends CustomPainter {
  EditorScenePainter({
    required this.session,
    required this.handleColor,
    required this.chrome,
    required this.chromeShadow,
  }) : super(repaint: session);

  final EditorSession session;
  final Color handleColor;
  final Color chrome;
  final Color chromeShadow;

  @override
  void paint(Canvas canvas, Size size) {
    final s = session;
    final document = s.document;
    final view = Offset.zero & size;
    canvas.save();
    canvas.clipRect(view);
    if (s.tool != EditorTool.crop) {
      canvas.clipRect(s.fit.regionInView);
    }
    canvas.transform(s.sourceToView.storage);
    paintEditorScene(
      canvas,
      s.assets,
      document,
      active: s.draftText ?? s.activeItem,
      skipText: s.editingText,
    );
    canvas.restore();

    if (s.tool == EditorTool.crop) {
      _paintCrop(canvas, view, s.cropRectInView, s.fit.regionInView);
    } else if (s.tool == EditorTool.text) {
      final selected = s.selectedText;
      if (selected != null && selected.id != s.editingText) {
        _paintSelection(canvas, s.textCornersInView(selected));
      }
    }
  }

  void _paintCrop(Canvas canvas, Rect view, Rect crop, Rect picture) {
    // Dim everything of the picture outside the crop.
    final dim = Path()
      ..addRect(picture)
      ..addRect(crop)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = const Color(0x99000000));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = chrome;
    canvas.drawRect(crop, line);
    // Thirds.
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..color = chrome.withValues(alpha: 0.55);
    for (var i = 1; i < 3; i++) {
      final x = crop.left + crop.width * i / 3;
      final y = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), thin);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), thin);
    }
    // Corner brackets and edge grips.
    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = chrome;
    final arm = math.min(22.0, math.min(crop.width, crop.height) / 3);
    void corner(Offset c, double dx, double dy) {
      canvas.drawLine(c, c + Offset(dx * arm, 0), bracket);
      canvas.drawLine(c, c + Offset(0, dy * arm), bracket);
    }

    corner(crop.topLeft, 1, 1);
    corner(crop.topRight, -1, 1);
    corner(crop.bottomLeft, 1, -1);
    corner(crop.bottomRight, -1, -1);
    final grip = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = chrome;
    final half = math.min(14.0, math.min(crop.width, crop.height) / 6);
    canvas.drawLine(
      Offset(crop.center.dx - half, crop.top),
      Offset(crop.center.dx + half, crop.top),
      grip,
    );
    canvas.drawLine(
      Offset(crop.center.dx - half, crop.bottom),
      Offset(crop.center.dx + half, crop.bottom),
      grip,
    );
    canvas.drawLine(
      Offset(crop.left, crop.center.dy - half),
      Offset(crop.left, crop.center.dy + half),
      grip,
    );
    canvas.drawLine(
      Offset(crop.right, crop.center.dy - half),
      Offset(crop.right, crop.center.dy + half),
      grip,
    );
  }

  void _paintSelection(Canvas canvas, List<Offset> corners) {
    final path = Path()..addPolygon(corners, true);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = chromeShadow,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = chrome,
    );
    // Bottom-right: grab to resize and turn. Top-left: delete.
    final grab = corners[2];
    canvas.drawCircle(grab, 11, Paint()..color = handleColor);
    canvas.drawCircle(
      grab,
      11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = chrome,
    );
    final arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawLine(grab + const Offset(-4, 4), grab + const Offset(4, -4), arrow);
    canvas.drawLine(grab + const Offset(0.5, -4), grab + const Offset(4, -4), arrow);
    canvas.drawLine(grab + const Offset(4, -0.5), grab + const Offset(4, -4), arrow);
    canvas.drawLine(grab + const Offset(-4, 0.5), grab + const Offset(-4, 4), arrow);
    canvas.drawLine(grab + const Offset(-0.5, 4), grab + const Offset(-4, 4), arrow);

    final remove = corners.first;
    canvas.drawCircle(remove, 11, Paint()..color = const Color(0xFF17171A));
    canvas.drawCircle(
      remove,
      11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = chrome,
    );
    canvas.drawLine(remove + const Offset(-3.5, -3.5), remove + const Offset(3.5, 3.5), arrow);
    canvas.drawLine(remove + const Offset(3.5, -3.5), remove + const Offset(-3.5, 3.5), arrow);
  }

  @override
  bool shouldRepaint(EditorScenePainter old) =>
      old.session != session ||
      old.handleColor != handleColor ||
      old.chrome != chrome;
}
