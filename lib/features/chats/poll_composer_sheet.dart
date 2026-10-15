import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/poll.dart';

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
  int? _durationHours = 24;
  var _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
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
    setState(() => _optionControllers.removeAt(index).dispose());
  }

  /// Why the form cannot be posted yet, or null when it can. Blank answers
  /// are left out.
  String? _validate(String question, List<String> options) {
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
    return null;
  }

  Future<void> _post() async {
    final question = _questionController.text.trim();
    final options = [
      for (final controller in _optionControllers)
        if (controller.text.trim().isNotEmpty) controller.text.trim(),
    ];
    final problem = _validate(question, options);
    if (problem != null) {
      setState(() => _errorText = problem);
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await ref
          .read(chatsRepositoryProvider)
          .createPoll(
            conversationId: widget.conversationId,
            question: question,
            options: options,
            multi: _multi,
            durationHours: _durationHours,
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on SlowmodeException catch (error) {
      _fail(error.toString());
    } on AutoModBlockedException catch (error) {
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
                value: _multi,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _multi = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                key: const ValueKey('poll-duration-field'),
                initialValue: _durationHours,
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
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _durationHours = value),
              ),
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
