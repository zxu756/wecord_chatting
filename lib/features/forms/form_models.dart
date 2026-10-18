import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// The 8 kinds of question a form can ask (migration 202610230110).
enum FormFieldType {
  shortText('short_text'),
  longText('long_text'),
  number('number'),
  singleChoice('single_choice'),
  multipleChoice('multiple_choice'),
  date('date'),
  image('image'),
  member('member');

  const FormFieldType(this.wire);

  /// The name the server stores.
  final String wire;

  static FormFieldType? fromWire(String? wire) =>
      values.where((type) => type.wire == wire).firstOrNull;

  bool get isChoice =>
      this == FormFieldType.singleChoice ||
      this == FormFieldType.multipleChoice;

  bool get isText =>
      this == FormFieldType.shortText || this == FormFieldType.longText;
}

/// One choice of a single or multiple choice question.
@immutable
class FormOption {
  const FormOption({required this.id, required this.label});

  factory FormOption.fromJson(Map<String, dynamic> json) => FormOption(
    id: json['id'] as String,
    label: (json['label'] as String?) ?? '',
  );

  final String id;
  final String label;

  Map<String, dynamic> toJson() => {'id': id, 'label': label};
}

/// One question.
@immutable
class FormFieldDef {
  const FormFieldDef({
    required this.id,
    required this.type,
    required this.label,
    this.required = false,
    this.help = '',
    this.options = const [],
    this.min,
    this.max,
    this.integerOnly = false,
  });

  /// Reads a question; null for a type this app doesn't know.
  static FormFieldDef? fromJson(Map<String, dynamic> json) {
    final type = FormFieldType.fromWire(json['type'] as String?);
    final id = json['id'];
    if (type == null || id is! String) {
      return null;
    }
    return FormFieldDef(
      id: id,
      type: type,
      label: (json['label'] as String?) ?? '',
      required: json['required'] == true,
      help: (json['help'] as String?) ?? '',
      options: [
        if (json['options'] is List)
          for (final option in json['options'] as List)
            if (option is Map<String, dynamic>) FormOption.fromJson(option),
      ],
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      integerOnly: json['integer'] == true,
    );
  }

  final String id;
  final FormFieldType type;
  final String label;
  final bool required;
  final String help;
  final List<FormOption> options;
  final double? min;
  final double? max;
  final bool integerOnly;

  FormFieldDef copyWith({
    String? label,
    bool? required,
    String? help,
    List<FormOption>? options,
    double? min,
    double? max,
    bool clearMin = false,
    bool clearMax = false,
    bool? integerOnly,
  }) {
    return FormFieldDef(
      id: id,
      type: type,
      label: label ?? this.label,
      required: required ?? this.required,
      help: help ?? this.help,
      options: options ?? this.options,
      min: clearMin ? null : (min ?? this.min),
      max: clearMax ? null : (max ?? this.max),
      integerOnly: integerOnly ?? this.integerOnly,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.wire,
    'label': label.trim(),
    'required': required,
    if (help.trim().isNotEmpty) 'help': help.trim(),
    if (type.isChoice) 'options': [for (final o in options) o.toJson()],
    if (type == FormFieldType.number) ...{
      'min': ?min,
      'max': ?max,
      if (integerOnly) 'integer': true,
    },
  };

  String? optionLabel(String optionId) =>
      options.where((o) => o.id == optionId).firstOrNull?.label;
}

/// Who may read the answers.
enum FormResultsVisibility {
  creator('creator'),
  afterSubmit('after_submit'),
  everyone('everyone');

  const FormResultsVisibility(this.wire);

  final String wire;

  static FormResultsVisibility fromWire(String? wire) => values.firstWhere(
    (value) => value.wire == wire,
    orElse: () => FormResultsVisibility.creator,
  );
}

/// The creator's choices.
@immutable
class FormSettings {
  const FormSettings({
    this.anonymous = false,
    this.onePerPerson = true,
    this.editable = true,
    this.results = FormResultsVisibility.creator,
    this.deadline,
    this.maxResponses,
  });

