import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/motion.dart';
import 'package:wecord/shared/ui/wecord_pressable.dart';

/// An iOS-style switch: a pill track (accent when on) and a white thumb
/// that springs across. 46×28 on phones; pass [compact] for the 42×26
/// desktop size. Ticks a selection haptic when flipped.
class WeCordSwitch extends StatelessWidget {
  const WeCordSwitch({
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.semanticLabel,
    this.focusNode,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool compact;
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final width = compact ? 42.0 : 46.0;
    final height = compact ? 26.0 : 28.0;
    const inset = 3.0;
    final thumb = height - inset * 2;
    final spring = WeCordMotion.snappy;
    return WeCordPressable(
      toggled: value,
      semanticLabel: semanticLabel,
      focusNode: focusNode,
      pressedScale: 1,
      onPressed: onChanged == null
          ? null
          : () {
              WeCordHaptics.selection();
              onChanged!(!value);
            },
      builder: (context, states) {
        final pressed = states.contains(WidgetState.pressed);
        return AnimatedOpacity(
          opacity: onChanged == null ? 0.5 : 1,
          duration: WeCordMotion.quick,
          child: AnimatedContainer(
            duration: WeCordMotion.durationOf(context, WeCordMotion.base),
            curve: WeCordMotion.standard,
            width: width,
            height: height,
            padding: const EdgeInsets.all(inset),
            decoration: BoxDecoration(
              color: value ? c.accent : c.track,
              borderRadius: BorderRadius.circular(height),
            ),
            child: AnimatedAlign(
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              duration: spring.durationOf(context),
              curve: spring.curve,
              child: AnimatedContainer(
                duration: spring.durationOf(context),
                curve: spring.curve,
                // The thumb stretches a little while held, like iOS.
                width: pressed ? thumb + 5 : thumb,
                height: thumb,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(thumb),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
