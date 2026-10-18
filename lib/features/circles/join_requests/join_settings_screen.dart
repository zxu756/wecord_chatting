import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/join_requests/join_request_models.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

void openCircleJoinSettings(BuildContext context, CircleDetail detail) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) =>
          CircleJoinSettingsScreen(circleId: detail.circle.id),
    ),
  );
}

/// Circle settings → Join mode: how people get in and, when they apply, the
/// questions they answer.
class CircleJoinSettingsScreen extends ConsumerWidget {
  const CircleJoinSettingsScreen({required this.circleId, super.key});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(circleJoinSettingsProvider(circleId));
    return settings.when(
      loading: () => CirclePageScaffold(
        title: tr('Join mode'),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => CirclePageScaffold(
        title: tr('Join mode'),
        body: CircleEmptyState(
          icon: Icons.how_to_reg_outlined,
          title: tr('Could not load join settings.'),
          action: WeCordButton(
            label: tr('Try again'),
            onPressed: () =>
                ref.invalidate(circleJoinSettingsProvider(circleId)),
          ),
        ),
      ),
      data: (settings) =>
          JoinSettingsEditor(circleId: circleId, initial: settings),
    );
  }
}

/// One question being edited.
class _Draft {
  _Draft(JoinQuestion question)
    : id = question.id,
      kind = question.kind,
      required = question.required,
      prompt = TextEditingController(text: question.prompt),
      options = [
        for (final option in question.options)
          TextEditingController(text: option),
      ];

  final String id;
  JoinQuestionKind kind;
  bool required;
  final TextEditingController prompt;
  final List<TextEditingController> options;

  void dispose() {
    prompt.dispose();
    for (final option in options) {
      option.dispose();
    }
  }

  JoinQuestion toQuestion() => JoinQuestion(
    id: id,
    kind: kind,
    prompt: prompt.text,
    options: [for (final option in options) option.text],
    required: required,
  );
}

class JoinSettingsEditor extends ConsumerStatefulWidget {
  const JoinSettingsEditor({
    required this.circleId,
    required this.initial,
    super.key,
  });

  final String circleId;
  final CircleJoinSettings initial;

  @override
  ConsumerState<JoinSettingsEditor> createState() => _JoinSettingsEditorState();
}

