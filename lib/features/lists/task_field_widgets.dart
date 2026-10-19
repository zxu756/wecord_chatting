import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/task_field_format.dart';
import 'package:wecord/features/lists/task_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/ui/ui.dart';

Future<void> openTaskLink(String address) async {
  final uri = Uri.tryParse(address);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return;
  }
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    // Nothing to open it with.
  }
}

/// What editing a field's value answers: `changed` false when dismissed;
/// `value` null clears it.
typedef FieldEdit = ({bool changed, Object? value});

/// Asks for the value of [def] (a number, a choice, a link, a person).
Future<FieldEdit> editTaskFieldValue(
  BuildContext context, {
  required TaskFieldDef def,
  required Object? current,
  required List<GroupMember> members,
}) async {
  switch (def.type) {
    case TaskFieldType.number:
    case TaskFieldType.link:
      final result = await showDialog<_TextAnswer>(
        context: context,
        builder: (context) => _FieldTextDialog(def: def, current: current),
      );
      if (result == null) {
        return (changed: false, value: null);
      }
      return (changed: true, value: result.value);
    case TaskFieldType.select:
      final result = await showWeCordSheet<_PickAnswer>(
        context,
        title: def.name,
        builder: (context, _) => _FieldChoiceSheet(
          options: [
            for (final option in def.options)
              (id: option.id, name: option.name),
          ],
          current: current as String?,
          clearLabel: tr('No choice'),
        ),
      );
      if (result == null) {
        return (changed: false, value: null);
      }
      return (changed: true, value: result.id);
    case TaskFieldType.person:
      final result = await showWeCordSheet<_PickAnswer>(
        context,
        title: def.name,
        detents: const [0.55, 0.92],
        initialDetent: 0.7,
        builder: (context, scrollController) => _FieldChoiceSheet(
          options: [
            for (final member in members)
              (id: member.profile.id, name: member.profile.displayName),
          ],
          current: current as String?,
          clearLabel: tr('Nobody'),
          scrollController: scrollController,
        ),
      );
      if (result == null) {
        return (changed: false, value: null);
      }
      return (changed: true, value: result.id);
  }
}

class _TextAnswer {
  const _TextAnswer(this.value);

  /// A number or an address; null clears.
  final Object? value;
}

class _PickAnswer {
  const _PickAnswer(this.id);

  final String? id;
}

class _FieldTextDialog extends StatefulWidget {
  const _FieldTextDialog({required this.def, required this.current});

  final TaskFieldDef def;
  final Object? current;

  @override
  State<_FieldTextDialog> createState() => _FieldTextDialogState();
}

class _FieldTextDialogState extends State<_FieldTextDialog> {
  late final _text = TextEditingController(
    text: switch (widget.current) {
      final num value => formatTaskNumber(value),
      final String value => value,
      _ => '',
    },
  );
  String? _error;

  bool get _isNumber => widget.def.type == TaskFieldType.number;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final raw = _text.text.trim();
    if (raw.isEmpty) {
      Navigator.of(context).pop(const _TextAnswer(null));
      return;
    }
    if (_isNumber) {
      final number = num.tryParse(raw.replaceAll(',', '.'));
      if (number == null || number.abs() > 1e12) {
        setState(() => _error = tr('Enter a number.'));
        return;
      }
      Navigator.of(context).pop(_TextAnswer(number));
      return;
    }
    final link = normalizeTaskLink(raw);
    if (link == null) {
      setState(() => _error = tr('Enter a web address.'));
      return;
    }
    Navigator.of(context).pop(_TextAnswer(link));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.def.name),
      content: SizedBox(
        width: 360,
        child: WeCordTextField(
          fieldKey: const ValueKey('task-field-input'),
          controller: _text,
          autofocus: true,
          hint: _isNumber ? tr('A number') : 'https://',
          errorText: _error,
          keyboardType: _isNumber
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : TextInputType.url,
          inputFormatters: _isNumber
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))]
              : null,
          maxLength: _isNumber ? 20 : 500,
          onChanged: (_) {
            if (_error != null) {
              setState(() => _error = null);
            }
          },
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(tr('Save'))),
      ],
    );
  }
}

class _FieldChoiceSheet extends StatelessWidget {
  const _FieldChoiceSheet({
    required this.options,
    required this.current,
    required this.clearLabel,
    this.scrollController,
  });

  final List<({String id, String name})> options;
  final String? current;
  final String clearLabel;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    Widget row(String? id, String name, {bool muted = false}) {
      final on = id != null && id == current;
      return WeCordPressable(
        key: ValueKey('field-choice-${id ?? 'none'}'),
        onPressed: () => Navigator.of(context).pop(_PickAnswer(id)),
        selected: on,
        toggled: on,
        semanticLabel: name,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        pressedScale: 0.99,
        builder: (context, states) => Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on
                ? c.accentSoft
                : states.contains(WidgetState.hovered)
                ? c.raised
                : Colors.transparent,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: muted ? c.muted : c.ink,
                  ),
                ),
              ),
              if (on) Icon(Icons.check_rounded, color: c.accent),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      shrinkWrap: scrollController == null,
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        for (final option in options) row(option.id, option.name),
        if (options.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              tr('Nothing to choose from yet.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted),
            ),
          ),
        if (current != null) row(null, clearLabel, muted: true),
      ],
    );
  }
}

/// One line of the task sheet for a field of the list: its name and value.
class TaskFieldRow extends StatelessWidget {
  const TaskFieldRow({
    required this.def,
    required this.value,
    required this.members,
    required this.canEdit,
    required this.onEdit,
    super.key,
  });

  final TaskFieldDef def;
  final Object? value;
  final List<GroupMember> members;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final text = formatTaskFieldValue(def, value, members);
    final isLink = def.type == TaskFieldType.link && value is String;
    return WeCordPressable(
      key: ValueKey('task-field-${def.id}'),
      onPressed: canEdit
          ? onEdit
          : (isLink ? () => openTaskLink('$value') : null),
      semanticLabel: def.name,
      mergeSemantics: false,
      pressedScale: 0.99,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) => Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: states.contains(WidgetState.hovered) && canEdit
              ? c.raised
              : Colors.transparent,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        child: TaskLabelValueLine(
          icon: taskFieldIcon(def.type),
          label: def.name,
          value: Text(
            text ?? (canEdit ? tr('Not set') : '—'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: text == null ? FontWeight.w400 : FontWeight.w600,
              color: text == null ? c.subtle : c.ink,
            ),
          ),
          trailing: isLink
              ? WeCordIconButton(
                  icon: Icons.open_in_new_rounded,
                  tooltip: tr('Open the link'),
                  size: 36,
                  iconSize: 18,
                  variant: WeCordButtonVariant.ghost,
                  onPressed: () => unawaited(openTaskLink('$value')),
                )
              : null,
        ),
      ),
    );
  }
}
