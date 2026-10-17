import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// One choice in an [OptionPickerSheet].
class PickerOption<T> {
  const PickerOption({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon,
  });

  final T value;
  final String title;
  final String? subtitle;
  final IconData? icon;
}

/// Opens a WeCord sheet with [options] as rows and a check on the current
/// one; returns the option picked, or null when the sheet was dismissed.
Future<T?> showOptionPicker<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  required T selected,
  String? note,
}) {
  return showWeCordSheet<T>(
    context,
    title: title,
    builder: (context, _) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: OptionPickerBody<T>(
          options: options,
          selected: selected,
          note: note,
          onPick: (value) => Navigator.of(context).pop(value),
        ),
      ),
    ),
  );
}

/// The rows of a picker: one per option, a check on [selected].
class OptionPickerBody<T> extends StatelessWidget {
  const OptionPickerBody({
    required this.options,
    required this.selected,
    required this.onPick,
    this.note,
    this.enabled = true,
    super.key,
  });

  final List<PickerOption<T>> options;
  final T selected;
  final ValueChanged<T> onPick;

  /// Explains the choice, under the rows.
  final String? note;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsGroup(
          color: c.well,
          separatorIndent: 14,
          children: [
            for (final option in options)
              Semantics(
                selected: option.value == selected,
                child: SettingsRow(
                  key: ValueKey('option-${option.value}'),
                  title: option.title,
                  subtitle: option.subtitle,
                  trailing: option.value == selected
                      ? Icon(Icons.check_rounded, size: 20, color: c.accent)
                      : const SizedBox(width: 20),
                  onTap: enabled
                      ? () {
                          WeCordHaptics.selection();
                          onPick(option.value);
                        }
                      : null,
                ),
              ),
          ],
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
            child: Text(
              note!,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: c.muted),
            ),
          ),
      ],
    );
  }
}

/// Shown in a sheet when a choice could not be saved.
String couldNotSaveText() => tr('Could not save. Try again.');
