import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/features/forms/form_repository.dart';
import 'package:wecord/features/forms/form_validation.dart';
import 'package:wecord/features/forms/form_widgets.dart';
import 'package:wecord/features/later/later_time.dart'
    show describeWhen, schedulePicks;
import 'package:wecord/features/later/when_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the form builder for [conversationId]. Resolves to true once the
/// card is posted.
Future<bool?> showFormBuilder(
  BuildContext context, {
  required String conversationId,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute<bool>(
      builder: (context) => FormBuilderPage(conversationId: conversationId),
    ),
  );
}

/// One question being edited, with the text boxes of its parts.
class _Draft {
  _Draft(FormFieldDef field)
    : def = field,
      label = TextEditingController(text: field.label),
      help = TextEditingController(text: field.help),
      min = TextEditingController(
        text: field.min == null ? '' : formatNumber(field.min!),
      ),
      max = TextEditingController(
        text: field.max == null ? '' : formatNumber(field.max!),
      ),
      options = [
        for (final o in field.options)
          (o.id, TextEditingController(text: o.label)),
      ],
      showHint = field.help.isNotEmpty;

  FormFieldDef def;
  final TextEditingController label;
  final TextEditingController help;
  final TextEditingController min;
  final TextEditingController max;
  final List<(String, TextEditingController)> options;
  bool showHint;

  void dispose() {
    label.dispose();
    help.dispose();
    min.dispose();
    max.dispose();
    for (final (_, controller) in options) {
      controller.dispose();
    }
  }

  /// The question as the boxes say it.
  FormFieldDef read() {
    final low = double.tryParse(min.text.trim().replaceAll(',', '.'));
    final high = double.tryParse(max.text.trim().replaceAll(',', '.'));
    return FormFieldDef(
      id: def.id,
      type: def.type,
      label: label.text,
      required: def.required,
      help: showHint ? help.text : '',
      options: [
        for (final (id, controller) in options)
          FormOption(id: id, label: controller.text),
      ],
      min: def.type == FormFieldType.number ? low : null,
      max: def.type == FormFieldType.number ? high : null,
      integerOnly: def.type == FormFieldType.number && def.integerOnly,
    );
  }
}

/// The form builder: a title, questions you can add, reorder and edit, and
/// the settings. Posting puts the card into the chat.
class FormBuilderPage extends ConsumerStatefulWidget {
  const FormBuilderPage({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<FormBuilderPage> createState() => _FormBuilderPageState();
}

class _FormBuilderPageState extends ConsumerState<FormBuilderPage> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _limit = TextEditingController();
  final _drafts = <_Draft>[];
  var _settings = const FormSettings();
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _drafts.add(_Draft(newFormField(FormFieldType.shortText, const [])));
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _limit.dispose();
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  FormDraft _draft() {
    final max = int.tryParse(_limit.text.trim());
    return FormDraft(
      title: _title.text,
      description: _description.text,
      fields: [for (final draft in _drafts) draft.read()],
      settings: _limit.text.trim().isEmpty
          ? _settings.copyWith(clearMax: true)
          : _settings.copyWith(maxResponses: max),
    );
  }

  Future<void> _addQuestion() async {
    if (_drafts.length >= formMaxFields) {
      setState(
        () => _error = tr('A form can have up to {count} questions.', {
          'count': formMaxFields,
        }),
      );
      return;
    }
    final type = await showWeCordSheet<FormFieldType>(
      context,
      title: tr('Add a question'),
      builder: (context, _) => const _TypeSheet(),
    );
    if (type == null || !mounted) {
      return;
    }
    setState(() {
      _error = null;
      _drafts.add(
        _Draft(newFormField(type, [for (final d in _drafts) d.def.id])),
      );
    });
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _drafts.length || from == to) {
      return;
    }
    setState(() => _drafts.insert(to, _drafts.removeAt(from)));
  }

  void _remove(int index) {
    setState(() => _drafts.removeAt(index).dispose());
  }

  Future<void> _pickDeadline() async {
    final picked = await showWhenSheet(
      context,
      title: tr('Deadline'),
      picks: schedulePicks,
      initial: _settings.deadline,
    );
    if (picked != null && mounted) {
      setState(() => _settings = _settings.copyWith(deadline: picked));
    }
  }

