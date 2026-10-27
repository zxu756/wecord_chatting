import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/check_in/check_in_models.dart'
    show checkInDateText;
import 'package:wecord/features/circles/circle_ui.dart'
    show confirmCircleAction;
import 'package:wecord/features/forms/form_widgets.dart' show FormPageFrame;
import 'package:wecord/features/later/schedule_repeat.dart'
    show RepeatKind, repeatKindLabel;
import 'package:wecord/features/notifications/device_time_zone.dart';
import 'package:wecord/features/privacy/option_picker.dart';
import 'package:wecord/features/workflows/workflow_models.dart';
import 'package:wecord/features/workflows/workflow_repository.dart';
import 'package:wecord/features/workflows/workflow_runs_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

String _weekdayName(int isoWeekday) => switch (isoWeekday) {
  1 => tr('Monday'),
  2 => tr('Tuesday'),
  3 => tr('Wednesday'),
  4 => tr('Thursday'),
  5 => tr('Friday'),
  6 => tr('Saturday'),
  _ => tr('Sunday'),
};

/// The editable form of one step.
class _ActionDraft {
  _ActionDraft(this.kind);

  factory _ActionDraft.from(WorkflowAction action) {
    final draft = _ActionDraft(action.kind)
      ..channelId = action.channelId ?? ''
      ..roleId = action.roleId ?? ''
      ..formId = action.formId ?? ''
      ..fromMessage = action.fromMessage
      ..dateInTitle = action.dateInTitle
      ..deadlineDays = action.deadlineDays;
    draft.text.text = action.text ?? '';
    draft.title.text = action.title ?? '';
    return draft;
  }

  WorkflowActionKind kind;
  final text = TextEditingController();
  final title = TextEditingController();
  String channelId = '';
  String roleId = '';
  String formId = '';
  bool fromMessage = false;
  bool dateInTitle = true;
  int? deadlineDays;

  void dispose() {
    text.dispose();
    title.dispose();
  }

  WorkflowAction build({
    required bool inCircle,
    required WorkflowOptions options,
    required WorkflowTriggerKind trigger,
  }) {
    final config = <String, Object?>{};
    if (kind.usesChannel && inCircle) {
      var channel = channelId;
      if (channel.isEmpty &&
          !trigger.hasMessage &&
          options.channels.isNotEmpty) {
        channel = options.channels.first.id;
      }
      if (channel.isNotEmpty) {
        config['channel_id'] = channel;
      }
    }
    switch (kind) {
      case WorkflowActionKind.sendMessage:
      case WorkflowActionKind.sendDm:
        config['text'] = text.text.trim();
      case WorkflowActionKind.addRole:
        config['role_id'] = roleId.isNotEmpty
            ? roleId
            : (options.roles.isEmpty ? '' : options.roles.first.id);
      case WorkflowActionKind.createTask:
        config['from_message'] = fromMessage;
        if (title.text.trim().isNotEmpty) {
          config['title'] = title.text.trim();
        }
        if (fromMessage) {
          config.remove('channel_id');
        }
      case WorkflowActionKind.sendForm:
        config['form_id'] = formId.isNotEmpty
            ? formId
            : (options.forms.isEmpty ? '' : options.forms.first.id);
        config['date_in_title'] = dateInTitle;
        if (deadlineDays != null) {
          config['deadline_days'] = deadlineDays;
        }
    }
    return WorkflowAction(kind, config);
  }
}

/// Makes or changes a workflow: a name, what starts it and up to five
/// steps. Saving makes the saver the person the steps run as.
class WorkflowEditorPage extends ConsumerStatefulWidget {
  const WorkflowEditorPage({required this.scope, this.workflow, super.key});

  final WorkflowScope scope;

  /// The workflow being changed; null makes a new one.
  final Workflow? workflow;

  @override
  ConsumerState<WorkflowEditorPage> createState() => _WorkflowEditorPageState();
}

