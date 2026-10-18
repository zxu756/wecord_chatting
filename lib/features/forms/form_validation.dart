import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The most the server takes (migration 202610230110).
const formMaxFields = 30;
const formMaxOptions = 30;
const formMinOptions = 2;

/// Whether [value] counts as an answer to [field] (blank text, an empty
/// choice and a missing value do not).
bool isAnswered(FormFieldDef field, Object? value) {
  return switch (value) {
    null => false,
    final String text => text.trim().isNotEmpty,
    final List<Object?> list => list.isNotEmpty,
    _ => true,
  };
}

/// What is wrong with one answer, or null.
String? answerProblem(FormFieldDef field, Object? value) {
  if (!isAnswered(field, value)) {
    return field.required ? tr('This question needs an answer.') : null;
  }
  switch (field.type) {
    case FormFieldType.shortText:
      return (value as String).trim().length > 200
          ? tr('At most 200 characters.')
          : null;
    case FormFieldType.longText:
      return (value as String).trim().length > 2000
          ? tr('At most 2000 characters.')
          : null;
    case FormFieldType.number:
      if (value is! num) {
        return tr('Enter a number.');
      }
      if (field.integerOnly && value != value.truncate()) {
        return tr('Enter a whole number.');
      }
      if (field.min != null && value < field.min!) {
        return tr('At least {min}.', {'min': formatNumber(field.min!)});
      }
      if (field.max != null && value > field.max!) {
        return tr('At most {max}.', {'max': formatNumber(field.max!)});
      }
      return null;
    case FormFieldType.singleChoice:
      return field.optionLabel('$value') == null
          ? tr('Pick one of the choices.')
          : null;
    case FormFieldType.multipleChoice:
      final picked = value is List ? value : const [];
      return picked.any((id) => field.optionLabel('$id') == null)
          ? tr('Pick from the choices.')
          : null;
    case FormFieldType.date:
      return DateTime.tryParse('$value') == null ? tr('Pick a date.') : null;
    case FormFieldType.image:
      return value is FormImageAnswer ? null : tr('Add a picture.');
    case FormFieldType.member:
      return value is String ? null : tr('Pick a member.');
  }
}

/// The first question (in order) whose answer would be refused, with why.
({FormFieldDef field, String problem})? firstAnswerProblem(
  List<FormFieldDef> fields,
  FormAnswers answers,
) {
  for (final field in fields) {
    final problem = answerProblem(field, answers[field.id]);
    if (problem != null) {
      return (field: field, problem: problem);
    }
  }
  return null;
}

/// The answers without blanks, as the server wants them.
FormAnswers cleanAnswers(List<FormFieldDef> fields, FormAnswers answers) {
  return {
    for (final field in fields)
      if (isAnswered(field, answers[field.id]))
        field.id: switch (answers[field.id]) {
          final String text => text.trim(),
          final other => other,
        },
  };
}

/// "3", "3.5": a number without a trailing ".0".
String formatNumber(num value) {
  if (value == value.truncate()) {
    return value.truncate().toString();
  }
  final text = value.toStringAsFixed(4);
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// What is wrong with a form in the builder, or null: said once, about the
/// first thing to fix.
String? draftProblem(FormDraft draft) {
  if (draft.title.trim().isEmpty) {
    return tr('Give the form a title.');
  }
  if (draft.fields.isEmpty) {
    return tr('Add at least one question.');
  }
  if (draft.fields.length > formMaxFields) {
    return tr('A form can have up to {count} questions.', {
      'count': formMaxFields,
    });
  }
  for (final (index, field) in draft.fields.indexed) {
    if (field.label.trim().isEmpty) {
      return tr('Question {number} needs a title.', {'number': index + 1});
    }
    if (field.type.isChoice) {
      final filled = field.options.where((o) => o.label.trim().isNotEmpty);
      if (filled.length < formMinOptions) {
        return tr('Question {number} needs at least two choices.', {
          'number': index + 1,
        });
      }
    }
    if (field.type == FormFieldType.number &&
        field.min != null &&
        field.max != null &&
        field.min! > field.max!) {
      return tr(
        'Question {number}: the smallest number is above the largest.',
        {'number': index + 1},
      );
    }
  }
  return null;
}

/// The draft as it is sent: blank choices dropped.
FormDraft sendableDraft(FormDraft draft) {
  return FormDraft(
    title: draft.title.trim(),
    description: draft.description.trim(),
    settings: draft.settings,
    fields: [
      for (final field in draft.fields)
        field.type.isChoice
            ? field.copyWith(
                options: [
                  for (final o in field.options)
                    if (o.label.trim().isNotEmpty)
                      FormOption(id: o.id, label: o.label.trim()),
                ],
              )
            : field,
    ],
  );
}

/// An id for a new question that is not in [used]: "q1", "q2", ...
String newFormFieldId(Iterable<String> used) {
  final taken = used.toSet();
  var n = taken.length + 1;
  while (taken.contains('q$n')) {
    n++;
  }
  return 'q$n';
}

/// An id for a new choice that is not in [used]: "o1", "o2", ...
String newFormOptionId(Iterable<String> used) {
  final taken = used.toSet();
  var n = taken.length + 1;
  while (taken.contains('o$n')) {
    n++;
  }
  return 'o$n';
}

/// The question as the builder first shows it.
FormFieldDef newFormField(FormFieldType type, Iterable<String> usedIds) {
  return FormFieldDef(
    id: newFormFieldId(usedIds),
    type: type,
    label: '',
    options: type.isChoice
        ? [
            const FormOption(id: 'o1', label: ''),
            const FormOption(id: 'o2', label: ''),
          ]
        : const [],
  );
}
