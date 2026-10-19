import 'package:flutter/material.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "How long": permanent, or an hour to 30 days. Used by every ban dialog.
class BanDurationPicker extends StatelessWidget {
  const BanDurationPicker({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final Duration? selected;
  final ValueChanged<Duration?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SettingsGroup(
      key: const ValueKey('ban-duration'),
      header: tr('How long'),
      color: c.well,
      separatorIndent: 14,
      children: [
        for (final (label, length) in banDurations)
          SettingsRow(
            key: ValueKey('ban-duration-${length?.inSeconds ?? 0}'),
            title: tr(label),
            showChevron: false,
            trailing: selected == length
                ? Icon(Icons.check_rounded, size: 20, color: c.accentText)
                : null,
            onTap: () => onChanged(length),
          ),
      ],
    );
  }
}