class _WorkflowEditorPageState extends ConsumerState<WorkflowEditorPage> {
  final _name = TextEditingController();
  final _emoji = TextEditingController();
  final _words = TextEditingController();
  var _triggerKind = WorkflowTriggerKind.memberJoined;
  String _triggerChannel = '';
  String _triggerForm = '';
  var _recurrence = RepeatKind.weekly;
  var _day = 1;
  var _time = const TimeOfDay(hour: 9, minute: 0);
  DateTime? _until;
  String? _zone;
  var _enabled = true;
  final _actions = <_ActionDraft>[];
  var _busy = false;
  String? _error;

  bool get _inCircle => widget.scope.isCircle;

  @override
  void initState() {
    super.initState();
    final workflow = widget.workflow;
    if (workflow == null) {
      _actions.add(_ActionDraft(WorkflowActionKind.sendMessage));
      return;
    }
    _name.text = workflow.name;
    _enabled = workflow.enabled;
    final trigger = workflow.trigger;
    _triggerKind = trigger.kind;
    _triggerChannel = trigger.channelId ?? '';
    _triggerForm = trigger.formId ?? '';
    _emoji.text = trigger.emoji ?? '';
    _words.text = trigger.words.join(', ');
    _recurrence = RepeatKind.fromWire(trigger.recurrence) ?? RepeatKind.weekly;
    _day = trigger.day ?? 1;
    final parts = trigger.time.split(':');
    _time = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    _zone = trigger.zone;
    _until = trigger.until == null ? null : DateTime.tryParse(trigger.until!);
    _actions.addAll(workflow.actions.map(_ActionDraft.from));
  }

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    _words.dispose();
    for (final action in _actions) {
      action.dispose();
    }
    super.dispose();
  }

  WorkflowOptions get _options =>
      ref.read(workflowOptionsProvider(widget.scope)).value ??
      const WorkflowOptions();

  Future<void> _pickTrigger() async {
    final picked = await showOptionPicker<WorkflowTriggerKind>(
      context,
      title: tr('What starts it'),
      selected: _triggerKind,
      options: [
        for (final kind in WorkflowTriggerKind.values)
          PickerOption(value: kind, title: kind.label),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _triggerKind = picked);
    }
  }

  Future<String?> _pickFrom(
    String title,
    String selected,
    List<PickerOption<String>> options,
  ) {
    return showOptionPicker<String>(
      context,
      title: title,
      selected: selected,
      options: options,
    );
  }

  Future<void> _pickTriggerChannel() async {
    final picked = await _pickFrom(tr('Channel'), _triggerChannel, [
      PickerOption(value: '', title: tr('Any channel')),
      for (final channel in _options.channels)
        PickerOption(value: channel.id, title: channel.name),
    ]);
    if (picked != null && mounted) {
      setState(() => _triggerChannel = picked);
    }
  }

  Future<void> _pickTriggerForm() async {
    final picked = await _pickFrom(tr('Form'), _triggerForm, [
      for (final form in _options.forms)
        PickerOption(value: form.id, title: form.title),
    ]);
    if (picked != null && mounted) {
      setState(() => _triggerForm = picked);
    }
  }

  Future<void> _pickRecurrence() async {
    final picked = await showOptionPicker<RepeatKind>(
      context,
      title: tr('Repeat'),
      selected: _recurrence,
      options: [
        for (final kind in RepeatKind.values)
          PickerOption(value: kind, title: repeatKindLabel(kind)),
      ],
    );
    if (picked != null && mounted) {
      setState(() {
        _recurrence = picked;
        _day = 1;
      });
    }
  }

  Future<void> _pickDay() async {
    final weekly = _recurrence == RepeatKind.weekly;
    final picked = await showOptionPicker<int>(
      context,
      title: weekly ? tr('Day of the week') : tr('Day of the month'),
      selected: _day,
      options: [
        for (var d = 1; d <= (weekly ? 7 : 31); d++)
          PickerOption(value: d, title: weekly ? _weekdayName(d) : '$d'),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _day = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) {
      setState(() => _time = picked);
    }
  }

  Future<void> _pickUntil() async {
    final today = DateTime.now();
    final first = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _until ?? first.add(const Duration(days: 30)),
      firstDate: first,
      lastDate: first.add(const Duration(days: 730)),
    );
    if (picked != null && mounted) {
      setState(() => _until = picked);
    }
  }

  Future<void> _pickActionKind(_ActionDraft draft) async {
    final picked = await showOptionPicker<WorkflowActionKind>(
      context,
      title: tr('What it should do'),
      selected: draft.kind,
      options: [
        for (final kind in WorkflowActionKind.values)
          if (_inCircle || kind != WorkflowActionKind.addRole)
            PickerOption(value: kind, title: kind.label),
      ],
    );
    if (picked != null && mounted) {
      setState(() => draft.kind = picked);
    }
  }

  void _addAction() {
    final limit = ref
        .read(workflowListProvider(widget.scope))
        .value
        ?.limits
        .maxActions;
    if (_actions.length >= (limit ?? 5)) {
      return;
    }
    setState(() => _actions.add(_ActionDraft(WorkflowActionKind.sendMessage)));
  }

  WorkflowTrigger _buildTrigger() {
    final config = <String, Object?>{};
    switch (_triggerKind) {
      case WorkflowTriggerKind.memberJoined:
        break;
      case WorkflowTriggerKind.reaction:
        config['emoji'] = _emoji.text.trim();
        if (_inCircle && _triggerChannel.isNotEmpty) {
          config['channel_id'] = _triggerChannel;
        }
      case WorkflowTriggerKind.keyword:
        config['words'] = [
          for (final word in _words.text.split(RegExp('[,，\n]')))
            if (word.trim().isNotEmpty) word.trim(),
        ];
        if (_inCircle && _triggerChannel.isNotEmpty) {
          config['channel_id'] = _triggerChannel;
        }
      case WorkflowTriggerKind.schedule:
        config['recurrence'] = _recurrence.wire;
        config['time'] =
            '${_time.hour.toString().padLeft(2, '0')}:'
            '${_time.minute.toString().padLeft(2, '0')}';
        config['zone'] = _zone ?? deviceTimeZone() ?? 'UTC';
        if (_recurrence == RepeatKind.weekly ||
            _recurrence == RepeatKind.monthly) {
          config['day'] = _day;
        }
        if (_until != null) {
          config['until'] = checkInDateText(_until!);
        }
      case WorkflowTriggerKind.formSubmitted:
        final forms = _options.forms;
        config['form_id'] = _triggerForm.isNotEmpty
            ? _triggerForm
            : (forms.isEmpty ? '' : forms.first.id);
    }
    return WorkflowTrigger(_triggerKind, config);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final options = await ref.read(
        workflowOptionsProvider(widget.scope).future,
      );
      await ref
          .read(workflowRepositoryProvider)
          .save(
            widget.scope,
            id: widget.workflow?.id,
            name: _name.text.trim(),
            trigger: _buildTrigger(),
            actions: [
              for (final draft in _actions)
                draft.build(
                  inCircle: _inCircle,
                  options: options,
                  trigger: _triggerKind,
                ),
            ],
            enabled: _enabled,
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on WorkflowException catch (error) {
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
          _error = tr("That didn't work. Try again.");
        });
      }
    }
  }

  Future<void> _delete() async {
    final workflow = widget.workflow;
    if (workflow == null) {
      return;
    }
    final sure = await confirmCircleAction(
      context,
      title: tr('Delete this workflow?'),
      message: tr('Its run log goes with it.'),
      confirmLabel: tr('Delete'),
    );
    if (!sure || !mounted) {
      return;
    }
    try {
      await ref.read(workflowRepositoryProvider).delete(workflow.id);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on WorkflowException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } on Object {
      if (mounted) {
        setState(() => _error = tr("That didn't work. Try again."));
      }
    }
  }

  Widget _pickRow({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SettingsRow(
      key: key,
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }

  List<Widget> _triggerRows(WorkflowOptions options) {
    final channel = _triggerChannel.isEmpty
        ? tr('Any channel')
        : options.channelName(_triggerChannel) ?? tr('Any channel');
    final loc = MaterialLocalizations.of(context);
    return [
      if (_triggerKind == WorkflowTriggerKind.reaction ||
          _triggerKind == WorkflowTriggerKind.keyword)
        if (_inCircle)
          _pickRow(
            key: const ValueKey('workflow-trigger-channel'),
            icon: Icons.tag_rounded,
            title: tr('Channel'),
            subtitle: channel,
            onTap: () => unawaited(_pickTriggerChannel()),
          ),
      if (_triggerKind == WorkflowTriggerKind.formSubmitted)
        _pickRow(
          key: const ValueKey('workflow-trigger-form'),
          icon: Icons.assignment_outlined,
          title: tr('Form'),
          subtitle:
              options.formTitle(_triggerForm) ??
              (options.forms.isEmpty
                  ? tr('No forms here yet')
                  : options.forms.first.title),
          onTap: () => unawaited(_pickTriggerForm()),
        ),
      if (_triggerKind == WorkflowTriggerKind.schedule) ...[
        _pickRow(
          key: const ValueKey('workflow-trigger-repeat'),
          icon: Icons.repeat_rounded,
          title: tr('Repeat'),
          subtitle: repeatKindLabel(_recurrence),
          onTap: () => unawaited(_pickRecurrence()),
        ),
        if (_recurrence == RepeatKind.weekly ||
            _recurrence == RepeatKind.monthly)
          _pickRow(
            key: const ValueKey('workflow-trigger-day'),
            icon: Icons.calendar_today_outlined,
            title: _recurrence == RepeatKind.weekly
                ? tr('Day of the week')
                : tr('Day of the month'),
            subtitle: _recurrence == RepeatKind.weekly
                ? _weekdayName(_day)
                : '$_day',
            onTap: () => unawaited(_pickDay()),
          ),
        _pickRow(
          key: const ValueKey('workflow-trigger-time'),
          icon: Icons.schedule_rounded,
          title: tr('Time'),
          subtitle: _time.format(context),
          onTap: () => unawaited(_pickTime()),
        ),
        _pickRow(
          key: const ValueKey('workflow-trigger-until'),
          icon: Icons.event_outlined,
          title: tr('Last day'),
          subtitle: _until == null ? tr('None') : loc.formatMediumDate(_until!),
          onTap: () => unawaited(_pickUntil()),
        ),
        if (_until != null)
          SettingsRow(
            key: const ValueKey('workflow-trigger-until-clear'),
            icon: Icons.close_rounded,
            title: tr('Remove last day'),
            showChevron: false,
            onTap: () => setState(() => _until = null),
          ),
      ],
    ];
  }

  List<Widget> _actionRows(_ActionDraft draft, int index) {
    final options = _options;
    final c = context.tokens.colors;
    final channel = draft.channelId.isEmpty
        ? (_triggerKind.hasMessage
              ? tr('Where it happened')
              : (options.channels.isEmpty
                    ? tr('No channels')
                    : options.channels.first.name))
        : options.channelName(draft.channelId) ?? tr('Where it happened');
    final role =
        options.roleName(draft.roleId) ??
        (options.roles.isEmpty ? tr('No roles') : options.roles.first.name);
    final form =
        options.formTitle(draft.formId) ??
        (options.forms.isEmpty
            ? tr('No forms here yet')
            : options.forms.first.title);
    final k = 'workflow-action-$index';
    final textField = WeCordTextField(
      fieldKey: ValueKey('$k-text'),
      controller: draft.text,
      label: tr('Message'),
      hint: tr('Welcome, {member}!'),
      helperText: _triggerKind.hasMember
          ? tr('You can use {member}, {place} and {date}.')
          : tr('You can use {place} and {date}.'),
      maxLines: 5,
      minLines: 2,
      maxLength: 500,
    );
    return [
      SettingsGroup(
        color: c.well,
        children: [
          _pickRow(
            key: ValueKey('$k-kind'),
            icon: Icons.bolt_rounded,
            title: tr('Action'),
            subtitle: draft.kind.label,
            onTap: () => unawaited(_pickActionKind(draft)),
          ),
          if (draft.kind.usesChannel &&
              _inCircle &&
              !(draft.kind == WorkflowActionKind.createTask &&
                  draft.fromMessage))
            _pickRow(
              key: ValueKey('$k-channel'),
              icon: Icons.tag_rounded,
              title: tr('Channel'),
              subtitle: channel,
              onTap: () => unawaited(() async {
                final picked = await _pickFrom(tr('Channel'), draft.channelId, [
                  if (_triggerKind.hasMessage)
                    PickerOption(value: '', title: tr('Where it happened')),
                  for (final ch in options.channels)
                    PickerOption(value: ch.id, title: ch.name),
                ]);
                if (picked != null && mounted) {
                  setState(() => draft.channelId = picked);
                }
              }()),
            ),
          if (draft.kind == WorkflowActionKind.addRole)
            _pickRow(
              key: ValueKey('$k-role'),
              icon: Icons.military_tech_outlined,
              title: tr('Role'),
              subtitle: role,
              onTap: () => unawaited(() async {
                final picked = await _pickFrom(tr('Role'), draft.roleId, [
                  for (final r in options.roles)
                    PickerOption(value: r.id, title: r.name),
                ]);
                if (picked != null && mounted) {
                  setState(() => draft.roleId = picked);
                }
              }()),
            ),
          if (draft.kind == WorkflowActionKind.sendForm) ...[
            _pickRow(
              key: ValueKey('$k-form'),
              icon: Icons.assignment_outlined,
              title: tr('Form'),
              subtitle: form,
              onTap: () => unawaited(() async {
                final picked = await _pickFrom(tr('Form'), draft.formId, [
                  for (final f in options.forms)
                    PickerOption(value: f.id, title: f.title),
                ]);
                if (picked != null && mounted) {
                  setState(() => draft.formId = picked);
                }
              }()),
            ),
            SettingsRow.toggle(
              key: ValueKey('$k-date'),
              icon: Icons.today_outlined,
              title: tr('Put the date in the title'),
              value: draft.dateInTitle,
              onChanged: (on) => setState(() => draft.dateInTitle = on),
            ),
            SettingsRow.toggle(
              key: ValueKey('$k-deadline'),
              icon: Icons.timer_outlined,
              title: tr('Close after 7 days'),
              value: draft.deadlineDays != null,
              onChanged: (on) =>
                  setState(() => draft.deadlineDays = on ? 7 : null),
            ),
          ],
          if (draft.kind == WorkflowActionKind.createTask &&
              _triggerKind.hasMessage)
            SettingsRow.toggle(
              key: ValueKey('$k-from-message'),
              icon: Icons.task_alt_rounded,
              title: tr('Make the task from the message'),
              value: draft.fromMessage,
              onChanged: (on) => setState(() => draft.fromMessage = on),
            ),
        ],
      ),
      if (draft.kind == WorkflowActionKind.sendMessage ||
          draft.kind == WorkflowActionKind.sendDm) ...[
        const SizedBox(height: 10),
        textField,
      ],
      if (draft.kind == WorkflowActionKind.createTask) ...[
        const SizedBox(height: 10),
        WeCordTextField(
          fieldKey: ValueKey('$k-title'),
          controller: draft.title,
          label: draft.fromMessage ? tr('Title (optional)') : tr('Title'),
          hint: tr('Follow up with {member}'),
          maxLength: 200,
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final options =
        ref.watch(workflowOptionsProvider(widget.scope)).value ??
        const WorkflowOptions();
    final limits = ref.watch(workflowListProvider(widget.scope)).value?.limits;
    final maxActions = limits?.maxActions ?? 5;
    final editing = widget.workflow != null;
    return FormPageFrame(
      pageKey: const ValueKey('workflow-editor-page'),
      title: editing ? tr('Edit workflow') : tr('New workflow'),
      subtitle: tr('When something happens, do something'),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                key: const ValueKey('workflow-editor-error'),
                style: TextStyle(fontSize: 13.5, color: c.dangerText),
              ),
            ),
          WeCordButton(
            key: const ValueKey('workflow-save'),
            label: tr('Save workflow'),
            variant: WeCordButtonVariant.accent,
            size: WeCordButtonSize.large,
            expand: true,
            loading: _busy,
            onPressed: _busy ? null : () => unawaited(_save()),
          ),
        ],
      ),
      child: ListView(
        key: const ValueKey('workflow-editor-list'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          WeCordTextField(
            fieldKey: const ValueKey('workflow-name-field'),
            controller: _name,
            label: tr('Name'),
            hint: tr('Welcome new members'),
            maxLength: 60,
            textInputAction: TextInputAction.next,
          ),
          SettingsSectionHeader(tr('When this happens')),
          SettingsGroup(
            color: c.well,
            children: [
              _pickRow(
                key: const ValueKey('workflow-trigger-kind'),
                icon: Icons.flash_on_rounded,
                title: tr('What starts it'),
                subtitle: _triggerKind.label,
                onTap: () => unawaited(_pickTrigger()),
              ),
              ..._triggerRows(options),
            ],
          ),
          if (_triggerKind == WorkflowTriggerKind.reaction) ...[
            const SizedBox(height: 10),
            WeCordTextField(
              fieldKey: const ValueKey('workflow-emoji-field'),
              controller: _emoji,
              label: tr('Emoji'),
              hint: '👍',
              maxLength: 8,
            ),
          ],
          if (_triggerKind == WorkflowTriggerKind.keyword) ...[
            const SizedBox(height: 10),
            WeCordTextField(
              fieldKey: const ValueKey('workflow-words-field'),
              controller: _words,
              label: tr('Keywords'),
              hint: tr('price, refund'),
              helperText: tr('Separate them with commas. Up to 10.'),
              maxLines: 3,
              minLines: 1,
            ),
          ],
          SettingsSectionHeader(tr('Then do this')),
          for (final (i, draft) in _actions.indexed) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        tr('Step {number}', {'number': i + 1}),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: c.subtle,
                        ),
                      ),
                    ),
                  ),
                  if (_actions.length > 1)
                    WeCordIconButton(
                      key: ValueKey('workflow-action-$i-remove'),
                      tooltip: tr('Remove step {number}', {'number': i + 1}),
                      icon: Icons.close_rounded,
                      variant: WeCordButtonVariant.ghost,
                      onPressed: () => setState(() {
                        _actions.removeAt(i).dispose();
                      }),
                    ),
                ],
              ),
            ),
            ..._actionRows(draft, i),
            const SizedBox(height: 14),
          ],
          if (_actions.length < maxActions)
            WeCordButton(
              key: const ValueKey('workflow-add-action'),
              label: tr('Add a step'),
              icon: Icons.add_rounded,
              onPressed: _addAction,
            ),
          SettingsSectionHeader(tr('Status')),
          SettingsGroup(
            color: c.well,
            children: [
              SettingsRow.toggle(
                key: const ValueKey('workflow-enabled'),
                icon: Icons.play_circle_outline_rounded,
                title: tr('Running'),
                subtitle: tr(
                  'Steps run as you. Messages are marked as automatic.',
                ),
                value: _enabled,
                onChanged: (on) => setState(() => _enabled = on),
              ),
              if (editing)
                SettingsRow(
                  key: const ValueKey('workflow-open-log'),
                  icon: Icons.history_rounded,
                  title: tr('Run log'),
                  onTap: () => unawaited(
                    Navigator.of(context, rootNavigator: true).push<void>(
                      MaterialPageRoute<void>(
                        builder: (context) =>
                            WorkflowRunsPage(workflow: widget.workflow!),
                      ),
                    ),
                  ),
                ),
              if (editing)
                SettingsRow(
                  key: const ValueKey('workflow-delete'),
                  icon: Icons.delete_outline_rounded,
                  title: tr('Delete workflow'),
                  destructive: true,
                  showChevron: false,
                  onTap: () => unawaited(_delete()),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              tr(
                'A workflow follows the same rules as people: blocked members, disappearing messages, the circle rules and restricted chats are never bypassed.',
              ),
              style: TextStyle(fontSize: 12.5, height: 1.4, color: c.subtle),
            ),
          ),
        ],
      ),
    );
  }
}
