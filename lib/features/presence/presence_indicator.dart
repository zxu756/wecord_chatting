import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// The dot on the corner of an avatar: green for Online, a crescent for
/// Idle, a bar for Do Not Disturb and a hollow ring for offline (null) and
/// Invisible. Shapes differ too, so it doesn't rely on colour alone.
/// [borderColor] should match what the avatar sits on.
class PresenceIndicator extends StatelessWidget {
  const PresenceIndicator({
    required this.status,
    required this.borderColor,
    this.size = 12,
    super.key,
  });

  final PresenceStatus? status;
  final Color borderColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final color = presenceColor(context, status);
    final inner = size - 4;
    final Widget? cutout = switch (status) {
      PresenceStatus.online => null,
      // A bite out of the top left makes a crescent.
      PresenceStatus.idle => Align(
        alignment: Alignment.topLeft,
        child: _dot(inner * 0.6, borderColor),
      ),
      PresenceStatus.doNotDisturb => Center(
        child: Container(
          width: inner * 0.7,
          height: (inner * 0.25).clamp(1.5, 4),
          decoration: BoxDecoration(
            color: borderColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      PresenceStatus.invisible ||
      null => Center(child: _dot(inner * 0.45, borderColor)),
    };
    return Semantics(
      label: status == null || status == PresenceStatus.invisible
          ? tr('Offline')
          : status.label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: cutout,
      ),
    );
  }

  static Widget _dot(double diameter, Color color) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// The colour that stands for [status]; null means offline.
Color presenceColor(BuildContext context, PresenceStatus? status) {
  final c = context.tokens.colors;
  return switch (status) {
    PresenceStatus.online => c.success,
    PresenceStatus.idle => c.warning,
    PresenceStatus.doNotDisturb => c.danger,
    PresenceStatus.invisible || null => c.faint,
  };
}
