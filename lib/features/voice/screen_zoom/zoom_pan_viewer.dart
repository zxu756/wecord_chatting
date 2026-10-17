import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The most a shared screen zooms in.
const maxScreenZoom = 8.0;

/// How far a double-tap on an unzoomed screen zooms in.
const doubleTapZoom = 2.5;

/// One step of the zoom buttons and the +/- keys.
const zoomStep = 1.5;

/// Lets people zoom into [child] (a shared screen) and look around: pinch
/// or scroll the wheel to zoom, drag to pan, double-tap or double-click to
/// zoom back out (or in, on a screen that isn't zoomed), and buttons and
/// keys (+ − 0 and the arrows) for those who can't pinch.
///
/// [onFocus] adds the "Focus this tile" button, [focused] says it is on.
class ZoomPanViewer extends StatefulWidget {
  const ZoomPanViewer({
    required this.child,
    this.onFocus,
    this.focused = false,
    this.onZoomedChanged,
    this.controller,
    super.key,
  });

  final Widget child;

  /// Spotlights this tile (or puts it back); no button without it.
  final VoidCallback? onFocus;
  final bool focused;

  /// Called when the screen gets zoomed in (true) or back to normal, so the
  /// page around it can stop scrolling while a finger pans the picture.
  final ValueChanged<bool>? onZoomedChanged;

  /// For tests and callers that want to see or set the zoom.
  final TransformationController? controller;

  @override
  State<ZoomPanViewer> createState() => _ZoomPanViewerState();
}

