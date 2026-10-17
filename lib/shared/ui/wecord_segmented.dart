import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/motion.dart';
import 'package:wecord/shared/ui/tap_target.dart';
import 'package:wecord/shared/ui/wecord_pressable.dart';

/// One choice in a [WeCordSegmented].
class WeCordSegment<T> {
  const WeCordSegment({
    required this.value,
    required this.label,
    this.icon,
    this.key,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Key of the segment's button, for tests.
  final Key? key;
}

/// An iOS-style segmented control: equal segments on a raised track with
/// a white thumb that springs to the selection. Fills the width it gets
/// when [expand] is set, otherwise sizes to its widest segment.
class WeCordSegmented<T> extends StatelessWidget {
  const WeCordSegmented({
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.expand = false,
    this.height = 36,
    this.semanticLabel,
    super.key,
  });

  final List<WeCordSegment<T>> segments;
  final T selected;
  final ValueChanged<T>? onChanged;
  final bool expand;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final count = segments.length;
    final index = segments.indexWhere((s) => s.value == selected);
    final spring = WeCordMotion.snappy;
    const inset = 3.0;

    // The track looks `height` tall; on touch screens the segments reach
    // the platform's touch target, above and below it.
    final reach = math.max(height, context.touchTargetSize);
    final track = SizedBox(
      height: reach,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Container(
                height: height,
                padding: const EdgeInsets.all(inset),
                decoration: BoxDecoration(
                  color: c.raised,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: index < 0
                    ? null
                    : AnimatedAlign(
                        alignment: Alignment(
                          count == 1 ? 0 : -1 + 2 * index / (count - 1),
                          0,
                        ),
                        duration: spring.durationOf(context),
                        curve: spring.curve,
                        child: FractionallySizedBox(
                          widthFactor: 1 / count,
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: tokens.isDark ? c.raisedStrong : c.panel,
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: tokens.shadows.hairline,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          // The segments set the width; they are as tall as `reach`.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: inset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final segment in segments)
                  Expanded(child: _segment(context, segment)),
              ],
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      label: semanticLabel,
      child: expand ? track : IntrinsicWidth(child: track),
    );
  }

  Widget _segment(BuildContext context, WeCordSegment<T> segment) {
    final c = context.tokens.colors;
    final isSelected = segment.value == selected;
    return WeCordPressable(
      key: segment.key,
      selected: isSelected,
      exclusiveGroup: true,
      minTapSize: Size.zero,
      pressedScale: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      onPressed: onChanged == null
          ? null
          : () {
              if (!isSelected) {
                WeCordHaptics.selection();
                onChanged!(segment.value);
              }
            },
      builder: (context, states) {
        final color = isSelected ? c.ink : c.muted;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (segment.icon != null) ...[
                Icon(segment.icon, size: 16, color: color),
                const SizedBox(width: 6),
              ],
              // A label that does not fit shrinks instead of being cut off
              // ("Comfortab..."); screen readers still get the whole word.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    segment.label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
