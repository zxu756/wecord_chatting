import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/shared/models/event_extras.dart';
import 'package:wecord/features/events2/events2_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A short-lived link to a picture of an event (a cover or a photo).
final eventPictureUrlProvider = FutureProvider.autoDispose
    .family<String, ({String bucket, String path})>((ref, key) {
      return ref
          .watch(events2RepositoryProvider)
          .pictureUrl(key.bucket, key.path);
    });

/// Runs [body] and reports its failure as a snackbar, for the small calls
/// the Events 2.0 widgets make. Returns whether it worked.
Future<bool> runEventAction(
  BuildContext context,
  Future<void> Function() body,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await body();
    return true;
  } on EventException catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text(error.failure.message)));
  } on Object {
    messenger?.showSnackBar(
      SnackBar(content: Text(EventFailure.other.message)),
    );
  }
  return false;
}

/// A picture from Storage, filling its box.
class EventPicture extends ConsumerWidget {
  const EventPicture({
    required this.bucket,
    required this.path,
    this.semanticLabel,
    super.key,
  });

  final String bucket;
  final String path;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final url = ref.watch(
      eventPictureUrlProvider((bucket: bucket, path: path)),
    );
    Widget placeholder({bool broken = false}) => ColoredBox(
      color: c.raised,
      child: Center(
        child: Icon(
          broken ? Icons.broken_image_outlined : Icons.image_outlined,
          color: c.faint,
          size: 28,
        ),
      ),
    );
    return Semantics(
      image: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: switch (url) {
        AsyncData(:final value) => Image.network(
          value,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) =>
              placeholder(broken: true),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : placeholder(),
        ),
        AsyncError() => placeholder(broken: true),
        _ => placeholder(),
      },
    );
  }
}

/// The cover of an event, wide, with rounded corners.
class EventCoverBanner extends StatelessWidget {
  const EventCoverBanner({
    required this.kind,
    required this.coverPath,
    this.aspectRatio = 16 / 7,
    this.radius = WeCordRadii.lg,
    super.key,
  });

  final EventKind kind;
  final String coverPath;
  final double aspectRatio;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: EventPicture(
          key: ValueKey('event-cover-$coverPath'),
          bucket: kind.bucket,
          path: coverPath,
          semanticLabel: tr('Event cover'),
        ),
      ),
    );
  }
}

/// Small facts about an event: that it repeats, how many seats are left and
/// how many wait. Nothing when the event uses none of it.
class EventInfoChips extends StatelessWidget {
  const EventInfoChips({
    required this.extras,
    required this.seatsTaken,
    this.checkedIn = true,
    super.key,
  });

  final EventExtras extras;

  /// How many seats are taken (the people Going).
  final int seatsTaken;

  /// Whether to count the people who checked in.
  final bool checkedIn;

