import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/notifications/notification_settings_controller.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A small moon that shows while quiet hours are on, for the corner of the
/// notifications bell. Nothing (and no space) the rest of the time.
class QuietHoursMoon extends ConsumerWidget {
  const QuietHoursMoon({
    this.size = 16,
    this.ringColor,
    this.semanticLabel = true,
    super.key,
  });

  /// The diameter of the moon's disc.
  final double size;

  /// A ring in the color behind it, so the moon stands out from the bell.
  final Color? ringColor;

  /// Whether screen readers hear "Quiet hours are on" (leave it off when the
  /// label is already part of a row).
  final bool semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(quietHoursActiveProvider)) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final moon = Container(
      key: const ValueKey('quiet-hours-moon'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.ink,
        border: ringColor == null
            ? null
            : Border.all(color: ringColor!, width: 1.5),
      ),
      child: Icon(Icons.nightlight_round, size: size * 0.66, color: c.onInk),
    );
    if (!semanticLabel) {
      return ExcludeSemantics(child: moon);
    }
    return Semantics(label: tr('Quiet hours are on'), child: moon);
  }
}
