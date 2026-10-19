import 'package:flutter/material.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/task_status_editor.dart' show newStatusId;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The most fields a list can have, and choices a field can have.
const maxTaskFields = 20;
const maxTaskFieldOptions = 30;

/// Edits a list's own fields: add, rename, change the type, reorder and
/// remove; for a single-choice field its choices. Returns the new fields, or
/// null when dismissed.
Future<List<TaskFieldDef>?> showTaskFieldsEditor(
  BuildContext context,
  List<TaskFieldDef> fields,
) {
  return showWeCordSheet<List<TaskFieldDef>>(
    context,
    title: tr('Custom fields'),
    detents: const [0.6, 0.94],
    initialDetent: 0.85,
    builder: (context, scrollController) =>
        _FieldsEditor(fields: fields, scrollController: scrollController),
  );
}

/// Whether [fields] can be saved: every field and choice has a name, a
/// single-choice field has at least one choice.
bool validTaskFields(List<TaskFieldDef> fields) {
  return fields.length <= maxTaskFields &&
      fields.every(
        (field) =>
            field.name.trim().isNotEmpty &&
            (field.type != TaskFieldType.select ||
                (field.options.isNotEmpty &&
                    field.options.length <= maxTaskFieldOptions &&
                    field.options.every(
                      (option) => option.name.trim().isNotEmpty,
                    ))),
      );
}

class _FieldsEditor extends StatefulWidget {
  const _FieldsEditor({required this.fields, this.scrollController});

  final List<TaskFieldDef> fields;
  final ScrollController? scrollController;

  @override
  State<_FieldsEditor> createState() => _FieldsEditorState();
}

class _FieldsEditorState extends State<_FieldsEditor> {
  late final List<TaskFieldDef> _fields = [...widget.fields];
  final _names = <String, TextEditingController>{};
  final _optionNames = <String, TextEditingController>{};

  TextEditingController _nameFor(TaskFieldDef field) => _names.putIfAbsent(
    field.id,
    () => TextEditingController(text: field.name),
  );

  TextEditingController _optionFor(String fieldId, TaskFieldOption option) =>
      _optionNames.putIfAbsent(
        '$fieldId/${option.id}',
        () => TextEditingController(text: option.name),
      );

