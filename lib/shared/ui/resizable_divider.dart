import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/motion.dart';

/// Which edge of its panel a [ResizableDivider] sits on.
enum ResizableDividerEdge {
  /// The right edge of a panel on the left (a sidebar): dragging right
  /// widens it.
  end,

  /// The left edge of a panel on the right (members, profile): dragging
  /// left widens it.
  start,
}

/// The handle on a column's edge that resizes it: an invisible
/// [hitWidth]-wide strip with the column-resize cursor, where a thin accent
/// line shows on hover, while dragging and when focused.
///
/// Dragging reports every width through [onChanged] (a little past the
/// range with resistance); on release the width springs back into range
/// and [onChangeEnd] keeps it. Double-click (or Enter) resets to
/// [defaultValue]. With [collapseBelow], dragging narrower than it snaps
/// the panel shut: the live width is then 0, and a final 0 means closed.
/// Keyboard: ←/→ move the edge by [step], Home/End go to [min]/[max]. It
/// reads as a slider to screen readers. Springs go still with reduced
/// motion.
///
/// Place it over the edge, centred on it (e.g. a [Positioned] of width
/// [hitWidth] in a [Stack] around the row).
class ResizableDivider extends StatefulWidget {
  const ResizableDivider({
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.onChanged,
    required this.onChangeEnd,
    required this.semanticLabel,
    this.edge = ResizableDividerEdge.end,
    this.collapseBelow,
    this.step = 16,
    this.tooltip,
    this.valueLabel,
    this.focusNode,
    super.key,
  });

  /// Width of the strip that takes the pointer.
  static const hitWidth = 8.0;

  /// The panel's width now.
  final double value;
  final double min;

  /// The widest the panel may get here; below [min] counts as [min].
  final double max;
  final double defaultValue;

  /// Every width while dragging or springing (0 while closing).
  final ValueChanged<double> onChanged;

  /// The width to keep (0 to close the panel).
  final ValueChanged<double> onChangeEnd;
  final ResizableDividerEdge edge;

  /// Dragging narrower than this closes the panel; null never closes it.
  final double? collapseBelow;

  /// How far one arrow key press moves the edge.
  final double step;

  /// What the slider resizes, for screen readers ("Sidebar width").
  final String semanticLabel;

  /// Shown on hover, e.g. "Drag to resize · double-click to reset".
  final String? tooltip;

  /// The width as read aloud; "292" by default.
  final String Function(double width)? valueLabel;

  final FocusNode? focusNode;

