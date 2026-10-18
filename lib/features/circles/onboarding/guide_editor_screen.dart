import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/onboarding/guide_models.dart';
import 'package:wecord/features/circles/onboarding/guide_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Circle settings → Onboarding → Member guide.
void openCircleGuideEditor(
  BuildContext context, {
  required CircleDetail detail,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleGuideEditorScreen(detail: detail),
    ),
  );
}

/// Where managers write the circle's questions (what a new member picks
/// gives roles and points at channels), the newcomer tasks, and where new
/// members are announced.
class CircleGuideEditorScreen extends ConsumerWidget {
  const CircleGuideEditorScreen({required this.detail, super.key});

  final CircleDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circleId = detail.circle.id;
    final config = ref.watch(circleGuideConfigProvider(circleId));
    return config.when(
      loading: () => CirclePageScaffold(
        title: tr('Member guide'),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => CirclePageScaffold(
        title: tr('Member guide'),
        body: CircleEmptyState(
          icon: Icons.explore_outlined,
          title: tr('Could not load the guide.'),
          action: WeCordButton(
            label: tr('Try again'),
            onPressed: () =>
                ref.invalidate(circleGuideConfigProvider(circleId)),
          ),
        ),
      ),
      data: (config) => GuideEditor(detail: detail, initial: config),
    );
  }
}

/// A chip is as wide as its words; long names are cut so it fits a phone.
String _chipText(String text) =>
    text.length <= 26 ? text : '${text.substring(0, 25)}…';

class _OptionDraft {
  _OptionDraft(GuideOptionDraftData data)
    : id = data.id,
      label = TextEditingController(text: data.label),
      emoji = TextEditingController(text: data.emoji ?? ''),
      roleIds = {...data.roleIds},
      channelIds = {...data.channelIds};

  final String? id;
  final TextEditingController label;
  final TextEditingController emoji;
  final Set<String> roleIds;
  final Set<String> channelIds;
  var expanded = false;

  GuideOptionDraftData toData() => GuideOptionDraftData(
    id: id,
    label: label.text,
    emoji: emoji.text,
    roleIds: roleIds.toList(),
    channelIds: channelIds.toList(),
  );

  void dispose() {
    label.dispose();
    emoji.dispose();
  }
}

class _PromptDraft {
  _PromptDraft(GuidePromptDraftData data)
    : id = data.id,
      title = TextEditingController(text: data.title),
      required = data.required,
      singleSelect = data.singleSelect,
      options = [for (final option in data.options) _OptionDraft(option)];

  final String? id;
  final TextEditingController title;
  bool required;
  bool singleSelect;
  final List<_OptionDraft> options;

  GuidePromptDraftData toData() => GuidePromptDraftData(
    id: id,
    title: title.text,
    required: required,
    singleSelect: singleSelect,
    options: [for (final option in options) option.toData()],
  );

  void dispose() {
    title.dispose();
    for (final option in options) {
      option.dispose();
    }
  }
}

class _TaskDraft {
  _TaskDraft(GuideTaskDraftData data)
    : id = data.id,
      title = TextEditingController(text: data.title),
      action = data.action,
      channelId = data.channelId;

  final String? id;
  final TextEditingController title;
  GuideTaskAction action;
  String? channelId;

  GuideTaskDraftData toData() => GuideTaskDraftData(
    id: id,
    title: title.text,
    action: action,
    channelId: action.takesChannel ? channelId : null,
  );

  void dispose() => title.dispose();
}

class GuideEditor extends ConsumerStatefulWidget {
  const GuideEditor({required this.detail, required this.initial, super.key});

  final CircleDetail detail;
  final CircleGuideConfig initial;

  @override
  ConsumerState<GuideEditor> createState() => _GuideEditorState();
}

class _GuideEditorState extends ConsumerState<GuideEditor> {
  late final _prompts = [
    for (final prompt in widget.initial.prompts) _PromptDraft(prompt),
  ];
  late final _tasks = [
    for (final task in widget.initial.tasks) _TaskDraft(task),
  ];
  late String? _greetingChannel = widget.initial.greetingChannelId;
  late String? _greetingSticker = widget.initial.greetingStickerId;
  var _saving = false;
  String? _error;

