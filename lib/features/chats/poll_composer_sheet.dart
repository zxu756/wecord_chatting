import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/polls_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/poll.dart';

/// The dropdown's "pick a day and time" entry (no real duration is -1).
const _pickTime = -1;

/// Opens the poll form for [conversationId]. Returns true once the poll is
/// posted.
Future<bool?> showPollComposerSheet(
  BuildContext context, {
  required String conversationId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => PollComposerSheet(conversationId: conversationId),
  );
}

/// The poll form: a question, 2 to 10 answers, whether several answers are
/// allowed, and how long voting lasts.
class PollComposerSheet extends ConsumerStatefulWidget {
  const PollComposerSheet({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<PollComposerSheet> createState() => _PollComposerSheetState();
}

class _PollComposerSheetState extends ConsumerState<PollComposerSheet> {
  final _questionController = TextEditingController();
  final _optionControllers = [TextEditingController(), TextEditingController()];
  var _multi = false;
  var _moreOptions = false;
  var _quiz = false;
  var _anonymous = false;
  var _allowAdd = false;

  /// The index (among all answer fields) of a quiz's right answer.
  int? _correct;
  final _explanationController = TextEditingController();

  /// A closing time picked by hand; wins over [_durationHours].
  DateTime? _closesAt;
  int? _durationHours = 24;
  var _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    _explanationController.dispose();
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= PollAttachment.maxOptions) {
      return;
    }
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= PollAttachment.minOptions) {
      return;
    }
    setState(() {
      _optionControllers.removeAt(index).dispose();
      final correct = _correct;
      if (correct != null) {
        _correct = correct == index
            ? null
            : correct > index
            ? correct - 1
            : correct;
      }
    });
  }

  /// Asks for a day and a time up to 30 days ahead.
  Future<void> _pickClosingTime() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _closesAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (day == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _closesAt ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) {
      return;
    }
    final picked = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    setState(() {
      _closesAt = picked;
      _errorText = null;
    });
  }

  /// Why the form cannot be posted yet, or null when it can. Blank answers
  /// are left out.
  String? _validate(String question, List<String> options, {int? correct}) {
    if (question.isEmpty) {
      return tr('Ask a question.');
    }
    if (options.length < PollAttachment.minOptions) {
      return tr('Add at least {count} answers.', {
        'count': PollAttachment.minOptions,
      });
    }
    final distinct = {for (final option in options) option.toLowerCase()};
    if (distinct.length != options.length) {
      return tr('Answers must be different.');
    }
    if (_quiz && correct == null) {
      return tr('Mark the right answer.');
    }
    final closes = _closesAt;
    if (closes != null &&
        closes.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      return tr('Pick a closing time in the future.');
    }
    return null;
  }

  Future<void> _post() async {
    final question = _questionController.text.trim();
    final options = <String>[];
    int? correct;
    for (final (index, controller) in _optionControllers.indexed) {
      if (controller.text.trim().isEmpty) {
        continue;
      }
      if (_quiz && _correct == index) {
        correct = options.length;
      }
      options.add(controller.text.trim());
    }
    final problem = _validate(question, options, correct: correct);
    if (problem != null) {
      setState(() => _errorText = problem);
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final draft = PollDraft(
      question: question,
      options: options,
      multi: _multi && !_quiz,
      durationHours: _closesAt == null ? _durationHours : null,
      closesAt: _closesAt,
      quizCorrectIndex: _quiz ? correct : null,
      quizExplanation: _quiz ? _explanationController.text : '',
      anonymous: _anonymous,
      allowAddOptions: _allowAdd && !_quiz,
    );
    try {
      if (draft.usesNewFeatures) {
        await ref
            .read(pollsRepositoryProvider)
            .createPoll(widget.conversationId, draft);
      } else {
        await ref
            .read(chatsRepositoryProvider)
            .createPoll(
              conversationId: widget.conversationId,
              question: question,
              options: options,
              multi: _multi,
              durationHours: _durationHours,
            );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on SlowmodeException catch (error) {
      _fail(error.toString());
    } on SendRefusedException catch (error) {
      _fail(error.toString());
    } catch (_) {
      _fail(tr('Could not post the poll. Try again.'));
    }
  }

  void _fail(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      _errorText = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        // Lifts the sheet above the keyboard, so the form scrolls within
        // the space left instead of hiding behind it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Create poll'), style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('poll-question-field'),
                controller: _questionController,
                autofocus: true,
                enabled: !_saving,
                maxLength: PollAttachment.maxQuestionLength,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: tr('Question'),
                ),
              ),
              const SizedBox(height: 4),
              Text(tr('Answers'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final (index, controller) in _optionControllers.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: ValueKey('poll-option-field-$index'),
                          controller: controller,
                          enabled: !_saving,
                          maxLength: PollAttachment.maxOptionLength,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: tr('Answer {number}', {
                              'number': index + 1,
                            }),
                            counterText: '',
                          ),
                        ),
                      ),
                      if (_quiz)
                        IconButton(
                          key: ValueKey('poll-correct-$index'),
                          tooltip: tr('Mark answer {number} as right', {
                            'number': index + 1,
                          }),
                          isSelected: _correct == index,
                          onPressed: _saving
                              ? null
                              : () => setState(() => _correct = index),
                          icon: const Icon(Icons.check_circle_outline),
                          selectedIcon: const Icon(Icons.check_circle),
                        ),
                      IconButton(
                        tooltip: tr('Remove answer {number}', {
                          'number': index + 1,
                        }),
                        onPressed:
                            _saving ||
                                _optionControllers.length <=
                                    PollAttachment.minOptions
                            ? null
                            : () => _removeOption(index),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('poll-add-option'),
                  onPressed:
                      _saving ||
                          _optionControllers.length >= PollAttachment.maxOptions
                      ? null
                      : _addOption,
                  icon: const Icon(Icons.add),
                  label: Text(tr('Add answer')),
                ),
              ),
              SwitchListTile(
                key: const ValueKey('poll-multi-switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Allow multiple answers')),
                value: _multi && !_quiz,
                onChanged: _saving || _quiz
                    ? null
                    : (value) => setState(() => _multi = value),
              ),
              const SizedBox(height: 8),
              KeyedSubtree(
                key: ValueKey(_closesAt?.millisecondsSinceEpoch),
                child: DropdownButtonFormField<int?>(
                  isExpanded: true,
                  key: const ValueKey('poll-duration-field'),
                  initialValue: _closesAt == null ? _durationHours : _pickTime,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: tr('Duration'),
                  ),
                  items: [
                    for (final hours in pollDurationHours)
                      DropdownMenuItem(
                        value: hours,
                        child: Text(pollDurationLabel(hours)),
                      ),
                    DropdownMenuItem(
                      value: _pickTime,
                      child: Text(
                        _closesAt == null
                            ? tr('Pick a day and time…')
                            : tr('Closes {time}', {
                                'time': MaterialLocalizations.of(
                                  context,
                                ).formatShortDate(_closesAt!),
                              }),
                      ),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value == _pickTime) {
                            unawaited(_pickClosingTime());
                            return;
                          }
                          setState(() {
                            _durationHours = value;
                            _closesAt = null;
                          });
                        },
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('poll-more-options'),
                  onPressed: () => setState(() => _moreOptions = !_moreOptions),
                  icon: Icon(
                    _moreOptions ? Icons.expand_less : Icons.expand_more,
                  ),
                  label: Text(
                    _moreOptions ? tr('Fewer options') : tr('More options'),
                  ),
                ),
              ),
              if (_moreOptions) ...[
                SwitchListTile(
                  key: const ValueKey('poll-quiz-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Quiz')),
                  subtitle: Text(
                    tr(
                      'One right answer, shown with an explanation after people vote',
                    ),
                  ),
                  value: _quiz,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _quiz = value;
                          if (!value) {
                            _correct = null;
                          }
                        }),
                ),
                if (_quiz) ...[
                  const SizedBox(height: 4),
                  TextField(
                    key: const ValueKey('poll-explanation-field'),
                    controller: _explanationController,
                    enabled: !_saving,
                    maxLength: 500,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: tr('Explanation (optional)'),
                    ),
                  ),
                ],
                SwitchListTile(
                  key: const ValueKey('poll-anonymous-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Anonymous votes')),
                  subtitle: Text(
                    tr('Everyone sees the totals, nobody sees who voted'),
                  ),
                  value: _anonymous,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _anonymous = value),
                ),
                SwitchListTile(
                  key: const ValueKey('poll-allow-add-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Members can add answers')),
                  value: _allowAdd && !_quiz,
                  onChanged: _saving || _quiz
                      ? null
                      : (value) => setState(() => _allowAdd = value),
                ),
              ],
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorText!,
                  key: const ValueKey('poll-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(tr('Cancel')),
                  ),
                  FilledButton(
                    key: const ValueKey('poll-post-button'),
                    onPressed: _saving ? null : _post,
                    child: Text(tr('Post poll')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
