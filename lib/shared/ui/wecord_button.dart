import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/count_badge.dart';
import 'package:wecord/shared/ui/motion.dart';
import 'package:wecord/shared/ui/wecord_pressable.dart';

/// How a [WeCordButton] or [WeCordIconButton] is filled.
enum WeCordButtonVariant {
  /// Ink fill (inverted in dark): the one main action of a screen.
  primary,

  /// Accent fill: compose, send, join — actions that create something.
  accent,

  /// Quiet raised fill: secondary actions next to a primary one.
  secondary,

  /// No fill until hovered: toolbar and header actions.
  ghost,

  /// Red fill: leave, delete, end call.
  danger,

  /// White on paper (light) / raised (dark): back buttons and actions on
  /// paper pages.
  onPaper,
}

/// Button heights.
enum WeCordButtonSize {
  /// 54: full-width actions on phones (sign in, send request).
  large(54, 16, 24, 20),

  /// 44: the default.
  medium(44, 15, 20, 18),

  /// 32: inline chips and actions inside cards.
  small(32, 13, 14, 16);

  const WeCordButtonSize(this.height, this.fontSize, this.padding, this.icon);

  final double height;
  final double fontSize;
  final double padding;
  final double icon;
}

({Color fill, Color foreground, Color hover}) _colorsFor(
  WeCordButtonVariant variant,
  WeCordTokens tokens,
) {
  final c = tokens.colors;
  Color shade(Color base, double amount) => Color.alphaBlend(
    (tokens.isDark ? Colors.white : Colors.black).withValues(alpha: amount),
    base,
  );
  return switch (variant) {
    WeCordButtonVariant.primary => (
      fill: c.ink,
      foreground: c.onInk,
      hover: tokens.isDark
          ? Color.alphaBlend(Colors.black.withValues(alpha: 0.08), c.ink)
          : Color.alphaBlend(Colors.white.withValues(alpha: 0.12), c.ink),
    ),
    WeCordButtonVariant.accent => (
      fill: c.accent,
      foreground: c.onAccent,
      hover: shade(c.accent, 0.08),
    ),
    WeCordButtonVariant.secondary => (
      fill: c.raised,
      foreground: c.ink,
      hover: shade(c.raised, 0.04),
    ),
    WeCordButtonVariant.ghost => (
      fill: c.raised.withValues(alpha: 0),
      foreground: c.ink,
      hover: c.raised,
    ),
    WeCordButtonVariant.danger => (
      fill: c.danger,
      foreground: c.onDanger,
      hover: shade(c.danger, 0.08),
    ),
    WeCordButtonVariant.onPaper => (
      fill: tokens.isDark ? c.raised : c.panel,
      foreground: c.ink,
      hover: tokens.isDark ? c.raisedStrong : c.lineSoft,
    ),
  };
}

/// A pill button. Pass [expand] for full-width phone actions and [loading]
/// to swap the label for a spinner (it is disabled meanwhile).
class WeCordButton extends StatelessWidget {
  const WeCordButton({
    required this.label,
    required this.onPressed,
    this.variant = WeCordButtonVariant.primary,
    this.size = WeCordButtonSize.medium,
    this.icon,
    this.expand = false,
    this.loading = false,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final WeCordButtonVariant variant;
  final WeCordButtonSize size;
  final IconData? icon;
  final bool expand;
  final bool loading;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = _colorsFor(variant, tokens);
    final enabled = onPressed != null && !loading;
    return WeCordPressable(
      onPressed: enabled ? onPressed : null,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: loading ? label : null,
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        final content = loading
            ? SizedBox.square(
                dimension: size.icon,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.foreground,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: size.icon, color: colors.foreground),
                    SizedBox(width: size == WeCordButtonSize.small ? 6 : 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.foreground,
                        fontSize: size.fontSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              );
        return AnimatedOpacity(
          opacity: onPressed == null ? 0.4 : 1,
          duration: WeCordMotion.quick,
          child: AnimatedContainer(
            duration: WeCordMotion.quick,
            curve: WeCordMotion.standard,
            // At least `size.height`; taller when large text needs room.
            constraints: BoxConstraints(minHeight: size.height),
            width: expand ? double.infinity : null,
            padding: EdgeInsets.symmetric(
              horizontal: size.padding,
              vertical: size == WeCordButtonSize.small ? 6 : 8,
            ),
            decoration: ShapeDecoration(
              color: hovered && enabled ? colors.hover : colors.fill,
              shape: const StadiumBorder(),
            ),
            child: expand
                ? Center(child: content)
                : Center(widthFactor: 1, heightFactor: 1, child: content),
          ),
        );
      },
    );
  }
}

/// A round icon button. [tooltip] doubles as its accessible label. The
/// visible circle is [size]; the touch target never shrinks below 44.
class WeCordIconButton extends StatelessWidget {
  const WeCordIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.variant = WeCordButtonVariant.secondary,
    this.size = 40,
    this.iconSize,
    this.badgeCount,
    this.selected = false,
    this.focusNode,
    this.onLongPress,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// A long press (the tooltip then does not show on long press).
  final VoidCallback? onLongPress;
  final WeCordButtonVariant variant;
  final double size;
  final double? iconSize;

  /// A red count on the top-right corner (notifications).
  final int? badgeCount;

  /// Shows the button as switched on (a toggled panel or filter).
  final bool selected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = _colorsFor(
      selected && variant == WeCordButtonVariant.ghost
          ? WeCordButtonVariant.secondary
          : variant,
      tokens,
    );
    final target = size < WeCordSizes.touchTarget
        ? WeCordSizes.touchTarget
        : size;
    return WeCordPressable(
      onPressed: onPressed,
      onLongPress: onLongPress,
      tooltip: tooltip,
      semanticLabel: tooltip,
      selected: selected,
      focusNode: focusNode,
      pressedScale: 0.92,
      shape: const CircleBorder(),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        Widget circle = AnimatedContainer(
          duration: WeCordMotion.quick,
          curve: WeCordMotion.standard,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: hovered && onPressed != null ? colors.hover : colors.fill,
            shape: BoxShape.circle,
            boxShadow: variant == WeCordButtonVariant.onPaper
                ? tokens.shadows.hairline
                : null,
          ),
          child: Icon(
            icon,
            size: iconSize ?? (size * 0.5).clamp(16.0, 24.0),
            color: colors.foreground,
          ),
        );
        if (badgeCount != null && badgeCount! > 0) {
          circle = Stack(
            clipBehavior: Clip.none,
            children: [
              circle,
              Positioned(
                top: -2,
                right: -2,
                child: CountBadge(count: badgeCount, size: 18),
              ),
            ],
          );
        }
        return AnimatedOpacity(
          opacity: onPressed == null ? 0.4 : 1,
          duration: WeCordMotion.quick,
          child: SizedBox.square(
            dimension: target,
            child: Center(child: circle),
          ),
        );
      },
    );
  }
}