class _JoinSettingsEditorState extends ConsumerState<JoinSettingsEditor> {
  late var _mode = widget.initial.mode;
  late final _drafts = [
    for (final question in widget.initial.questions) _Draft(question),
  ];
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final questions = [for (final draft in _drafts) draft.toQuestion()];
    if (_mode == CircleJoinMode.apply &&
        questions.any((question) => !question.isValid)) {
      setState(
        () => _error = tr(
          'Every question needs its words, and a choice needs two or more '
          'options.',
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(joinRequestsRepositoryProvider)
          .saveSettings(
            widget.circleId,
            CircleJoinSettings(
              mode: _mode,
              // Questions are kept while another mode is chosen, but only
              // valid ones can be saved.
              questions: [
                for (final question in questions)
                  if (question.isValid) question,
              ],
            ),
          );
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('Could not save join settings. Try again.');
        });
      }
      return;
    }
    ref.invalidate(circleJoinSettingsProvider(widget.circleId));
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(tr('Join settings saved.'))));
      Navigator.of(context).pop();
    }
  }

  void _addQuestion() {
    setState(() {
      _drafts.add(
        _Draft(
          const JoinQuestion(id: '', kind: JoinQuestionKind.text, prompt: ''),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return CirclePageScaffold(
      title: tr('Join mode'),
      actions: [
        WeCordButton(
          key: const ValueKey('join-settings-save'),
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
                key: const ValueKey('join-settings-error'),
                style: TextStyle(
                  color: c.dangerText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SettingsGroup(
            separatorIndent: 14,
            children: [
              for (final mode in CircleJoinMode.values)
                _ModeRow(
                  mode: mode,
                  selected: _mode == mode,
                  onTap: () => setState(() => _mode = mode),
                ),
            ],
          ),
          if (_mode == CircleJoinMode.apply) ...[
            SettingsSectionHeader(tr('Questions')),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
              child: Text(
                tr(
                  'Up to {count} questions people answer when they ask to '
                  'join. Moderators read the answers before they decide.',
                  {'count': joinQuestionLimit},
                ),
                style: TextStyle(fontSize: 13, height: 1.4, color: c.muted),
              ),
            ),
            for (final (index, draft) in _drafts.indexed) ...[
              if (index > 0) const SizedBox(height: 12),
              _QuestionEditor(
                key: ObjectKey(draft),
                index: index,
                draft: draft,
                onChanged: () => setState(() {}),
                onRemove: () => setState(() {
                  _drafts.removeAt(index).dispose();
                }),
              ),
            ],
            if (_drafts.length < joinQuestionLimit) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: WeCordButton(
                  key: const ValueKey('join-add-question'),
                  label: tr('Add question'),
                  icon: Icons.add_rounded,
                  variant: WeCordButtonVariant.secondary,
                  size: WeCordButtonSize.small,
                  onPressed: _addQuestion,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A radio-style row for one join mode.
class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final CircleJoinMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      key: ValueKey('join-mode-${mode.key}'),
      selected: selected,
      semanticLabel: '${mode.label}. ${mode.description}',
      excludeSemantics: true,
      onPressed: onTap,
      builder: (context, states) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: AnimatedContainer(
                duration: WeCordMotion.quick,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? c.accent : Colors.transparent,
                  border: Border.all(
                    color: selected ? c.accent : c.track,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, size: 14, color: c.onAccent)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mode.description,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionEditor extends StatelessWidget {
  const _QuestionEditor({
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _Draft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final isChoice = draft.kind == JoinQuestionKind.choice;
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
                key: ValueKey('join-remove-question-$index'),
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
                  fieldKey: ValueKey('join-question-$index'),
                  controller: draft.prompt,
                  minLines: 1,
                  maxLines: 3,
                  inputFormatters: [LengthLimitingTextInputFormatter(200)],
                  hint: tr('Why do you want to join?'),
                ),
                const SizedBox(height: 12),
                WeCordSegmented<JoinQuestionKind>(
                  expand: true,
                  semanticLabel: tr('Answer type'),
                  segments: [
                    WeCordSegment(
                      key: ValueKey('join-kind-text-$index'),
                      value: JoinQuestionKind.text,
                      label: tr('Written answer'),
                    ),
                    WeCordSegment(
                      key: ValueKey('join-kind-choice-$index'),
                      value: JoinQuestionKind.choice,
                      label: tr('Pick one'),
                    ),
                  ],
                  selected: draft.kind,
                  onChanged: (kind) {
                    draft.kind = kind;
                    if (kind == JoinQuestionKind.choice &&
                        draft.options.length < 2) {
                      while (draft.options.length < 2) {
                        draft.options.add(TextEditingController());
                      }
                    }
                    onChanged();
                  },
                ),
                if (isChoice) ...[
                  const SizedBox(height: 12),
                  for (final (optionIndex, option) in draft.options.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: WeCordTextField(
                              fieldKey: ValueKey(
                                'join-option-$index-$optionIndex',
                              ),
                              controller: option,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(100),
                              ],
                              hint: tr('Option {number}', {
                                'number': optionIndex + 1,
                              }),
                            ),
                          ),
                          if (draft.options.length > 2)
                            WeCordIconButton(
                              tooltip: tr('Remove option'),
                              icon: Icons.remove_circle_outline,
                              variant: WeCordButtonVariant.ghost,
                              onPressed: () {
                                draft.options.removeAt(optionIndex).dispose();
                                onChanged();
                              },
                            ),
                        ],
                      ),
                    ),
                  if (draft.options.length < 8)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: WeCordButton(
                        key: ValueKey('join-add-option-$index'),
                        label: tr('Add option'),
                        icon: Icons.add_rounded,
                        variant: WeCordButtonVariant.ghost,
                        size: WeCordButtonSize.small,
                        onPressed: () {
                          draft.options.add(TextEditingController());
                          onChanged();
                        },
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('Required'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ),
                    WeCordSwitch(
                      key: ValueKey('join-required-$index'),
                      semanticLabel: tr('Required'),
                      value: draft.required,
                      onChanged: (value) {
                        draft.required = value;
                        onChanged();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