  String get _circleId => widget.detail.circle.id;

  @override
  void dispose() {
    for (final prompt in _prompts) {
      prompt.dispose();
    }
    for (final task in _tasks) {
      task.dispose();
    }
    super.dispose();
  }

  /// Channels a greeting card can go in: text and announcement channels.
  List<CircleChannel> get _greetingChannels => [
    for (final channel in widget.detail.channels)
      if (channel.kind == CircleChannelKind.text ||
          channel.kind == CircleChannelKind.announcement)
        channel,
  ];

  String? _validate() {
    for (final prompt in _prompts) {
      if (prompt.title.text.trim().isEmpty) {
        return tr('Every question needs its words.');
      }
      if (prompt.options.isEmpty) {
        return tr('Every question needs at least one option.');
      }
      if (prompt.options.any((o) => o.label.text.trim().isEmpty)) {
        return tr('Every option needs its words.');
      }
    }
    for (final task in _tasks) {
      if (task.title.text.trim().isEmpty) {
        return tr('Every task needs its words.');
      }
      if (task.action.needsChannel && task.channelId == null) {
        return tr('Pick the channel to visit.');
      }
    }
    return null;
  }

  String _saveError(Object error) {
    if (error is PostgrestException) {
      final detail = error.details?.toString() ?? '';
      if (detail.startsWith('role_')) {
        return tr(
          'A role you picked can no longer be given by an answer. It has '
          'management permissions, or ranks above one that does.',
        );
      }
      if (error.code == '42501') {
        return tr('You cannot change this part of the guide.');
      }
    }
    return tr('Could not save the guide. Try again.');
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repository = ref.read(circleGuideRepositoryProvider);
    try {
      await repository.savePrompts(_circleId, [
        for (final prompt in _prompts) prompt.toData(),
      ]);
      await repository.saveTasks(_circleId, [
        for (final task in _tasks) task.toData(),
      ]);
      await repository.saveGreeting(
        _circleId,
        channelId: _greetingChannel,
        stickerId: _greetingChannel == null ? null : _greetingSticker,
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _saveError(error);
        });
      }
      return;
    }
    ref.invalidate(circleGuideConfigProvider(_circleId));
    ref.invalidate(circleGuideProvider(_circleId));
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(tr('Member guide saved.'))));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return CirclePageScaffold(
      title: tr('Member guide'),
      actions: [
        WeCordButton(
          key: const ValueKey('guide-editor-save'),
          label: tr('Save'),
          size: WeCordButtonSize.medium,
          loading: _saving,
          onPressed: _saving ? null : () => unawaited(_save()),
        ),
      ],
      body: ListView(
        padding: circlePagePadding(context),
        children: [
          if (_error case final error?)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.dangerSoft,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              child: Text(
                error,
                key: const ValueKey('guide-editor-error'),
                style: TextStyle(
                  color: c.dangerText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SettingsSectionHeader(tr('Questions')),
          _hint(
            tr(
              'Up to {count} questions. What a member picks can give them '
              'roles, which open channels you keep for that role. Only roles '
              'without management permissions can be given this way.',
              {'count': CircleGuideLimits.prompts},
            ),
          ),
          for (final (index, prompt) in _prompts.indexed) ...[
            if (index > 0) const SizedBox(height: 12),
            _PromptEditor(
              key: ObjectKey(prompt),
              index: index,
              draft: prompt,
              detail: widget.detail,
              assignableRoleIds: widget.initial.assignableRoleIds,
              canAttachRoles: widget.detail.canAttachGuideRoles,
              onChanged: () => setState(() {}),
              onRemove: () =>
                  setState(() => _prompts.removeAt(index).dispose()),
            ),
          ],
          if (_prompts.length < CircleGuideLimits.prompts) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: WeCordButton(
                key: const ValueKey('guide-add-prompt'),
                label: tr('Add question'),
                icon: Icons.add_rounded,
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                onPressed: () => setState(
                  () => _prompts.add(
                    _PromptDraft(
                      const GuidePromptDraftData(
                        options: [GuideOptionDraftData()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          SettingsSectionHeader(tr('Tasks for new members')),
          _hint(
            tr(
              'Up to {count} tasks. New members see how many they have done.',
              {'count': CircleGuideLimits.tasks},
            ),
          ),
          for (final (index, task) in _tasks.indexed) ...[
            if (index > 0) const SizedBox(height: 12),
            _TaskEditor(
              key: ObjectKey(task),
              index: index,
              draft: task,
              channels: widget.detail.channels,
              onChanged: () => setState(() {}),
              onRemove: () => setState(() => _tasks.removeAt(index).dispose()),
            ),
          ],
          if (_tasks.length < CircleGuideLimits.tasks) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: WeCordButton(
                key: const ValueKey('guide-add-task'),
                label: tr('Add task'),
                icon: Icons.add_rounded,
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                onPressed: () => setState(
                  () => _tasks.add(
                    _TaskDraft(
                      GuideTaskDraftData(
                        title: GuideTaskAction.sendMessage.suggestedTitle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          SettingsSectionHeader(tr('Greeting')),
          _GreetingEditor(
            circleId: _circleId,
            channels: _greetingChannels,
            channelId: _greetingChannel,
            stickerId: _greetingSticker,
            onChannel: (id) => setState(() => _greetingChannel = id),
            onSticker: (id) => setState(() => _greetingSticker = id),
          ),
        ],
      ),
    );
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: context.tokens.colors.muted,
        ),
      ),
    );
  }
}

class _PromptEditor extends StatelessWidget {
  const _PromptEditor({
    required this.index,
    required this.draft,
    required this.detail,
    required this.assignableRoleIds,
    required this.canAttachRoles,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _PromptDraft draft;
  final CircleDetail detail;
  final Set<String> assignableRoleIds;
  final bool canAttachRoles;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return CircleCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Question {number}', {'number': index + 1}),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.subtle,
                  ),
                ),
              ),
              WeCordIconButton(
                key: ValueKey('guide-remove-prompt-$index'),
                tooltip: tr('Remove question'),
                icon: Icons.delete_outline_rounded,
                variant: WeCordButtonVariant.ghost,
                onPressed: onRemove,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WeCordTextField(
                  fieldKey: ValueKey('guide-prompt-title-$index'),
                  controller: draft.title,
                  hint: tr('What are you into?'),
                  minLines: 1,
                  maxLines: 2,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(
                      CircleGuideLimits.promptTitle,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    WeCordChip(
                      key: ValueKey('guide-prompt-required-$index'),
                      label: tr('Required'),
                      icon: draft.required ? Icons.check_rounded : null,
                      selected: draft.required,
                      onPressed: () {
                        draft.required = !draft.required;
                        onChanged();
                      },
                    ),
                    WeCordChip(
                      key: ValueKey('guide-prompt-single-$index'),
                      label: tr('Pick only one'),
                      icon: draft.singleSelect ? Icons.check_rounded : null,
                      selected: draft.singleSelect,
                      onPressed: () {
                        draft.singleSelect = !draft.singleSelect;
                        onChanged();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final (optionIndex, option) in draft.options.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _OptionEditor(
                      key: ObjectKey(option),
                      promptIndex: index,
                      index: optionIndex,
                      draft: option,
                      detail: detail,
                      assignableRoleIds: assignableRoleIds,
                      canAttachRoles: canAttachRoles,
                      onChanged: onChanged,
                      onRemove: () {
                        draft.options.removeAt(optionIndex).dispose();
                        onChanged();
                      },
                    ),
                  ),
                if (draft.options.length < CircleGuideLimits.options)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: WeCordButton(
                      key: ValueKey('guide-add-option-$index'),
                      label: tr('Add option'),
                      icon: Icons.add_rounded,
                      variant: WeCordButtonVariant.ghost,
                      size: WeCordButtonSize.small,
                      onPressed: () {
                        draft.options.add(
                          _OptionDraft(const GuideOptionDraftData()),
                        );
                        onChanged();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionEditor extends StatelessWidget {
  const _OptionEditor({
    required this.promptIndex,
    required this.index,
    required this.draft,
    required this.detail,
    required this.assignableRoleIds,
    required this.canAttachRoles,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int promptIndex;
  final int index;
  final _OptionDraft draft;
  final CircleDetail detail;
  final Set<String> assignableRoleIds;
  final bool canAttachRoles;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final roles = [
      for (final role in detail.roles)
        if (!role.isDefault) role,
    ];
    final summary = [
      if (draft.roleIds.isNotEmpty)
        tr('{count} roles', {'count': draft.roleIds.length}),
      if (draft.channelIds.isNotEmpty)
        tr('{count} channels', {'count': draft.channelIds.length}),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 52,
                child: WeCordTextField(
                  fieldKey: ValueKey('guide-option-emoji-$promptIndex-$index'),
                  controller: draft.emoji,
                  hint: '🙂',
                  inputFormatters: [LengthLimitingTextInputFormatter(8)],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: WeCordTextField(
                  fieldKey: ValueKey('guide-option-label-$promptIndex-$index'),
                  controller: draft.label,
                  hint: tr('Option {number}', {'number': index + 1}),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(
                      CircleGuideLimits.optionLabel,
                    ),
                  ],
                ),
              ),
              WeCordIconButton(
                key: ValueKey('guide-remove-option-$promptIndex-$index'),
                tooltip: tr('Remove option'),
                icon: Icons.remove_circle_outline,
                variant: WeCordButtonVariant.ghost,
                onPressed: onRemove,
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: WeCordButton(
              key: ValueKey('guide-option-more-$promptIndex-$index'),
              label: summary.isEmpty
                  ? tr('Roles and channels')
                  : '${tr('Roles and channels')} · $summary',
              icon: draft.expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              variant: WeCordButtonVariant.ghost,
              size: WeCordButtonSize.small,
              onPressed: () {
                draft.expanded = !draft.expanded;
                onChanged();
              },
            ),
          ),
          if (draft.expanded) ...[
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Gives these roles'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: c.subtle,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (roles.isEmpty)
                    Text(
                      tr('This circle has no roles yet.'),
                      style: TextStyle(fontSize: 13, color: c.muted),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final role in roles)
                          _roleChip(role, draft, assignableRoleIds),
                      ],
                    ),
                  if (roles.any((r) => !assignableRoleIds.contains(r.id)))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        tr(
                          'Roles with a lock have management permissions and '
                          'cannot be given.',
                        ),
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                    ),
                  if (!canAttachRoles)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        tr(
                          'Only members who can manage roles can add roles here.',
                        ),
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    tr('Points at these channels'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: c.subtle,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final channel in detail.channels)
                        WeCordChip(
                          key: ValueKey(
                            'guide-option-channel-$promptIndex-$index-${channel.id}',
                          ),
                          label: _chipText('#${channel.name}'),
                          selected: draft.channelIds.contains(channel.id),
                          onPressed: () {
                            if (!draft.channelIds.add(channel.id)) {
                              draft.channelIds.remove(channel.id);
                            } else if (draft.channelIds.length >
                                CircleGuideLimits.channelsPerOption) {
                              draft.channelIds.remove(channel.id);
                            }
                            onChanged();
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _roleChip(
    CircleRole role,
    _OptionDraft draft,
    Set<String> assignableRoleIds,
  ) {
    final selected = draft.roleIds.contains(role.id);
    final allowed = assignableRoleIds.contains(role.id);
    // A role already on the option stays visible so it can be taken off,
    // even when it can no longer be given.
    final canChange = selected || (allowed && canAttachRoles);
    return WeCordChip(
      key: ValueKey('guide-option-role-$promptIndex-$index-${role.id}'),
      label: _chipText(role.name),
      icon: allowed ? null : Icons.lock_outline_rounded,
      selected: selected,
      semanticLabel: allowed
          ? role.name
          : tr('{role}, has management permissions and cannot be given', {
              'role': role.name,
            }),
      onPressed: canChange
          ? () {
              if (selected) {
                draft.roleIds.remove(role.id);
              } else if (draft.roleIds.length <
                  CircleGuideLimits.rolesPerOption) {
                draft.roleIds.add(role.id);
              }
              onChanged();
            }
          : null,
    );
  }
}

class _TaskEditor extends StatelessWidget {
  const _TaskEditor({
    required this.index,
    required this.draft,
    required this.channels,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _TaskDraft draft;
  final List<CircleChannel> channels;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final pickable = [
      for (final channel in channels)
        if (!channel.isVoice) channel,
    ];
    return CircleCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Task {number}', {'number': index + 1}),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.subtle,
                  ),
                ),
              ),
              WeCordIconButton(
                key: ValueKey('guide-remove-task-$index'),
                tooltip: tr('Remove task'),
                icon: Icons.delete_outline_rounded,
                variant: WeCordButtonVariant.ghost,
                onPressed: onRemove,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in GuideTaskAction.values)
                      WeCordChip(
                        key: ValueKey('guide-task-kind-$index-${action.value}'),
                        label: action.label,
                        selected: draft.action == action,
                        onPressed: () {
                          final previous = draft.action;
                          draft.action = action;
                          if (!action.takesChannel) {
                            draft.channelId = null;
                          }
                          // Keep the words unless they were the suggestion.
                          if (draft.title.text.trim().isEmpty ||
                              draft.title.text == previous.suggestedTitle) {
                            draft.title.text = action.suggestedTitle;
                          }
                          onChanged();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                WeCordTextField(
                  fieldKey: ValueKey('guide-task-title-$index'),
                  controller: draft.title,
                  hint: tr('What should they do?'),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(
                      CircleGuideLimits.taskTitle,
                    ),
                  ],
                ),
                if (draft.action.takesChannel) ...[
                  const SizedBox(height: 10),
                  Text(
                    draft.action.needsChannel
                        ? tr('Channel to visit')
                        : tr('Channel to write in (optional)'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: c.subtle,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!draft.action.needsChannel)
                        WeCordChip(
                          key: ValueKey('guide-task-channel-$index-any'),
                          label: tr('Any channel'),
                          selected: draft.channelId == null,
                          onPressed: () {
                            draft.channelId = null;
                            onChanged();
                          },
                        ),
                      for (final channel in pickable)
                        WeCordChip(
                          key: ValueKey(
                            'guide-task-channel-$index-${channel.id}',
                          ),
                          label: _chipText('#${channel.name}'),
                          selected: draft.channelId == channel.id,
                          onPressed: () {
                            draft.channelId = channel.id;
                            onChanged();
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GreetingEditor extends ConsumerWidget {
  const _GreetingEditor({
    required this.circleId,
    required this.channels,
    required this.channelId,
    required this.stickerId,
    required this.onChannel,
    required this.onSticker,
  });

  final String circleId;
  final List<CircleChannel> channels;
  final String? channelId;
  final String? stickerId;
  final ValueChanged<String?> onChannel;
  final ValueChanged<String?> onSticker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final on = channelId != null;
    final stickers = [
      for (final emoji
          in ref.watch(circleEmojisProvider(circleId)).value ??
              const <CircleEmoji>[])
        if (emoji.kind == CircleEmojiKind.sticker) emoji,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          separatorIndent: 14,
          footer: tr(
            'A card in the channel greets each new member and has a Say '
            'hello button.',
          ),
          children: [
            SettingsRow.toggle(
              key: const ValueKey('guide-greeting-toggle'),
              icon: Icons.waving_hand_outlined,
              tone: SettingsTone.success,
              title: tr('Greet new members'),
              value: on,
              onChanged: (value) {
                if (value) {
                  onChannel(channels.isEmpty ? null : channels.first.id);
                } else {
                  onChannel(null);
                  onSticker(null);
                }
              },
            ),
          ],
        ),
        if (on) ...[
          const SizedBox(height: 12),
          CircleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Channel'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: c.subtle,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final channel in channels)
                      WeCordChip(
                        key: ValueKey('guide-greeting-channel-${channel.id}'),
                        label: _chipText('#${channel.name}'),
                        selected: channelId == channel.id,
                        onPressed: () => onChannel(channel.id),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  tr('Sticker for Say hello'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: c.subtle,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    WeCordChip(
                      key: const ValueKey('guide-greeting-sticker-none'),
                      label: tr('A waving hand'),
                      selected: stickerId == null,
                      onPressed: () => onSticker(null),
                    ),
                    for (final sticker in stickers)
                      WeCordChip(
                        key: ValueKey('guide-greeting-sticker-${sticker.id}'),
                        label: _chipText(sticker.name),
                        selected: stickerId == sticker.id,
                        onPressed: () => onSticker(sticker.id),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
