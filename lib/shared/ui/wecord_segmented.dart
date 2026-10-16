import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/motion.dart';
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

    final track = Container(
      height: height,
      padding: const EdgeInsets.all(inset),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          if (index >= 0)
            Positioned.fill(
              child: AnimatedAlign(
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
          Row(
            children: [
              for (final segment in segments)
                Expanded(child: _segment(context, segment)),
            ],
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
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (segment.icon != null) ...[
                Icon(segment.icon, size: 16, color: color),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  segment.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: color,
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