  factory FormSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const FormSettings();
    }
    return FormSettings(
      anonymous: json['anonymous'] == true,
      onePerPerson: json['one_per_person'] != false,
      editable: json['editable'] != false,
      results: FormResultsVisibility.fromWire(json['results'] as String?),
      deadline: DateTime.tryParse('${json['deadline']}'),
      maxResponses: (json['max_responses'] as num?)?.toInt(),
    );
  }

  final bool anonymous;
  final bool onePerPerson;
  final bool editable;
  final FormResultsVisibility results;
  final DateTime? deadline;
  final int? maxResponses;

  FormSettings copyWith({
    bool? anonymous,
    bool? onePerPerson,
    bool? editable,
    FormResultsVisibility? results,
    DateTime? deadline,
    bool clearDeadline = false,
    int? maxResponses,
    bool clearMax = false,
  }) {
    return FormSettings(
      anonymous: anonymous ?? this.anonymous,
      onePerPerson: onePerPerson ?? this.onePerPerson,
      editable: editable ?? this.editable,
      results: results ?? this.results,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      maxResponses: clearMax ? null : (maxResponses ?? this.maxResponses),
    );
  }

  Map<String, dynamic> toJson() => {
    'anonymous': anonymous,
    'one_per_person': onePerPerson,
    'editable': onePerPerson && editable,
    'results': results.wire,
    if (deadline != null) 'deadline': deadline!.toUtc().toIso8601String(),
    'max_responses': ?maxResponses,
  };
}

/// What the person built in the form builder.
@immutable
class FormDraft {
  const FormDraft({
    required this.title,
    required this.fields,
    this.description = '',
    this.settings = const FormSettings(),
  });

  final String title;
  final String description;
  final List<FormFieldDef> fields;
  final FormSettings settings;
}

/// A picture someone attached to an answer.
@immutable
class FormImageAnswer {
  const FormImageAnswer({
    required this.bucket,
    required this.path,
    this.mimeType,
  });

  static FormImageAnswer? maybeFrom(Object? value) {
    if (value is! Map) {
      return null;
    }
    final bucket = value['bucket'];
    final path = value['path'];
    if (bucket is! String || path is! String) {
      return null;
    }
    return FormImageAnswer(
      bucket: bucket,
      path: path,
      mimeType: value['mime_type'] as String?,
    );
  }

  final String bucket;
  final String path;
  final String? mimeType;

  Map<String, dynamic> toJson() => {
    'bucket': bucket,
    'path': path,
    'mime_type': ?mimeType,
  };

  @override
  bool operator ==(Object other) =>
      other is FormImageAnswer && other.bucket == bucket && other.path == path;

  @override
  int get hashCode => Object.hash(bucket, path);
}

/// The answers of one sheet, by question id: a String (text, single choice,
/// date as yyyy-MM-dd, member id), a num, a `List<String>` (multiple choice)
/// or a [FormImageAnswer].
typedef FormAnswers = Map<String, Object?>;

/// Reads answers as the server stores them.
FormAnswers answersFromJson(Object? json) {
  if (json is! Map) {
    return {};
  }
  final out = <String, Object?>{};
  for (final MapEntry(:key, :value) in json.entries) {
    if (key is! String) {
      continue;
    }
    if (value is List) {
      out[key] = [for (final item in value) '$item'];
    } else if (value is Map) {
      final image = FormImageAnswer.maybeFrom(value);
      if (image != null) {
        out[key] = image;
      }
    } else if (value != null) {
      out[key] = value;
    }
  }
  return out;
}

/// The answers as the server wants them.
Map<String, dynamic> answersToJson(FormAnswers answers) => {
  for (final MapEntry(:key, :value) in answers.entries)
    key: value is FormImageAnswer ? value.toJson() : value,
};

/// One sheet of answers.
@immutable
class FormResponseRow {
  const FormResponseRow({
    required this.id,
    required this.answers,
    this.userId,
    this.submittedAt,
    this.updatedAt,
  });

  factory FormResponseRow.fromJson(Map<String, dynamic> json) {
    return FormResponseRow(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      answers: answersFromJson(json['answers']),
      submittedAt: DateTime.tryParse('${json['submitted_at']}'),
      updatedAt: DateTime.tryParse('${json['updated_at']}'),
    );
  }

  final String id;

  /// Null in an anonymous form: the server does not send it.
  final String? userId;
  final FormAnswers answers;
  final DateTime? submittedAt;
  final DateTime? updatedAt;
}

/// A form as `get_form` answers.
@immutable
class FormSnapshot {
  const FormSnapshot({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.fields,
    required this.settings,
    required this.createdBy,
    this.messageId,
    this.description = '',
    this.responseCount = 0,
    this.closedByServer = false,
    this.creatorName = '',
    this.canManage = false,
    this.canViewResults = false,
    this.myResponse,
    this.myResponseCount = 0,
  });