  @override
  void dispose() {
    for (final controller in _names.values) {
      controller.dispose();
    }
    for (final controller in _optionNames.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _update(int index, TaskFieldDef Function(TaskFieldDef) change) {
    setState(() => _fields[index] = change(_fields[index]));
  }

  void _move(int index, int by) {
    final target = index + by;
    if (target < 0 || target >= _fields.length) {
      return;
    }
    setState(() {
      final field = _fields.removeAt(index);
      _fields.insert(target, field);
    });
  }

  void _add() {
    final id = newStatusId('field', {for (final f in _fields) f.id});
    setState(() {
      _fields.add(TaskFieldDef(id: id, name: '', type: TaskFieldType.number));
    });
  }

  void _remove(int index) {
    setState(() {
      final removed = _fields.removeAt(index);
      _names.remove(removed.id)?.dispose();
    });
  }

  void _addOption(int index) {
    final field = _fields[index];
    final id = newStatusId('option', {for (final o in field.options) o.id});
    _update(
      index,
      (field) => field.copyWith(
        options: [
          ...field.options,
          TaskFieldOption(id: id, name: ''),
        ],
      ),
    );
  }

  void _removeOption(int index, String optionId) {
    _update(
      index,
      (field) => field.copyWith(
        options: [
          for (final option in field.options)
            if (option.id != optionId) option,
        ],
      ),
    );
    _optionNames.remove('${_fields[index].id}/$optionId')?.dispose();
  }

  void _renameOption(int index, String optionId, String name) {
    _update(
      index,
      (field) => field.copyWith(
        options: [
          for (final option in field.options)
            if (option.id == optionId)
              TaskFieldOption(id: option.id, name: name)
            else
              option,
        ],
      ),
    );
  }

  void _save() {
    Navigator.of(context).pop([
      for (final field in _fields)
        field.copyWith(
          name: field.name.trim(),
          options: [
            for (final option in field.options)
              TaskFieldOption(id: option.id, name: option.name.trim()),
          ],
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final valid = validTaskFields(_fields);
    final changedType = [
      for (final field in _fields)
        for (final old in widget.fields)
          if (old.id == field.id && old.type != field.type) field,
    ].isNotEmpty;
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  tr(
                    'Add fields to keep more about each task: a number, a choice, a link or a person.',
                  ),
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
                ),
              ),
              for (final (index, field) in _fields.indexed)
                Container(
                  key: ValueKey('field-${field.id}'),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.well,
                    borderRadius: BorderRadius.circular(WeCordRadii.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: WeCordTextField(
                              fieldKey: ValueKey('field-name-${field.id}'),
                              controller: _nameFor(field),
                              hint: tr('Field name'),
                              maxLength: 40,
                              onChanged: (value) => _update(
                                index,
                                (field) => field.copyWith(name: value),
                              ),
                            ),
                          ),
                          WeCordIconButton(
                            icon: Icons.arrow_upward_rounded,
                            tooltip: tr('Move up'),
                            size: 36,
                            variant: WeCordButtonVariant.ghost,
                            onPressed: index > 0
                                ? () => _move(index, -1)
                                : null,
                          ),
                          WeCordIconButton(
                            icon: Icons.arrow_downward_rounded,
                            tooltip: tr('Move down'),
                            size: 36,
                            variant: WeCordButtonVariant.ghost,
                            onPressed: index < _fields.length - 1
                                ? () => _move(index, 1)
                                : null,
                          ),
                          WeCordIconButton(
                            icon: Icons.delete_outline_rounded,
                            tooltip: tr('Remove field'),
                            size: 36,
                            variant: WeCordButtonVariant.ghost,
                            onPressed: () => _remove(index),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final type in TaskFieldType.values)
                            WeCordChip(
                              key: ValueKey('field-${field.id}-${type.value}'),
                              label: type.label,
                              icon: null,
                              selected: field.type == type,
                              onPressed: () => _update(
                                index,
                                (field) => field.copyWith(
                                  type: type,
                                  options:
                                      type == TaskFieldType.select &&
                                          field.options.isEmpty
                                      ? [
                                          TaskFieldOption(
                                            id: 'option',
                                            name: '',
                                          ),
                                        ]
                                      : field.options,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (field.type == TaskFieldType.select) ...[
                        const SizedBox(height: 10),
                        for (final option in field.options)
                          Padding(
                            key: ValueKey('option-${field.id}-${option.id}'),
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: WeCordTextField(
                                    fieldKey: ValueKey(
                                      'option-name-${field.id}-${option.id}',
                                    ),
                                    controller: _optionFor(field.id, option),
                                    hint: tr('Choice'),
                                    maxLength: 40,
                                    onChanged: (value) =>
                                        _renameOption(index, option.id, value),
                                  ),
                                ),
                                WeCordIconButton(
                                  icon: Icons.close_rounded,
                                  tooltip: tr('Remove choice'),
                                  size: 36,
                                  variant: WeCordButtonVariant.ghost,
                                  onPressed: () =>
                                      _removeOption(index, option.id),
                                ),
                              ],
                            ),
                          ),
                        if (field.options.length < maxTaskFieldOptions)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: WeCordButton(
                              label: tr('Add a choice'),
                              icon: Icons.add_rounded,
                              size: WeCordButtonSize.small,
                              variant: WeCordButtonVariant.secondary,
                              onPressed: () => _addOption(index),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              if (_fields.length < maxTaskFields)
                Align(
                  alignment: Alignment.centerLeft,
                  child: WeCordButton(
                    label: tr('Add a field'),
                    icon: Icons.add_rounded,
                    variant: WeCordButtonVariant.secondary,
                    onPressed: _add,
                  ),
                ),
              if (changedType || widget.fields.length > _fields.length)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    tr(
                      'Values that no longer fit a field, and the values of a removed field, are cleared.',
                    ),
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
              if (!valid)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    tr(
                      'Give every field and choice a name, and every single-choice field at least one choice.',
                    ),
                    style: TextStyle(fontSize: 13, color: c.dangerText),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          child: WeCordButton(
            label: tr('Save'),
            expand: true,
            size: WeCordButtonSize.large,
            onPressed: valid ? _save : null,
          ),
        ),
      ],
    );
  }
}
