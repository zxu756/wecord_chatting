import 'package:flutter/material.dart';
import 'package:wecord/shared/models/custom_status.dart';

/// A status shown under a name, e.g. "🎯 Focusing"; nothing when [status]
/// is null or has expired.
class CustomStatusLabel extends StatelessWidget {
  const CustomStatusLabel({
    required this.status,
    this.style,
    this.textAlign,
    super.key,
  });

  final CustomStatus? status;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final active = activeCustomStatus(status);
    if (active == null) {
      return const SizedBox.shrink();
    }
    return Text(
      active.label,
      key: const ValueKey('custom-status-label'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style:
          style ??
          Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