  @override
  State<ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<ResizableDivider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this)
    ..addListener(_onTick)
    ..addStatusListener(_onStatus);

  var _hovered = false;
  var _focused = false;
  var _dragging = false;

  /// What the panel shows while dragging or springing; null at rest.
  double? _shown;
  double _from = 0;
  double _to = 0;
  Curve _curve = Curves.linear;

  /// Kept through [ResizableDivider.onChangeEnd] when the spring settles.
  double? _settleTo;

  double _dragStartValue = 0;
  double _dragStartX = 0;
  double _dragRaw = 0;
  var _wouldCollapse = false;

  double get _max => math.max(widget.min, widget.max);

  double get _sign => widget.edge == ResizableDividerEdge.end ? 1 : -1;

  /// A width just kept from the keyboard, until the panel shows it, so
  /// quick key repeats add up.
  double? _kept;

  double get _current => _shown ?? _kept ?? widget.value;

  @override
  void didUpdateWidget(ResizableDivider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _kept = null;
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  void _emit(double width) {
    _shown = width;
    widget.onChanged(width);
  }

  void _onTick() {
    _emit(lerpDouble(_from, _to, _curve.transform(_motion.value))!);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      final settleTo = _settleTo;
      if (settleTo != null) {
        _settleTo = null;
        _keep(settleTo);
      }
    }
  }

  /// Springs from what shows now to [target]; keeps [settle] at the end.
  void _animate(double target, WeCordSpring spring, {double? settle}) {
    _settleTo = settle;
    final duration = spring.durationOf(context);
    if (duration == Duration.zero) {
      _motion.stop();
      _settleTo = null;
      if (settle != null) {
        _keep(settle);
      } else {
        _emit(target);
      }
      return;
    }
    _from = _current;
    _to = target;
    _curve = spring.curve;
    _motion.duration = duration;
    _motion.forward(from: 0);
  }

  void _keep(double width) {
    _motion.stop();
    _settleTo = null;
    _shown = null;
    widget.onChangeEnd(width);
  }

  /// Springs to [target] and keeps it.
  void _settle(double target) {
    if (!_motion.isAnimating && (_current - target).abs() < 0.5) {
      _keep(target);
      return;
    }
    _animate(
      target,
      target == 0 ? WeCordMotion.smooth : WeCordMotion.snappy,
      settle: target,
    );
  }

  /// Past the range the edge follows the pointer less and less, up to 16.
  double _rubberBand(double raw) {
    double resist(double over) => 16 * over / (over + 48);
    if (raw > _max) {
      return _max + resist(raw - _max);
    }
    if (raw < widget.min) {
      return widget.min - resist(widget.min - raw);
    }
    return raw;
  }

  void _onDragStart(DragStartDetails details) {
    _motion.stop();
    _settleTo = null;
    _dragStartValue = _current;
    _dragStartX = details.globalPosition.dx;
    _dragRaw = _dragStartValue;
    _wouldCollapse = _dragStartValue == 0;
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragRaw =
        _dragStartValue + (details.globalPosition.dx - _dragStartX) * _sign;
    final collapseBelow = widget.collapseBelow;
    final collapse = collapseBelow != null && _dragRaw < collapseBelow;
    final target = collapse ? 0.0 : _rubberBand(_dragRaw);
    if (collapse != _wouldCollapse) {
      // A gentle snap shut, or back open.
      _wouldCollapse = collapse;
      WeCordHaptics.selection();
      _animate(target, WeCordMotion.smooth);
    } else if (_motion.isAnimating) {
      _to = target;
    } else {
      _emit(target);
    }
  }

  void _onDragEnd([Object? _]) {
    if (!_dragging) {
      return;
    }
    setState(() => _dragging = false);
    _settle(_wouldCollapse ? 0 : _dragRaw.clamp(widget.min, _max).toDouble());
  }

  void _reset() => _settle(widget.defaultValue.clamp(widget.min, _max));

  void _set(double width) {
    final kept = width.clamp(widget.min, _max).toDouble();
    _keep(kept);
    _kept = kept;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final value = _current;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _set(value - widget.step * _sign);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _set(value + widget.step * _sign);
    } else if (key == LogicalKeyboardKey.home) {
      _set(widget.min);
    } else if (key == LogicalKeyboardKey.end) {
      _set(_max);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _set(widget.defaultValue);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String _label(double width) =>
      widget.valueLabel?.call(width) ?? '${width.round()}';

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final value = widget.value.clamp(widget.min, _max).toDouble();
    final active = _hovered || _dragging || _focused;
    final wider = math.min(value + widget.step, _max);
    final narrower = math.max(value - widget.step, widget.min);

    Widget result = Center(
      child: AnimatedContainer(
        duration: WeCordMotion.quick,
        curve: WeCordMotion.standard,
        width: _dragging || _focused ? 3 : 2,
        decoration: BoxDecoration(
          color: c.accent.withValues(alpha: active ? 1 : 0),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

    result = MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        // Measured from the press, so the slop counts toward the width.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _onDragEnd,
        onDoubleTap: _reset,
        child: SizedBox(width: ResizableDivider.hitWidth, child: result),
      ),
    );

    result = Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: result,
    );

    result = Semantics(
      slider: true,
      focusable: true,
      focused: _focused,
      label: widget.semanticLabel,
      hint: widget.tooltip,
      value: _label(value),
      increasedValue: _label(wider),
      decreasedValue: _label(narrower),
      onIncrease: value < _max ? () => _set(wider) : null,
      onDecrease: value > widget.min ? () => _set(narrower) : null,
      child: result,
    );

    // Hidden by the press that starts a drag.
    final tooltip = widget.tooltip;
    if (tooltip != null && tooltip.isNotEmpty) {
      result = Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 600),
        child: result,
      );
    }
    return result;
  }
}
