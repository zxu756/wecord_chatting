import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/events2/event_widgets.dart';
import 'package:wecord/shared/models/event_extras.dart';
import 'package:wecord/features/events2/events2_repository.dart';
import 'package:wecord/features/notifications/device_time_zone.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What the event form holds of Events 2.0: the repeat, capacity, questions and
/// cover. The editors read [options] when they save.
class EventOptionsController extends ChangeNotifier {
  EventOptionsController([EventOptions? initial])
    : _options = (initial ?? const EventOptions()).copyWith();

  EventOptions _options;

  /// The options with this device's time zone, as they are sent.
  EventOptions get options => EventOptions(
    recurrence: _options.recurrence,
    coverPath: _options.coverPath,
    questions: _options.questions,
    capacity: _options.capacity,
    timeZone: _options.recurrence == EventRecurrence.none
        ? null
        : deviceTimeZone() ?? _options.timeZone,
    call: _options.call,
  );

  EventRecurrence get recurrence => _options.recurrence;
  String? get coverPath => _options.coverPath;
  List<EventQuestion> get questions => _options.questions;
  int? get capacity => _options.capacity;

  /// Whether the event carries a call; null where it cannot (circle events).
  bool? get call => _options.call;

  void setRecurrence(EventRecurrence value) {
    _options = _options.copyWith(recurrence: value);
    notifyListeners();
  }

  void setCover(String? path) {
    _options = _options.copyWith(coverPath: path);
    notifyListeners();
  }

  void setQuestions(List<EventQuestion> value) {
    _options = _options.copyWith(questions: value);
    notifyListeners();
  }

  void setCapacity(int? value) {
    _options = _options.copyWith(capacity: value);
    notifyListeners();
  }

  void setCall(bool value) {
    _options = _options.copyWith(call: value);
    notifyListeners();
  }
}

/// The rows of the event form for Events 2.0: repeat, seats, questions and a
/// cover picture.
class EventOptionsSection extends ConsumerStatefulWidget {
  const EventOptionsSection({
    required this.controller,
    required this.kind,
    required this.scopeId,
    this.enabled = true,
    super.key,
  });

  final EventOptionsController controller;
  final EventKind kind;

  /// The conversation (chat events) or the circle whose folder the cover goes
  /// into.
  final String scopeId;
  final bool enabled;

  @override
  ConsumerState<EventOptionsSection> createState() =>
      _EventOptionsSectionState();
}

class _EventOptionsSectionState extends ConsumerState<EventOptionsSection> {
  var _uploading = false;
  String? _coverError;