  factory FormSnapshot.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'];
    final mine = json['my_response'];
    return FormSnapshot(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      messageId: json['message_id'] as String?,
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      fields: [
        if (rawFields is List)
          for (final field in rawFields)
            if (field is Map<String, dynamic>) ?FormFieldDef.fromJson(field),
      ],
      settings: FormSettings.fromJson(
        json['settings'] is Map
            ? Map<String, dynamic>.from(json['settings'] as Map)
            : null,
      ),
      responseCount: (json['response_count'] as num?)?.toInt() ?? 0,
      closedByServer: json['closed'] == true,
      createdBy: json['created_by'] as String,
      creatorName: (json['creator_name'] as String?) ?? '',
      canManage: json['can_manage'] == true,
      canViewResults: json['can_view_results'] == true,
      myResponse: mine is Map
          ? FormResponseRow.fromJson(Map<String, dynamic>.from(mine))
          : null,
      myResponseCount: (json['my_response_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String conversationId;
  final String? messageId;
  final String title;
  final String description;
  final List<FormFieldDef> fields;
  final FormSettings settings;
  final int responseCount;
  final bool closedByServer;
  final String createdBy;
  final String creatorName;
  final bool canManage;
  final bool canViewResults;
  final FormResponseRow? myResponse;
  final int myResponseCount;

  /// Closed by hand, or the deadline has passed ([now] decides the second,
  /// so a card flips without waiting for the server).
  bool isClosed(DateTime now) =>
      closedByServer ||
      (settings.deadline != null && !settings.deadline!.isAfter(now));

  bool get isFull =>
      settings.maxResponses != null && responseCount >= settings.maxResponses!;

  bool get hasAnswered => myResponse != null;

  /// Whether the person can open the fill-in page to send or change
  /// something right now.
  bool canFill(DateTime now) {
    if (isClosed(now)) {
      return false;
    }
    if (!hasAnswered) {
      return !isFull;
    }
    return settings.onePerPerson ? settings.editable : !isFull;
  }

  FormFieldDef? fieldById(String id) =>
      fields.where((field) => field.id == id).firstOrNull;
}

/// A person named in the results.
@immutable
class FormPerson {
  const FormPerson({required this.id, required this.name, this.avatarUrl});

  final String id;
  final String name;
  final String? avatarUrl;

  String get displayName => name.trim().isEmpty ? tr('Someone') : name.trim();
}

/// `get_form_results`.
@immutable
class FormResults {
  const FormResults({
    required this.formId,
    required this.anonymous,
    required this.responses,
    required this.people,
    required this.unfilled,
    required this.memberTotal,
  });

  factory FormResults.fromJson(Map<String, dynamic> json) {
    final rawPeople = json['people'];
    final people = <String, FormPerson>{
      if (rawPeople is Map)
        for (final MapEntry(:key, :value) in rawPeople.entries)
          if (value is Map)
            '$key': FormPerson(
              id: '$key',
              name: (value['name'] as String?) ?? '',
              avatarUrl: value['avatar_url'] as String?,
            ),
    };
    final rawUnfilled = json['unfilled'];
    return FormResults(
      formId: json['form_id'] as String,
      anonymous: json['anonymous'] == true,
      responses: [
        if (json['responses'] is List)
          for (final row in json['responses'] as List)
            if (row is Map)
              FormResponseRow.fromJson(Map<String, dynamic>.from(row)),
      ],
      people: people,
      unfilled: rawUnfilled is List
          ? [
              for (final row in rawUnfilled)
                if (row is Map)
                  FormPerson(
                    id: row['user_id'] as String,
                    name: (row['name'] as String?) ?? '',
                    avatarUrl: row['avatar_url'] as String?,
                  ),
            ]
          : null,
      memberTotal: (json['member_total'] as num?)?.toInt() ?? 0,
    );
  }

  final String formId;
  final bool anonymous;
  final List<FormResponseRow> responses;

  /// Respondents (not in an anonymous form) and the people picked in
  /// member questions, by user id.
  final Map<String, FormPerson> people;

  /// Members who have not answered; null when the server does not say
  /// (anonymous forms, or the reader is not the creator).
  final List<FormPerson>? unfilled;
  final int memberTotal;

  FormPerson? personById(String? id) => id == null ? null : people[id];
}

/// What a form card in a chat points at (the message's attachment).
@immutable
class FormCard {
  const FormCard({required this.formId, this.title = ''});

  final String formId;
  final String title;

  static FormCard? maybeFromAttachment(Map<String, dynamic>? attachment) {
    if (attachment == null || attachment['kind'] != 'form') {
      return null;
    }
    final id = attachment['form_id'];
    if (id is! String) {
      return null;
    }
    return FormCard(formId: id, title: attachment['title'] as String? ?? '');
  }
}

extension FormMessageCard on ChatMessage {
  /// The form this message is the card of, or null.
  FormCard? get formCard {
    if (type != MessageType.text || recalledAt != null) {
      return null;
    }
    return FormCard.maybeFromAttachment(attachment);
  }
}

enum FormFailureKind {
  closed,
  full,
  alreadySubmitted,
  notAllowed,
  held,
  badTitle,
  badFields,
  badSettings,
  badDeadline,
  badLimit,
  tooLong,
  answerRequired,
  answerInvalid,
  resultsHidden,
  remindTooSoon,
  remindLimit,
  nobodyToRemind,
  rateLimited,
  forbidden,
  gone,
  imageUpload,
  other,
}

/// A write the server refused.
class FormException implements Exception {
  const FormException(this.kind, {this.fieldId});

  /// Reads the server's refusal (the error texts of migrations
  /// 202610230110 and 202610230120). For a refused answer the detail is the
  /// id of the question.
  factory FormException.fromPostgrest(PostgrestException error) {
    final kind = switch (error.message) {
      'form_closed' => FormFailureKind.closed,
      'form_full' => FormFailureKind.full,
      'form_already_submitted' => FormFailureKind.alreadySubmitted,
      'form_not_allowed' => FormFailureKind.notAllowed,
      'form_held' => FormFailureKind.held,
      'form_title_invalid' => FormFailureKind.badTitle,
      'form_fields_invalid' => FormFailureKind.badFields,
      'form_settings_invalid' => FormFailureKind.badSettings,
      'form_deadline_invalid' => FormFailureKind.badDeadline,
      'form_max_invalid' => FormFailureKind.badLimit,
      'form_text_too_long' => FormFailureKind.tooLong,
      'form_answer_required' => FormFailureKind.answerRequired,
      'form_answer_invalid' ||
      'form_unknown_field' ||
      'form_answers_invalid' => FormFailureKind.answerInvalid,
      'form_results_hidden' => FormFailureKind.resultsHidden,
      'remind_too_soon' => FormFailureKind.remindTooSoon,
      'remind_limit' => FormFailureKind.remindLimit,
      'nobody_to_remind' => FormFailureKind.nobodyToRemind,
      'rate_limited' => FormFailureKind.rateLimited,
      'Form not found' || 'Conversation not found' => FormFailureKind.gone,
      _ when error.code == '53400' => FormFailureKind.rateLimited,
      _ when error.code == '42501' => FormFailureKind.forbidden,
      _ => FormFailureKind.other,
    };
    final detail = error.details;
    return FormException(
      kind,
      fieldId: detail is String && detail.isNotEmpty ? detail : null,
    );
  }

  final FormFailureKind kind;
  final String? fieldId;

  /// What to tell the person.
  String get message => switch (kind) {
    FormFailureKind.closed => tr('This form is closed.'),
    FormFailureKind.full => tr('This form has all the answers it takes.'),
    FormFailureKind.alreadySubmitted => tr(
      'You have already filled this form in.',
    ),
    FormFailureKind.notAllowed => tr(
      'Forms work in groups and circle channels.',
    ),
    FormFailureKind.held => tr(
      "New members can't start forms in this circle yet.",
    ),
    FormFailureKind.badTitle => tr('Give the form a title.'),
    FormFailureKind.badFields => tr('Check the questions of this form.'),
    FormFailureKind.badSettings => tr('Check the settings of this form.'),
    FormFailureKind.badDeadline => tr('Pick a deadline in the future.'),
    FormFailureKind.badLimit => tr('The limit is a number from 1 to 500.'),
    FormFailureKind.tooLong => tr('That is too long.'),
    FormFailureKind.answerRequired => tr('Answer every question marked *.'),
    FormFailureKind.answerInvalid => tr('Check your answers.'),
    FormFailureKind.resultsHidden => tr(
      "You can't see the results of this form.",
    ),
    FormFailureKind.remindTooSoon => tr(
      'You reminded people a moment ago. Try again later.',
    ),
    FormFailureKind.remindLimit => tr(
      'You can remind people three times for one form.',
    ),
    FormFailureKind.nobodyToRemind => tr('Everyone has filled this in.'),
    FormFailureKind.rateLimited => tr(
      'Too many reminders today. Try tomorrow.',
    ),
    FormFailureKind.forbidden => tr("You can't do that here."),
    FormFailureKind.gone => tr("This form isn't available any more."),
    FormFailureKind.imageUpload => tr("The picture didn't upload. Try again."),
    FormFailureKind.other => tr("That didn't work. Try again."),
  };

  @override
  String toString() => 'FormException($kind, $fieldId)';
}

/// What the answers of one submit said back.
@immutable
class FormSubmitResult {
  const FormSubmitResult({this.updated = false, this.textHeld = false});

  final bool updated;

  /// The circle's AI guard kept the free text out of the answers.
  final bool textHeld;
}