  @override
  Widget build(BuildContext context) {
    final capacity = extras.capacity;
    final chips = <(IconData, String)>[
      if (extras.repeats) (Icons.repeat_rounded, extras.recurrence.label),
      if (capacity != null)
        (
          Icons.event_seat_outlined,
          extras.isFull(seatsTaken)
              ? tr('Full · {taken} of {capacity}', {
                  'taken': seatsTaken,
                  'capacity': capacity,
                })
              : tr('{taken} of {capacity} seats', {
                  'taken': seatsTaken,
                  'capacity': capacity,
                }),
        ),
      if (extras.waitlistCount > 0)
        (
          Icons.hourglass_empty_rounded,
          tr('{count} on the waiting list', {'count': extras.waitlistCount}),
        ),
      if (checkedIn && extras.checkedInCount > 0)
        (
          Icons.how_to_reg_outlined,
          tr('{count} checked in', {'count': extras.checkedInCount}),
        ),
    ];
    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      key: const ValueKey('event-info-chips'),
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (icon, label) in chips) _InfoChip(icon: icon, label: label),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: c.raised,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 14, color: c.muted)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks the questions of an event and returns the answers ({question id:
/// text}), or null when the person backs out. Required questions must be
/// answered.
Future<Map<String, String>?> showEventAnswerSheet(
  BuildContext context, {
  required String eventTitle,
  required List<EventQuestion> questions,
  Map<String, String> initial = const {},
  String? actionLabel,
}) {
  return showWeCordSheet<Map<String, String>>(
    context,
    title: tr('Sign up'),
    builder: (context, _) => EventAnswerForm(
      eventTitle: eventTitle,
      questions: questions,
      initial: initial,
      actionLabel: actionLabel ?? tr('Sign up'),
    ),
  );
}

/// The form of [showEventAnswerSheet].
class EventAnswerForm extends StatefulWidget {
  const EventAnswerForm({
    required this.eventTitle,
    required this.questions,
    required this.actionLabel,
    this.initial = const {},
    super.key,
  });

  final String eventTitle;
  final List<EventQuestion> questions;
  final Map<String, String> initial;
  final String actionLabel;

  @override
  State<EventAnswerForm> createState() => _EventAnswerFormState();
}

class _EventAnswerFormState extends State<EventAnswerForm> {
  final _controllers = <String, TextEditingController>{};
  final _choices = <String, String>{};
  final _errors = <String, String>{};

  @override
  void initState() {
    super.initState();
    for (final question in widget.questions) {
      final answer = widget.initial[question.id] ?? '';
      if (question.type == EventQuestionType.choice) {
        if (question.options.contains(answer)) {
          _choices[question.id] = answer;
        }
      } else {
        _controllers[question.id] = TextEditingController(text: answer);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final answers = <String, String>{};
    final errors = <String, String>{};
    for (final question in widget.questions) {
      final raw = question.type == EventQuestionType.choice
          ? _choices[question.id] ?? ''
          : (_controllers[question.id]?.text ?? '').trim();
      final value = question.type == EventQuestionType.number
          ? raw.replaceAll(',', '.')
          : raw;
      if (value.isEmpty) {
        if (question.required) {
          errors[question.id] = tr('This question needs an answer.');
        }
        continue;
      }
      if (question.type == EventQuestionType.number &&
          !RegExp(r'^-?\d{1,9}(\.\d{1,4})?$').hasMatch(value)) {
        errors[question.id] = tr('Enter a number.');
        continue;
      }
      answers[question.id] = value;
    }
    if (errors.isNotEmpty) {
      setState(() {
        _errors
          ..clear()
          ..addAll(errors);
      });
      return;
    }
    Navigator.of(context).pop(answers);
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
          widget.eventTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 14),
        for (final question in widget.questions) ...[
          _QuestionField(
            question: question,
            controller: _controllers[question.id],
            choice: _choices[question.id],
            error: _errors[question.id],
            onChoice: (value) => setState(() {
              _choices[question.id] = value;
              _errors.remove(question.id);
            }),
          ),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 4),
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
                key: const ValueKey('event-answers-submit'),
                label: widget.actionLabel,
                variant: WeCordButtonVariant.accent,
                size: WeCordButtonSize.large,
                expand: true,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuestionField extends StatelessWidget {
  const _QuestionField({
    required this.question,
    required this.controller,
    required this.choice,
    required this.error,
    required this.onChoice,
  });

  final EventQuestion question;
  final TextEditingController? controller;
  final String? choice;
  final String? error;
  final ValueChanged<String> onChoice;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final label = question.required ? '${question.label} *' : question.label;
    if (question.type == EventQuestionType.choice) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.muted,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in question.options)
                WeCordChip(
                  key: ValueKey('event-answer-${question.id}-$option'),
                  label: option,
                  selected: choice == option,
                  onPressed: () => onChoice(option),
                ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: c.dangerText,
                ),
              ),
            ),
        ],
      );
    }
    final number = question.type == EventQuestionType.number;
    return WeCordTextField(
      fieldKey: ValueKey('event-answer-${question.id}'),
      controller: controller,
      label: label,
      errorText: error,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      inputFormatters: number
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))]
          : null,
      maxLength: EventQuestion.maxAnswerLength,
      textInputAction: TextInputAction.next,
    );
  }
}