  EventOptionsController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(EventOptionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickRepeat() async {
    final picked = await showWeCordSheet<EventRecurrence>(
      context,
      title: tr('Repeat'),
      builder: (context, _) => _RepeatChoices(selected: _controller.recurrence),
    );
    if (picked != null) {
      _controller.setRecurrence(picked);
    }
  }

  Future<void> _pickCapacity() async {
    final result = await showWeCordSheet<_CapacityResult>(
      context,
      title: tr('Seats'),
      builder: (context, _) => _CapacityForm(initial: _controller.capacity),
    );
    if (result != null) {
      _controller.setCapacity(result.capacity);
    }
  }

  Future<void> _editQuestions() async {
    final result = await showWeCordSheet<List<EventQuestion>>(
      context,
      title: tr('Questions'),
      detents: const [0.92],
      builder: (context, scrollController) => EventQuestionsEditor(
        initial: _controller.questions,
        scrollController: scrollController,
      ),
    );
    if (result != null) {
      _controller.setQuestions(result);
    }
  }

  Future<void> _pickCover() async {
    setState(() {
      _coverError = null;
    });
    try {
      final image = await ref.read(imagePickerServiceProvider).pickImage();
      if (image == null || !mounted) {
        return;
      }
      setState(() => _uploading = true);
      final path = await ref
          .read(events2RepositoryProvider)
          .uploadCover(widget.kind, widget.scopeId, image);
      if (!mounted) {
        return;
      }
      _controller.setCover(path);
      setState(() => _uploading = false);
    } on Object {
      if (mounted) {
        setState(() {
          _uploading = false;
          _coverError = tr("The picture didn't upload. Try again.");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final enabled = widget.enabled && !_uploading;
    final questions = _controller.questions;
    final capacity = _controller.capacity;
    final cover = _controller.coverPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            tr('More options'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.muted,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SettingsGroup(
          separatorIndent: 58,
          color: c.well,
          children: [
            if (_controller.call != null)
              SettingsRow.toggle(
                key: const ValueKey('event-option-call'),
                icon: Icons.call_outlined,
                title: tr('Attach a call'),
                subtitle: tr(
                  'People can join from the event, and reminders open the call.',
                ),
                value: _controller.call ?? false,
                onChanged: enabled ? _controller.setCall : null,
              ),
            SettingsRow(
              key: const ValueKey('event-option-repeat'),
              icon: Icons.repeat_rounded,
              title: tr('Repeat'),
              value: _controller.recurrence.label,
              onTap: enabled ? _pickRepeat : null,
            ),
            SettingsRow(
              key: const ValueKey('event-option-capacity'),
              icon: Icons.event_seat_outlined,
              title: tr('Seats'),
              value: capacity == null ? tr('No limit') : '$capacity',
              onTap: enabled ? _pickCapacity : null,
            ),
            SettingsRow(
              key: const ValueKey('event-option-questions'),
              icon: Icons.quiz_outlined,
              title: tr('Questions for people signing up'),
              value: questions.isEmpty ? tr('None') : '${questions.length}',
              onTap: enabled ? _editQuestions : null,
            ),
            SettingsRow(
              key: const ValueKey('event-option-cover'),
              icon: Icons.image_outlined,
              title: tr('Cover picture'),
              value: _uploading
                  ? tr('Uploading…')
                  : cover == null
                  ? tr('None')
                  : tr('Added'),
              onTap: enabled ? _pickCover : null,
              trailing: cover == null || _uploading
                  ? null
                  : WeCordIconButton(
                      tooltip: tr('Remove cover picture'),
                      icon: Icons.close_rounded,
                      size: 32,
                      iconSize: 16,
                      variant: WeCordButtonVariant.ghost,
                      onPressed: widget.enabled
                          ? () => _controller.setCover(null)
                          : null,
                    ),
            ),
          ],
        ),
        if (_controller.recurrence != EventRecurrence.none)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Text(
              tr(
                'The next one is made when this one starts, at the same time '
                'of day in your time zone, also when the clocks change.',
              ),
              key: const ValueKey('event-repeat-note'),
              style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
            ),
          ),
        if (cover != null && !_uploading)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: EventCoverBanner(kind: widget.kind, coverPath: cover),
          ),
        if (_coverError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _coverError!,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: c.dangerText,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RepeatChoices extends StatelessWidget {
  const _RepeatChoices({required this.selected});

  final EventRecurrence selected;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        SettingsGroup(
          separatorIndent: 14,
          children: [
            for (final value in EventRecurrence.values)
              SettingsRow(
                key: ValueKey('event-repeat-${value.name}'),
                title: value.label,
                showChevron: false,
                trailing: value == selected
                    ? Icon(Icons.check_rounded, color: c.accentText)
                    : null,
                onTap: () => Navigator.of(context).pop(value),
              ),
          ],
        ),
      ],
    );
  }
}

class _CapacityResult {
  const _CapacityResult(this.capacity);

  final int? capacity;
}

class _CapacityForm extends StatefulWidget {
  const _CapacityForm({required this.initial});

  final int? initial;

  @override
  State<_CapacityForm> createState() => _CapacityFormState();
}

class _CapacityFormState extends State<_CapacityForm> {
  late final _controller = TextEditingController(
    text: widget.initial?.toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop(const _CapacityResult(null));
      return;
    }
    final value = int.tryParse(text);
    if (value == null || value < 1 || value > EventOptions.maxCapacity) {
      setState(() {
        _error = tr('Enter a number from 1 to {max}.', {
          'max': EventOptions.maxCapacity,
        });
      });
      return;
    }
    Navigator.of(context).pop(_CapacityResult(value));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 +
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          tr(
            'When every seat is taken, more people join a waiting list and '
            'move up when someone drops out.',
          ),
          style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.4),
        ),
        const SizedBox(height: 12),
        WeCordTextField(
          fieldKey: const ValueKey('event-capacity-field'),
          controller: _controller,
          label: tr('Seats'),
          hint: tr('Leave empty for no limit'),
          errorText: _error,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 5,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: WeCordButton(
                label: tr('No limit'),
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.large,
                expand: true,
                onPressed: () =>
                    Navigator.of(context).pop(const _CapacityResult(null)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: WeCordButton(
                key: const ValueKey('event-capacity-save'),
                label: tr('Done'),
                variant: WeCordButtonVariant.accent,
                size: WeCordButtonSize.large,
                expand: true,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A question in the editor, with the fields it is typed into.
class _QuestionDraft {
  _QuestionDraft(EventQuestion question)
    : id = question.id,
      type = question.type,
      required = question.required,
      label = TextEditingController(text: question.label),
      options = TextEditingController(text: question.options.join('\n'));

  final String id;
  EventQuestionType type;
  bool required;
  final TextEditingController label;
  final TextEditingController options;

  void dispose() {
    label.dispose();
    options.dispose();
  }
}

/// Edits the questions of an event: up to five, each text, number or choice,
/// required or not. Pops the list on Done.
class EventQuestionsEditor extends StatefulWidget {
  const EventQuestionsEditor({
    required this.initial,
    this.scrollController,
    super.key,
  });

  final List<EventQuestion> initial;
  final ScrollController? scrollController;

  @override
  State<EventQuestionsEditor> createState() => _EventQuestionsEditorState();
}

class _EventQuestionsEditorState extends State<EventQuestionsEditor> {
  late final List<_QuestionDraft> _drafts = [
    for (final question in widget.initial) _QuestionDraft(question),
  ];
  var _counter = 0;
  String? _error;

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  String _newId() {
    final taken = {for (final draft in _drafts) draft.id};
    do {
      _counter++;
    } while (taken.contains('q$_counter'));
    return 'q$_counter';
  }

  void _add() {
    if (_drafts.length >= EventQuestion.maxCount) {
      return;
    }
    setState(() {
      _drafts.add(_QuestionDraft(EventQuestion(id: _newId(), label: '')));
    });
  }

  void _remove(_QuestionDraft draft) {
    setState(() {
      _drafts.remove(draft);
      draft.dispose();
    });
  }

  void _done() {
    final result = <EventQuestion>[];
    for (final draft in _drafts) {
      final label = draft.label.text.trim();
      if (label.isEmpty) {
        setState(() => _error = tr('Every question needs some words.'));
        return;
      }
      var options = const <String>[];
      if (draft.type == EventQuestionType.choice) {
        final lines = <String>[];
        for (final line in draft.options.text.split('\n')) {
          final option = line.trim();
          if (option.isNotEmpty && !lines.contains(option)) {
            lines.add(option);
          }
        }
        if (lines.length < EventQuestion.minOptions ||
            lines.length > EventQuestion.maxOptions ||
            lines.any((o) => o.length > EventQuestion.maxOptionLength)) {
          setState(() {
            _error = tr(
              'A choice question needs 2 to 8 different options, one per line.',
            );
          });
          return;
        }
        options = lines;
      }
      result.add(
        EventQuestion(
          id: draft.id,
          label: label,
          type: draft.type,
          required: draft.required,
          options: options,
        ),
      );
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 +
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          tr(
            'People answer these when they sign up, for example how many '
            'people they bring or what they eat. Only you and the other '
            'organisers see the answers.',
          ),
          style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.4),
        ),
        const SizedBox(height: 12),
        for (final (index, draft) in _drafts.indexed) ...[
          _QuestionCard(
            key: ValueKey('event-question-${draft.id}'),
            index: index,
            draft: draft,
            onChanged: () => setState(() {}),
            onRemove: () => _remove(draft),
          ),
          const SizedBox(height: 12),
        ],
        if (_drafts.length < EventQuestion.maxCount)
          WeCordButton(
            key: const ValueKey('event-question-add'),
            label: tr('Add a question'),
            icon: Icons.add_rounded,
            variant: WeCordButtonVariant.secondary,
            size: WeCordButtonSize.large,
            expand: true,
            onPressed: _add,
          )
        else
          Text(
            tr('An event can ask up to {count} questions.', {
              'count': EventQuestion.maxCount,
            }),
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('event-questions-error'),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: c.dangerText,
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: WeCordButton(
                label: tr('Cancel'),
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.large,
                expand: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: WeCordButton(
                key: const ValueKey('event-questions-done'),
                label: tr('Done'),
                variant: WeCordButtonVariant.accent,
                size: WeCordButtonSize.large,
                expand: true,
                onPressed: _done,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _QuestionDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
        border: Border.all(color: c.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    tr('Question {number}', {'number': index + 1}),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.muted,
                    ),
                  ),
                ),
              ),
              WeCordIconButton(
                tooltip: tr('Remove question {number}', {'number': index + 1}),
                icon: Icons.delete_outline_rounded,
                size: 32,
                iconSize: 18,
                variant: WeCordButtonVariant.ghost,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 6),
          WeCordTextField(
            fieldKey: ValueKey('event-question-label-${draft.id}'),
            controller: draft.label,
            label: tr('Question'),
            hint: tr('How many people are you bringing?'),
            maxLength: EventQuestion.maxLabelLength,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          WeCordSegmented<EventQuestionType>(
            expand: true,
            semanticLabel: tr('Answer type'),
            selected: draft.type,
            onChanged: (value) {
              draft.type = value;
              onChanged();
            },
            segments: [
              for (final type in EventQuestionType.values)
                WeCordSegment(value: type, label: type.label),
            ],
          ),
          if (draft.type == EventQuestionType.choice) ...[
            const SizedBox(height: 10),
            WeCordTextField(
              fieldKey: ValueKey('event-question-options-${draft.id}'),
              controller: draft.options,
              label: tr('Options, one per line'),
              hint: tr('Vegetarian\nNo restrictions'),
              minLines: 3,
              maxLines: 6,
            ),
          ],
          const SizedBox(height: 6),
          SettingsGroup(
            separatorIndent: 14,
            color: c.panel,
            children: [
              SettingsRow.toggle(
                key: ValueKey('event-question-required-${draft.id}'),
                title: tr('Required'),
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
    );
  }
}