class _ZoomPanViewerState extends State<ZoomPanViewer>
    with SingleTickerProviderStateMixin {
  late final TransformationController _transform =
      widget.controller ?? TransformationController();
  late final AnimationController _animation = AnimationController(vsync: this);
  Animation<Matrix4>? _tween;
  final _viewerKey = GlobalKey();
  Offset _doubleTapAt = Offset.zero;
  var _zoomed = false;
  var _keyboardFocused = false;

  double get _scale => _transform.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    _animation.addListener(() {
      final tween = _tween;
      if (tween != null) {
        _transform.value = tween.value;
      }
    });
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    if (_zoomed) {
      // The page stops waiting for a finger on a picture that is gone.
      final callback = widget.onZoomedChanged;
      scheduleMicrotask(() => callback?.call(false));
    }
    if (widget.controller == null) {
      _transform.dispose();
    }
    _animation.dispose();
    super.dispose();
  }

  void _onTransform() {
    final zoomed = _scale > 1.01;
    if (zoomed != _zoomed) {
      _zoomed = zoomed;
      widget.onZoomedChanged?.call(zoomed);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Size get _size {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null || !box.hasSize ? Size.zero : box.size;
  }

  /// Zooms to [scale] around [focal] (a point in the viewer), keeping that
  /// point where it is, and animates there.
  void _zoomTo(double scale, Offset focal) {
    final size = _size;
    final target = scale.clamp(1.0, maxScreenZoom);
    final Matrix4 end;
    if (target <= 1.0 || size.isEmpty) {
      end = Matrix4.identity();
    } else {
      // The point of the picture under [focal] now.
      final scenePoint = _transform.toScene(focal);
      var x = focal.dx - scenePoint.dx * target;
      var y = focal.dy - scenePoint.dy * target;
      // Never show beyond the picture's edges.
      x = x.clamp(size.width - size.width * target, 0.0);
      y = y.clamp(size.height - size.height * target, 0.0);
      end = Matrix4.identity()
        ..setEntry(0, 0, target)
        ..setEntry(1, 1, target)
        ..setEntry(0, 3, x)
        ..setEntry(1, 3, y);
    }
    _animateTo(end);
  }

  void _animateTo(Matrix4 end) {
    if (WeCordMotion.reduceMotion(context)) {
      _transform.value = end;
      return;
    }
    _tween = Matrix4Tween(begin: _transform.value, end: end).animate(
      CurvedAnimation(parent: _animation, curve: WeCordMotion.smooth.curve),
    );
    _animation
      ..duration = WeCordMotion.smooth.duration
      ..forward(from: 0);
  }

  void zoomIn() => _zoomTo(_scale * zoomStep, _center);
  void zoomOut() => _zoomTo(_scale / zoomStep, _center);
  void reset() => _zoomTo(1, _center);

  Offset get _center => Offset(_size.width / 2, _size.height / 2);

  void _pan(double dx, double dy) {
    if (!_zoomed) {
      return;
    }
    final size = _size;
    final scale = _scale;
    final moved = _transform.value.clone()
      ..leftTranslateByDouble(-dx, -dy, 0, 1);
    final x = moved.entry(0, 3).clamp(size.width - size.width * scale, 0.0);
    final y = moved.entry(1, 3).clamp(size.height - size.height * scale, 0.0);
    moved
      ..setEntry(0, 3, x)
      ..setEntry(1, 3, y);
    _transform.value = moved;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final character = event.character;
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd ||
        character == '+') {
      zoomIn();
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      zoomOut();
    } else if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0 ||
        key == LogicalKeyboardKey.escape && _zoomed) {
      reset();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (!_zoomed) return KeyEventResult.ignored;
      _pan(-40, 0);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (!_zoomed) return KeyEventResult.ignored;
      _pan(40, 0);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (!_zoomed) return KeyEventResult.ignored;
      _pan(0, -40);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (!_zoomed) return KeyEventResult.ignored;
      _pan(0, 40);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final percent = (_scale * 100).round();
    final onFocus = widget.onFocus;

    return Semantics(
      container: true,
      customSemanticsActions: {
        CustomSemanticsAction(label: tr('Zoom in')): zoomIn,
        if (_zoomed) CustomSemanticsAction(label: tr('Zoom out')): zoomOut,
        if (_zoomed) CustomSemanticsAction(label: tr('Reset zoom')): reset,
      },
      child: Focus(
        onKeyEvent: _onKey,
        onFocusChange: (focused) => setState(
          () => _keyboardFocused =
              focused &&
              FocusManager.instance.highlightMode ==
                  FocusHighlightMode.traditional,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: const ValueKey('screen-zoom-surface'),
              behavior: HitTestBehavior.opaque,
              onDoubleTapDown: (details) =>
                  _doubleTapAt = details.localPosition,
              onDoubleTap: () {
                if (_zoomed) {
                  reset();
                } else {
                  _zoomTo(doubleTapZoom, _doubleTapAt);
                }
              },
              child: InteractiveViewer(
                key: _viewerKey,
                transformationController: _transform,
                minScale: 1,
                maxScale: maxScreenZoom,
                clipBehavior: Clip.hardEdge,
                onInteractionStart: (_) => _animation.stop(),
                child: widget.child,
              ),
            ),
            if (_keyboardFocused)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: c.accent, width: 2),
                    ),
                  ),
                ),
              ),
            if (_zoomed)
              Positioned(
                left: 8,
                top: 8,
                child: _ZoomPill(
                  key: const ValueKey('screen-zoom-pill'),
                  percent: percent,
                  onZoomIn: _scale >= maxScreenZoom - 0.01 ? null : zoomIn,
                  onZoomOut: zoomOut,
                  onReset: reset,
                ),
              ),
            if (onFocus != null)
              Positioned(
                right: 8,
                top: 8,
                child: _GlassIconButton(
                  key: const ValueKey('screen-focus-button'),
                  icon: widget.focused
                      ? Icons.close_fullscreen_rounded
                      : Icons.open_in_full_rounded,
                  tooltip: widget.focused
                      ? tr('Show everyone')
                      : tr('Focus this tile'),
                  selected: widget.focused,
                  onPressed: onFocus,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomPill extends StatelessWidget {
  const _ZoomPill({
    required this.percent,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    super.key,
  });

  final int percent;
  final VoidCallback? onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordGlass(
      borderRadius: BorderRadius.circular(WeCordRadii.pill),
      elevation: GlassElevation.flat,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GlassIconButton(
            key: const ValueKey('screen-zoom-out'),
            icon: Icons.remove_rounded,
            tooltip: tr('Zoom out'),
            onPressed: onZoomOut,
            bare: true,
          ),
          Semantics(
            liveRegion: true,
            label: tr('Zoom {percent}%', {'percent': percent}),
            child: ExcludeSemantics(
              child: Text(
                '$percent%',
                key: const ValueKey('screen-zoom-percent'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          _GlassIconButton(
            key: const ValueKey('screen-zoom-in'),
            icon: Icons.add_rounded,
            tooltip: tr('Zoom in'),
            onPressed: onZoomIn,
            bare: true,
          ),
          _GlassIconButton(
            key: const ValueKey('screen-zoom-reset'),
            icon: Icons.fit_screen_rounded,
            tooltip: tr('Reset zoom'),
            onPressed: onReset,
            bare: true,
          ),
        ],
      ),
    );
  }
}

/// A small round button over a shared screen: glass, or [bare] inside a
/// glass pill.
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.bare = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final button = WeCordPressable(
      semanticLabel: tooltip,
      tooltip: tooltip,
      excludeSemantics: true,
      selected: selected,
      shape: const CircleBorder(),
      pressedScale: 0.9,
      minTapSize: const Size.square(WeCordSizes.touchTarget),
      onPressed: onPressed,
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedOpacity(
          opacity: onPressed == null ? 0.4 : 1,
          duration: WeCordMotion.quick,
          child: AnimatedContainer(
            duration: WeCordMotion.quick,
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? c.ink
                  : c.ink.withValues(alpha: hovered ? 0.16 : 0),
            ),
            child: Icon(icon, size: 18, color: selected ? c.onInk : c.ink),
          ),
        );
      },
    );
    if (bare) {
      return button;
    }
    return WeCordGlass(
      borderRadius: BorderRadius.circular(WeCordRadii.pill),
      elevation: GlassElevation.flat,
      padding: const EdgeInsets.all(2),
      child: button,
    );
  }
}