  Future<void> _pickResults() async {
    final picked = await showWeCordSheet<FormResultsVisibility>(
      context,
      title: tr('Who can see the answers'),
      builder: (context, _) => _ResultsSheet(selected: _settings.results),
    );
    if (picked != null && mounted) {
      setState(() => _settings = _settings.copyWith(results: picked));
    }
  }

  Future<void> _post() async {
    final draft = _draft();
    final limitText = _limit.text.trim();
    final limit = int.tryParse(limitText);
    if (limitText.isNotEmpty && (limit == null || limit < 1 || limit > 500)) {
      setState(() => _error = tr('The limit is a number from 1 to 500.'));
      return;
    }
    final problem = draftProblem(draft);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(formRepositoryProvider)
          .create(widget.conversationId, sendableDraft(draft));
      if (mounted) {
        navigator.pop(true);
      }
    } on FormException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr("Couldn't post the form. Try again.");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final deadline = _settings.deadline;
    return FormPageFrame(
      pageKey: const ValueKey('form-builder-page'),
      title: tr('New form'),
      subtitle: tr('Everyone in the chat can fill it in.'),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  key: const ValueKey('form-builder-error'),
                  style: TextStyle(fontSize: 13.5, color: c.dangerText),
                ),
              ),
            ),
          WeCordButton(
            key: const ValueKey('form-post'),
            label: tr('Post form'),
            variant: WeCordButtonVariant.accent,
            size: WeCordButtonSize.large,
            expand: true,
            loading: _busy,
            onPressed: _busy ? null : () => unawaited(_post()),
          ),
        ],
      ),
      child: ListView(
        key: const ValueKey('form-builder-list'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          WeCordTextField(
            fieldKey: const ValueKey('form-title-field'),
            controller: _title,
            label: tr('Title'),
            hint: tr('Saturday hike sign-up'),
            maxLength: 120,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          WeCordTextField(
            fieldKey: const ValueKey('form-description-field'),
            controller: _description,
            label: tr('Description (optional)'),
            hint: tr('Meet at the gate at 8.'),
            maxLines: 4,
            minLines: 2,
            maxLength: 1000,
          ),
          SettingsSectionHeader(
            tr('Questions ({count})', {'count': _drafts.length}),
          ),
          ReorderableListView.builder(
            key: const ValueKey('form-question-list'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _drafts.length,
            onReorderItem: _move,
            proxyDecorator: (child, index, animation) => Material(
              color: Colors.transparent,
              elevation: 4,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
              child: child,
            ),
            itemBuilder: (context, index) {
              final draft = _drafts[index];
              return _QuestionEditor(
                key: ValueKey('form-question-${draft.def.id}'),
                draft: draft,
                index: index,
                count: _drafts.length,
                onChanged: () => setState(() => _error = null),
                onMove: (delta) => _move(index, index + delta),
                onRemove: _drafts.length > 1 ? () => _remove(index) : null,
              );
            },
          ),
          const SizedBox(height: 4),
          WeCordButton(
            key: const ValueKey('form-add-question'),
            label: tr('Add a question'),
            icon: Icons.add_rounded,
            variant: WeCordButtonVariant.secondary,
            size: WeCordButtonSize.large,
            expand: true,
            onPressed: () => unawaited(_addQuestion()),
          ),
          SettingsSectionHeader(tr('Settings')),
          SettingsGroup(
            color: c.well,
            children: [
              SettingsRow.toggle(
                key: const ValueKey('form-setting-anonymous'),
                icon: Icons.visibility_off_outlined,
                title: tr('Anonymous'),
                subtitle: tr(
                  'Nobody, not even you, can see who gave which answers.',
                ),
                value: _settings.anonymous,
                onChanged: (on) => setState(
                  () => _settings = _settings.copyWith(anonymous: on),
                ),
              ),
              SettingsRow.toggle(
                key: const ValueKey('form-setting-once'),
                icon: Icons.person_outline_rounded,
                title: tr('One answer per person'),
                value: _settings.onePerPerson,
                onChanged: (on) => setState(
                  () => _settings = _settings.copyWith(onePerPerson: on),
                ),
              ),
              SettingsRow.toggle(
                key: const ValueKey('form-setting-editable'),
                icon: Icons.edit_outlined,
                title: tr('People can change their answers'),
                value: _settings.onePerPerson && _settings.editable,
                onChanged: _settings.onePerPerson
                    ? (on) => setState(
                        () => _settings = _settings.copyWith(editable: on),
                      )
                    : null,
              ),
              SettingsRow(
                key: const ValueKey('form-setting-results'),
                icon: Icons.bar_chart_rounded,
                title: tr('Who can see the answers'),
                value: formResultsLabel(_settings.results),
                onTap: () => unawaited(_pickResults()),
              ),
              SettingsRow(
                key: const ValueKey('form-setting-deadline'),
                icon: Icons.event_outlined,
                title: tr('Deadline'),
                value: deadline == null
                    ? tr('None')
                    : describeWhen(
                        MaterialLocalizations.of(context),
                        deadline.toLocal(),
                        DateTime.now(),
                        alwaysUse24HourFormat:
                            MediaQuery.alwaysUse24HourFormatOf(context),
                      ),
                onTap: () => unawaited(_pickDeadline()),
              ),
              if (deadline != null)
                SettingsRow(
                  key: const ValueKey('form-setting-deadline-clear'),
                  icon: Icons.close_rounded,
                  title: tr('Remove deadline'),
                  showChevron: false,
                  onTap: () => setState(
                    () => _settings = _settings.copyWith(clearDeadline: true),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          WeCordTextField(
            fieldKey: const ValueKey('form-limit-field'),
            controller: _limit,
            label: tr('Most answers (optional)'),
            hint: tr('No limit'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 3,
          ),
        ],
      ),
    );
  }
}

/// "Only me", "People who answered", "Everyone".
String formResultsLabel(FormResultsVisibility visibility) =>
    switch (visibility) {
      FormResultsVisibility.creator => tr('Only me'),
      FormResultsVisibility.afterSubmit => tr('People who answered'),
      FormResultsVisibility.everyone => tr('Everyone'),
    };

class _QuestionEditor extends StatelessWidget {
  const _QuestionEditor({
    required this.draft,
    required this.index,
    required this.count,
    required this.onChanged,
    required this.onMove,
    required this.onRemove,
    super.key,
  });

  final _Draft draft;
  final int index;
  final int count;
  final VoidCallback onChanged;
  final ValueChanged<int> onMove;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final def = draft.def;
    return Semantics(
      container: true,
      label: tr('Question {number} of {count}: {type}', {
        'number': index + 1,
        'count': count,
        'type': formFieldTypeName(def.type),
      }),
      customSemanticsActions: {
        if (index > 0)
          CustomSemanticsAction(label: tr('Move up')): () => onMove(-1),
        if (index < count - 1)
          CustomSemanticsAction(label: tr('Move down')): () => onMove(1),
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(6, 8, 12, 12),
        decoration: BoxDecoration(
          color: c.well,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
          border: Border.all(color: c.lineSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  // A box being typed in keeps its caret layers on screen
                  // while the card lifts: let go of it first.
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    child: Tooltip(
                      message: tr('Drag to reorder'),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          key: ValueKey('form-drag-${def.id}'),
                          size: 22,
                          color: c.faint,
                        ),
                      ),
                    ),
                  ),
                ),
                SettingsIconTile(
                  icon: formFieldIcon(def.type),
                  tone: SettingsTone.accent,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${index + 1}. ${formFieldTypeName(def.type)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.muted,
                    ),
                  ),
                ),
                Text(
                  tr('Required'),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                const SizedBox(width: 8),
                WeCordSwitch(
                  key: ValueKey('form-required-${def.id}'),
                  compact: true,
                  semanticLabel: tr('Required'),
                  value: def.required,
                  onChanged: (on) {
                    draft.def = def.copyWith(required: on);
                    onChanged();
                  },
                ),
                WeCordIconButton(
                  key: ValueKey('form-remove-${def.id}'),
                  tooltip: tr('Delete question'),
                  icon: Icons.delete_outline_rounded,
                  size: 36,
                  iconSize: 20,
                  variant: WeCordButtonVariant.ghost,
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: WeCordTextField(
                fieldKey: ValueKey('form-label-${def.id}'),
                controller: draft.label,
                hint: tr('Question'),
                maxLength: 200,
                onChanged: (_) => onChanged(),
              ),
            ),
            if (draft.showHint)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 8),
                child: WeCordTextField(
                  fieldKey: ValueKey('form-help-${def.id}'),
                  controller: draft.help,
                  hint: tr('Hint (optional)'),
                  maxLength: 300,
                  onChanged: (_) => onChanged(),
                ),
              ),
            if (def.type.isChoice) _options(context),
            if (def.type == FormFieldType.number) _numberSettings(context),
            if (!draft.showHint)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6, top: 4),
                  child: WeCordButton(
                    key: ValueKey('form-add-hint-${def.id}'),
                    label: tr('Add a hint'),
                    variant: WeCordButtonVariant.ghost,
                    size: WeCordButtonSize.small,
                    onPressed: () {
                      draft.showHint = true;
                      onChanged();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _options(BuildContext context) {
    final multiple = draft.def.type == FormFieldType.multipleChoice;
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (id, controller)) in draft.options.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    multiple
                        ? Icons.check_box_outline_blank_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: c.faint,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: WeCordTextField(
                      fieldKey: ValueKey('form-option-${draft.def.id}-$id'),
                      controller: controller,
                      hint: tr('Choice {number}', {'number': i + 1}),
                      maxLength: 100,
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  WeCordIconButton(
                    key: ValueKey('form-option-remove-${draft.def.id}-$id'),
                    tooltip: tr('Delete choice'),
                    icon: Icons.close_rounded,
                    size: 34,
                    iconSize: 18,
                    variant: WeCordButtonVariant.ghost,
                    onPressed: draft.options.length > formMinOptions
                        ? () {
                            draft.options.removeAt(i).$2.dispose();
                            onChanged();
                          }
                        : null,
                  ),
                ],
              ),
            ),
          if (draft.options.length < formMaxOptions)
            Align(
              alignment: Alignment.centerLeft,
              child: WeCordButton(
                key: ValueKey('form-add-option-${draft.def.id}'),
                label: tr('Add a choice'),
                icon: Icons.add_rounded,
                variant: WeCordButtonVariant.ghost,
                size: WeCordButtonSize.small,
                onPressed: () {
                  draft.options.add((
                    newFormOptionId([for (final (id, _) in draft.options) id]),
                    TextEditingController(),
                  ));
                  onChanged();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _numberSettings(BuildContext context) {
    final inputs = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]'))];
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: WeCordTextField(
                  fieldKey: ValueKey('form-min-${draft.def.id}'),
                  controller: draft.min,
                  hint: tr('Smallest (optional)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: inputs,
                  maxLength: 14,
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: WeCordTextField(
                  fieldKey: ValueKey('form-max-${draft.def.id}'),
                  controller: draft.max,
                  hint: tr('Largest (optional)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: inputs,
                  maxLength: 14,
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
          SettingsRow.toggle(
            key: ValueKey('form-integer-${draft.def.id}'),
            title: tr('Whole numbers only'),
            value: draft.def.integerOnly,
            onChanged: (on) {
              draft.def = draft.def.copyWith(integerOnly: on);
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

class _TypeSheet extends StatelessWidget {
  const _TypeSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SettingsGroup(
          color: c.well,
          children: [
            for (final type in FormFieldType.values)
              SettingsRow(
                key: ValueKey('form-type-${type.wire}'),
                icon: formFieldIcon(type),
                tone: SettingsTone.accent,
                title: formFieldTypeName(type),
                showChevron: false,
                onTap: () => Navigator.of(context).pop(type),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultsSheet extends StatelessWidget {
  const _ResultsSheet({required this.selected});

  final FormResultsVisibility selected;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    String subtitle(FormResultsVisibility v) => switch (v) {
      FormResultsVisibility.creator => tr('Only you can read the answers.'),
      FormResultsVisibility.afterSubmit => tr(
        'Everyone can read the answers once they have sent theirs.',
      ),
      FormResultsVisibility.everyone => tr(
        'Everyone in the chat can read the answers.',
      ),
    };
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SettingsGroup(
          color: c.well,
          separatorIndent: 14,
          children: [
            for (final v in FormResultsVisibility.values)
              SettingsRow(
                key: ValueKey('form-results-${v.wire}'),
                title: formResultsLabel(v),
                subtitle: subtitle(v),
                trailing: v == selected
                    ? Icon(Icons.check_rounded, color: c.accent)
                    : null,
                onTap: () => Navigator.of(context).pop(v),
              ),
          ],
        ),
      ),
    );
  }
}
