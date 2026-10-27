import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/motion.dart';
import 'package:wecord/shared/ui/wecord_pressable.dart';

/// A pill chip for filters and tabs ("All", "Mentions 2"): ink when
/// selected, a quiet fill otherwise (white on [onPaper] pages). [count]
/// follows the label.
class WeCordChip extends StatelessWidget {
  const WeCordChip({
    required this.label,
    this.selected = false,
    this.onPressed,
    this.icon,
    this.count,
    this.onPaper = false,
    this.height = 34,
    this.onLongPress,
    this.trailing,
    this.semanticLabel,
    this.hint,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final IconData? icon;
  final int? count;
  final bool onPaper;
  final double height;

  /// Held (or right-clicked) for more, like editing a folder.
  final VoidCallback? onLongPress;

  /// Shown after the label (a gray count pill, a red dot).
  final Widget? trailing;

  /// What a screen reader says instead of the label and the visible count;
  /// use it when [trailing] carries meaning.
  final String? semanticLabel;

  /// What the chip does, read after its label.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final fill = selected ? c.ink : (onPaper ? c.panel : c.raised);
    final foreground = selected ? c.onInk : c.ink;
    final count = this.count;
    return WeCordPressable(
      selected: selected,
      semanticLabel: semanticLabel,
      excludeSemantics: semanticLabel != null,
      hint: hint,
      onLongPress: onLongPress == null
          ? null
          : () {
              WeCordHaptics.light();
              onLongPress!();
            },
      onPressed: onPressed == null
          ? null
          : () {
              WeCordHaptics.selection();
              onPressed!();
            },
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered) && !selected;
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          curve: WeCordMotion.standard,
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: ShapeDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.05), fill)
                : fill,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  count == null || count == 0 ? label : '$label $count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ],
          ),
        );
      },
    );
  }
}
