import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Who can see this": the audience of my status (and of the bubble over my
/// avatar in my friends' rows). Shown in the status sheet; it reports a
/// change through [onChanged] and the sheet saves it with the status.
class StatusVisibilityPicker extends ConsumerStatefulWidget {
  const StatusVisibilityPicker({required this.onChanged, super.key});

  /// Called with the new choice, or null when the choice is the saved one
  /// again (nothing to save).
  final ValueChanged<StatusVisibility?> onChanged;

  @override
  ConsumerState<StatusVisibilityPicker> createState() =>
      _StatusVisibilityPickerState();
}

class _StatusVisibilityPickerState
    extends ConsumerState<StatusVisibilityPicker> {
  StatusVisibility? _picked;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final saved =
        ref.watch(myProfileExtrasProvider).value?.statusVisibility ??
        StatusVisibility.everyone;
    final selected = _picked ?? saved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
          child: Semantics(
            header: true,
            child: Text(
              tr('Who can see this'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.subtle,
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final choice in StatusVisibility.values)
              WeCordChip(
                key: ValueKey('status-visibility-${choice.name}'),
                label: choice.label,
                selected: choice == selected,
                onPressed: () {
                  setState(() => _picked = choice);
                  widget.onChanged(choice == saved ? null : choice);
                },
              ),
          ],
        ),
      ],
    );
  }
}
