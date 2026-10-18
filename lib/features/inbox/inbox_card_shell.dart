import 'package:flutter/material.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A white card on the paper page, as the Notifications cards are: rounded,
/// an accent edge while it needs an answer, a soft tint on hover or press.
class InboxCardShell extends StatelessWidget {
  const InboxCardShell({
    required this.child,
    this.onPressed,
    this.highlighted = false,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;

  /// Needs an answer: an accent edge.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WeCordRadii.xl),
    );
    return WeCordPressable(
      onPressed: onPressed,
      shape: shape,
      pressedScale: 0.98,
      builder: (context, states) {
        final hovered =
            onPressed != null &&
            (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed));
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.all(14),
          decoration: ShapeDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.025), c.panel)
                : c.panel,
            shape: shape.copyWith(
              side: highlighted
                  ? BorderSide(color: c.accent, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: child,
        );
      },
    );
  }
}
