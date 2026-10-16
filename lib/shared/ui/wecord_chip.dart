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
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final IconData? icon;
  final int? count;
  final bool onPaper;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final fill = selected ? c.ink : (onPaper ? c.panel : c.raised);
    final foreground = selected ? c.onInk : c.ink;
    final count = this.count;
    return WeCordPressable(
      selected: selected,
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
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: ShapeDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.05), fill)
                : fill,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
              ],
              Text(
                count == null || count == 0 ? label : '$label $count',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
