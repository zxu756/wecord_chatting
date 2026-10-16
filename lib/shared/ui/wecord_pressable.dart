import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/motion.dart';

/// Builds a pressable's look from its interaction [states] (hovered,
/// focused, pressed, disabled, selected).
typedef PressableBuilder =
    Widget Function(BuildContext context, Set<WidgetState> states);

/// The interaction core of WeCord controls, instead of InkWell: a pointer
/// cursor and hover state on desktop and web, a focus ring for keyboards,
/// Enter/Space activation, a springy press scale on touch, and button
/// semantics. No ripple.
class WeCordPressable extends StatefulWidget {
  const WeCordPressable({
    required this.builder,
    this.onPressed,
    this.onLongPress,
    this.shape = const StadiumBorder(),
    this.pressedScale = 0.97,
    this.selected = false,
    this.semanticLabel,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
    this.toggled,
    this.excludeSemantics = false,
    super.key,
  });

  final PressableBuilder builder;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// The outline the focus ring follows.
  final OutlinedBorder shape;

  /// Scale while pressed; 1 turns the effect off.
  final double pressedScale;

  /// Adds [WidgetState.selected] and selected semantics.
  final bool selected;

  final String? semanticLabel;

  /// Shown on hover and long press (where there is no [onLongPress]).
  final String? tooltip;

  final FocusNode? focusNode;
  final bool autofocus;

  /// For switches: the on/off state announced to screen readers.
  final bool? toggled;

  /// Whether to hide the child's own semantics behind [semanticLabel].
  final bool excludeSemantics;

  bool get enabled => onPressed != null || onLongPress != null;

  @override
  State<WeCordPressable> createState() => _WeCordPressableState();
}

class _WeCordPressableState extends State<WeCordPressable> {
  var _hovered = false;
  var _focused = false;
  var _pressed = false;

  Set<WidgetState> get _states => {
    if (!widget.enabled) WidgetState.disabled,
    if (_hovered) WidgetState.hovered,
    if (_focused) WidgetState.focused,
    if (_pressed) WidgetState.pressed,
    if (widget.selected) WidgetState.selected,
  };

  void _setPressed(bool value) {
    if (_pressed != value && mounted) {
      setState(() => _pressed = value);
    }
  }

  @override
  void didUpdateWidget(WeCordPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _pressed = false;
      _hovered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = widget.enabled;
    final spring = WeCordMotion.snappy;
    final reduceMotion = WeCordMotion.reduceMotion(context);

    Widget result = widget.builder(context, _states);

    result = AnimatedScale(
      scale: _pressed && !reduceMotion ? widget.pressedScale : 1,
      duration: spring.duration,
      curve: spring.curve,
      child: result,
    );

    if (_focused) {
      result = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: widget.shape.copyWith(
            side: BorderSide(
              color: tokens.colors.accent,
              width: 2,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
          ),
        ),
        child: result,
      );
    }

    result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: widget.onPressed,
      onLongPress: widget.onLongPress,
      excludeFromSemantics: true,
      child: result,
    );

    result = FocusableActionDetector(
      enabled: enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: result,
    );

    result = Semantics(
      button: widget.toggled == null,
      toggled: widget.toggled,
      enabled: enabled,
      selected: widget.selected ? true : null,
      label: widget.semanticLabel,
      excludeSemantics: widget.excludeSemantics,
      onTap: widget.onPressed,
      onLongPress: widget.onLongPress,
      child: result,
    );

    final tooltip = widget.tooltip;
    if (tooltip != null && tooltip.isNotEmpty) {
      result = Tooltip(message: tooltip, child: result);
    }
    return result;
  }
}
