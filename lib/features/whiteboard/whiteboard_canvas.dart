import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wecord/features/whiteboard/whiteboard_controller.dart';
import 'package:wecord/features/whiteboard/whiteboard_geometry.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_painter.dart';

enum _Gesture { none, draw, pan, pinch, move, resize, marquee, tool }

/// The drawing surface: draws the board and turns touch, mouse, trackpad and
/// pen into the controller's actions.
///
///  * a finger or the mouse draws with the pen, highlighter, eraser and shape
///    tools; two fingers pinch and pan at any time;
///  * once a pen (Apple Pencil) has been used, fingers only move the view, so
///    a resting palm does not draw; the pen's pressure shapes the line;
///  * a trackpad pans with two fingers and zooms by pinching; a mouse wheel
///    pans, with Ctrl or Cmd it zooms; the middle or right button pans;
///  * with the select tool, a drag on an element moves it, on its handle
///    resizes it, on empty space draws a selection rectangle (a finger pans).
class WhiteboardCanvas extends StatefulWidget {
  const WhiteboardCanvas({
    required this.controller,
    required this.palette,
    this.onPicture,
    super.key,
  });

  final WhiteboardController controller;
  final WhiteboardPalette palette;

  /// Asks the page to pick a picture (used by the keyboard paste of the
  /// image tool).
  final VoidCallback? onPicture;

  static const surfaceKey = ValueKey('whiteboard-surface');
  static const editFieldKey = ValueKey('whiteboard-edit-field');

  @override
  State<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends State<WhiteboardCanvas> {
  final _focus = FocusNode(debugLabel: 'whiteboard');
  final _editFocus = FocusNode(debugLabel: 'whiteboard edit');
  final _editController = TextEditingController();
  String? _editingFor;

  final _pointers = <int, Offset>{};
  _Gesture _gesture = _Gesture.none;
  int? _primary;
  Offset? _downScreen;
  var _moved = false;
  Offset? _dragStartBoard;

  // Pinch.
  double _pinchStartDistance = 1;
  Offset _pinchStartFocal = Offset.zero;
  WhiteboardView _pinchStartView = const WhiteboardView();

  // Trackpad.
  WhiteboardView _panZoomStartView = const WhiteboardView();

  // Double tap.
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastTapAtPoint = Offset.zero;

  var _fitted = false;

  WhiteboardController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onController);
  }

  @override
  void didUpdateWidget(WhiteboardCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    _focus.dispose();
    _editFocus.dispose();
    _editController.dispose();
    super.dispose();
  }

  void _onController() {
    if (!_fitted &&
        c.loadState == WhiteboardLoadState.ready &&
        !c.viewport.isEmpty) {
      _fitted = true;
      c.fitToContent();
    }
    final editing = c.editingId;
    if (editing != _editingFor) {
      _editingFor = editing;
      if (editing != null) {
        final element = c.engine.elementById(editing);
        _editController.text = element?.text ?? '';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && c.editingId == editing) {
            _editFocus.requestFocus();
          }
        });
      } else {
        _focus.requestFocus();
      }
    }
  }

  // ------------------------------------------------------------ pointers --

  bool _isStylus(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus ||
      e.kind == PointerDeviceKind.invertedStylus;

  double? _pressureOf(PointerEvent e) {
    if (!_isStylus(e)) {
      return null;
    }
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) {
      return 0.5;
    }
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  void _down(PointerDownEvent e) {
    _focus.requestFocus();
    if (c.editingId != null) {
      c.finishEditing();
    }
    if (_isStylus(e)) {
      c.stylusSeen = true;
    }
    _pointers[e.pointer] = e.localPosition;

    if (_pointers.length == 2 && e.kind == PointerDeviceKind.touch) {
      _startPinch();
      return;
    }
    if (_pointers.length > 1) {
      return;
    }
    _primary = e.pointer;
    _downScreen = e.localPosition;
    _moved = false;
    final board = c.toBoard(e.localPosition);
    _dragStartBoard = board;

    final panButton =
        e.buttons & (kMiddleMouseButton | kSecondaryMouseButton) != 0;
    final fingerOnly = e.kind == PointerDeviceKind.touch && c.stylusSeen;
    if (panButton || fingerOnly || c.tool == WhiteboardTool.hand) {
      _gesture = _Gesture.pan;
      return;
    }
    switch (c.tool) {
      case WhiteboardTool.pen:
      case WhiteboardTool.highlighter:
        _gesture = _Gesture.draw;
        c.beginStroke(board, pressure: _pressureOf(e), kind: e.kind);
      case WhiteboardTool.eraser:
        _gesture = _Gesture.draw;
        c.beginErase(board);
      case WhiteboardTool.shape:
        _gesture = _Gesture.draw;
        c.beginShape(board);
      case WhiteboardTool.sticky:
      case WhiteboardTool.text:
        _gesture = _Gesture.tool;
      case WhiteboardTool.image:
        _gesture = _Gesture.pan;
      case WhiteboardTool.select:
        _startSelectGesture(e, board);
      case WhiteboardTool.hand:
        _gesture = _Gesture.pan;
    }
  }

  void _startSelectGesture(PointerDownEvent e, Offset board) {
    final handle = c.handleAt(board);
    if (handle != null) {
      _gesture = _Gesture.resize;
      c.beginResize(handle);
      return;
    }
    final additive = HardwareKeyboard.instance.isShiftPressed;
    if (c.pointOnSelection(board) && !additive) {
      _gesture = _Gesture.move;
      c.beginMove();
      return;
    }
    final hit = c.hitAt(board);
    if (hit != null) {
      if (additive) {
        c.tapSelect(board, additive: true);
        _gesture = _Gesture.none;
      } else {
        c.select([hit.id]);
        _gesture = _Gesture.move;
        c.beginMove();
      }
      return;
    }
    if (e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus) {
      // A finger on empty space pans; a tap clears the selection on lift.
      _gesture = _Gesture.pan;
    } else {
      _gesture = _Gesture.marquee;
      c.beginMarquee(board);
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) {
      return;
    }
    _pointers[e.pointer] = e.localPosition;
    if (_gesture == _Gesture.pinch) {
      _updatePinch();
      return;
    }
    if (e.pointer != _primary) {
      return;
    }
    final down = _downScreen;
    if (down != null && (e.localPosition - down).distance > 6) {
      _moved = true;
    }
    final board = c.toBoard(e.localPosition);
    c.pointerMoved(board);
    switch (_gesture) {
      case _Gesture.draw:
        switch (c.tool) {
          case WhiteboardTool.pen:
          case WhiteboardTool.highlighter:
            for (final sample in _samples(e)) {
              c.extendStroke(c.toBoard(sample.$1), pressure: sample.$2);
            }
          case WhiteboardTool.eraser:
            c.eraseAt(board);
          case WhiteboardTool.shape:
            c.updateShape(board);
          default:
            break;
        }
      case _Gesture.pan:
        c.setView(c.view.panned(e.localDelta));
      case _Gesture.move:
        final start = _dragStartBoard;
        if (start != null) {
          c.moveBy(board - start);
        }
      case _Gesture.resize:
        c.resizeTo(board);
      case _Gesture.marquee:
        c.updateMarquee(board);
      case _Gesture.tool:
      case _Gesture.pinch:
      case _Gesture.none:
        break;
    }
  }

  /// The points of a move event. (Flutter delivers one event per frame; the
  /// pen's single sample is used as is.)
  List<(Offset, double?)> _samples(PointerMoveEvent e) => [
    (e.localPosition, _pressureOf(e)),
  ];

  void _up(PointerUpEvent e) {
    final wasPrimary = e.pointer == _primary;
    _pointers.remove(e.pointer);
    if (_gesture == _Gesture.pinch) {
      if (_pointers.length < 2) {
        _gesture = _Gesture.none;
        _primary = null;
      }
      return;
    }
    if (!wasPrimary) {
      return;
    }
    final board = c.toBoard(e.localPosition);
    switch (_gesture) {
      case _Gesture.draw:
        switch (c.tool) {
          case WhiteboardTool.pen:
          case WhiteboardTool.highlighter:
            c.endStroke();
          case WhiteboardTool.eraser:
            c.endErase();
          case WhiteboardTool.shape:
            c.endShape();
          default:
            break;
        }
      case _Gesture.move:
        c.endMove();
        if (!_moved) {
          _handleTap(board, e.localPosition);
        }
      case _Gesture.resize:
        c.endResize();
      case _Gesture.marquee:
        if (_moved) {
          c.endMarquee(additive: HardwareKeyboard.instance.isShiftPressed);
        } else {
          c.endMarquee();
          c.clearSelection();
        }
      case _Gesture.pan:
        if (!_moved && c.tool == WhiteboardTool.select) {
          _handleTap(board, e.localPosition);
        }
      case _Gesture.tool:
        if (!_moved) {
          // The element is made first, then the tool goes back to Select so
          // the person can type straight away.
          final sticky = c.tool == WhiteboardTool.sticky;
          final created = sticky ? c.addSticky(board) : c.addText(board);
          if (created != null) {
            c.returnToSelect();
          }
        }
      case _Gesture.pinch:
      case _Gesture.none:
        break;
    }
    _gesture = _Gesture.none;
    _primary = null;
  }

  void _cancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (e.pointer == _primary || _gesture == _Gesture.pinch) {
      switch (_gesture) {
        case _Gesture.draw:
          c
            ..cancelStroke()
            ..endErase()
            ..endShape();
        case _Gesture.move:
          c.endMove();
        case _Gesture.resize:
          c.endResize();
        case _Gesture.marquee:
          c.endMarquee();
        default:
          break;
      }
      if (_pointers.length < 2) {
        _gesture = _Gesture.none;
        _primary = null;
      }
    }
  }

  void _handleTap(Offset board, Offset screen) {
    final now = DateTime.now();
    final isDouble =
        now.difference(_lastTapAt) < const Duration(milliseconds: 350) &&
        (screen - _lastTapAtPoint).distance < 24;
    _lastTapAt = now;
    _lastTapAtPoint = screen;
    final hit = c.hitAt(board);
    if (hit == null) {
      c.clearSelection();
      return;
    }
    if (isDouble &&
        (hit.kind == WhiteboardKind.sticky || hit.kind == WhiteboardKind.text)) {
      c.beginEditing(hit.id);
    } else {
      c.select([hit.id]);
    }
  }

  // --------------------------------------------------------------- pinch --

  void _startPinch() {
    // Whatever one finger had begun is dropped: two fingers only move the
    // view.
    switch (_gesture) {
      case _Gesture.draw:
        c
          ..cancelStroke()
          ..endErase()
          ..endShape();
      case _Gesture.move:
        c.endMove();
      case _Gesture.resize:
        c.endResize();
      case _Gesture.marquee:
        c.endMarquee();
      default:
        break;
    }
    _gesture = _Gesture.pinch;
    final points = _pointers.values.toList();
    _pinchStartDistance = math.max(1, (points[0] - points[1]).distance);
    _pinchStartFocal = (points[0] + points[1]) / 2;
    _pinchStartView = c.view;
  }

  void _updatePinch() {
    if (_pointers.length < 2) {
      return;
    }
    final points = _pointers.values.take(2).toList();
    final distance = math.max(1, (points[0] - points[1]).distance);
    final focal = (points[0] + points[1]) / 2;
    final scale = (_pinchStartView.scale * distance / _pinchStartDistance)
        .clamp(WhiteboardView.minScale, WhiteboardView.maxScale);
    final anchor = _pinchStartView.toBoard(_pinchStartFocal);
    c.setView(WhiteboardView(scale: scale, offset: focal - anchor * scale));
  }

  // ------------------------------------------------- trackpad and wheel --

  void _panZoomStart(PointerPanZoomStartEvent e) {
    _panZoomStartView = c.view;
  }

  void _panZoomUpdate(PointerPanZoomUpdateEvent e) {
    final start = _panZoomStartView;
    final scale = (start.scale * e.scale).clamp(
      WhiteboardView.minScale,
      WhiteboardView.maxScale,
    );
    final anchor = start.toBoard(e.localPosition);
    c.setView(
      WhiteboardView(
        scale: scale,
        offset: e.localPosition - anchor * scale + e.pan,
      ),
    );
  }

  void _signal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) {
      return;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      final factor = math.exp(-e.scrollDelta.dy / 300);
      c.setView(c.view.zoomed(factor, e.localPosition));
    } else {
      c.setView(c.view.panned(-e.scrollDelta));
    }
  }

  // ------------------------------------------------------------ keyboard --

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || c.editingId != null) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final command = keys.isMetaPressed || keys.isControlPressed;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      c.deleteSelection();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      c.clearSelection();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyZ) {
      keys.isShiftPressed ? c.redo() : c.undo();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyY) {
      c.redo();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyA) {
      c.selectAll();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyD) {
      c.duplicateSelection();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add) {
      c.setView(c.view.zoomed(1.2, c.viewport.center(Offset.zero)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus) {
      c.setView(c.view.zoomed(1 / 1.2, c.viewport.center(Offset.zero)));
      return KeyEventResult.handled;
    }
    final arrows = {
      LogicalKeyboardKey.arrowLeft: const Offset(-1, 0),
      LogicalKeyboardKey.arrowRight: const Offset(1, 0),
      LogicalKeyboardKey.arrowUp: const Offset(0, -1),
      LogicalKeyboardKey.arrowDown: const Offset(0, 1),
    };
    final step = arrows[key];
    if (step != null && c.selection.isNotEmpty) {
      c.beginMove();
      c.moveBy(step * (keys.isShiftPressed ? 10 : 1));
      c.endMove();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (c.viewport != size) {
          c.viewport = size;
          if (!_fitted && c.loadState == WhiteboardLoadState.ready) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_fitted) {
                _fitted = true;
                c.fitToContent();
              }
            });
          }
        }
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _key,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  key: WhiteboardCanvas.surfaceKey,
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: _cancel,
                  onPointerHover: (e) => c.pointerMoved(c.toBoard(e.localPosition)),
                  onPointerSignal: _signal,
                  onPointerPanZoomStart: _panZoomStart,
                  onPointerPanZoomUpdate: _panZoomUpdate,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: WhiteboardPainter(
                        controller: c,
                        palette: widget.palette,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: c,
                builder: (context, _) => _editor(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _editor(BuildContext context) {
    final id = c.editingId;
    final element = id == null ? null : c.engine.elementById(id);
    if (element == null) {
      return const SizedBox.shrink();
    }
    final view = c.view;
    final box = element.box;
    final topLeft = view.toScreen(box.topLeft);
    final fontSize = (element.kind == WhiteboardKind.sticky
            ? element.number('fs', 18)
            : element.fontSize) *
        view.scale;
    final isSticky = element.kind == WhiteboardKind.sticky;
    final style = TextStyle(
      fontSize: fontSize,
      height: 1.3,
      color: isSticky ? const Color(0xFF1B1B1F) : Color(element.color),
    );
    final field = TextField(
      key: WhiteboardCanvas.editFieldKey,
      controller: _editController,
      focusNode: _editFocus,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      style: style,
      cursorColor: Theme.of(context).colorScheme.primary,
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: (text) {
        final measured = isSticky
            ? null
            : measureWhiteboardText(text, element.fontSize);
        c.setEditingText(text, measured: measured);
      },
    );
    if (isSticky) {
      return Positioned(
        left: topLeft.dx + 10 * view.scale,
        top: topLeft.dy + 8 * view.scale,
        width: math.max(40, (box.width - 20) * view.scale),
        height: math.max(30, (box.height - 16) * view.scale),
        child: field,
      );
    }
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: math.max(120, box.width * view.scale + 40),
      child: field,
    );
  }
}
