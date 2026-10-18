import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/forms/form_csv.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/features/forms/form_stats.dart';
import 'package:wecord/features/forms/form_validation.dart';
import 'package:wecord/shared/models/message.dart';

import 'form_fakes.dart';

FormSnapshot snapshot({
  FormSettings settings = const FormSettings(),
  List<FormFieldDef>? fields,
  bool closed = false,
  int responseCount = 0,
  FormResponseRow? mine,
}) {
  return FormSnapshot(
    id: 'form-1',
    conversationId: 'group-1',
    title: 'Hike sign-up',
    fields: fields ?? sampleFormFields(),
    settings: settings,
    createdBy: 'user-2',
    closedByServer: closed,
    responseCount: responseCount,
    myResponse: mine,
  );
}

FormResults results(
  List<FormResponseRow> rows, {
  bool anonymous = false,
  Map<String, FormPerson>? people,
}) {
  return FormResults(
    formId: 'form-1',
    anonymous: anonymous,
    responses: rows,
    people:
        people ??
        {
          'user-3': const FormPerson(id: 'user-3', name: 'Bob'),
          'user-4': const FormPerson(id: 'user-4', name: 'Cy'),
        },
    unfilled: null,
    memberTotal: 6,
  );
}

void main() {
  group('answers', () {
    final fields = sampleFormFields();
    FormFieldDef field(String id) => fields.firstWhere((f) => f.id == id);

    test('a required question needs an answer, an optional one does not', () {
      expect(answerProblem(field('name'), null), isNotNull);
      expect(answerProblem(field('name'), '   '), isNotNull);
      expect(answerProblem(field('name'), 'Ada'), isNull);
      expect(answerProblem(field('story'), null), isNull);
      expect(answerProblem(field('food'), const <String>[]), isNull);
    });

    test('numbers are checked against the range and whole-number rule', () {
      expect(answerProblem(field('age'), 31), isNull);
      expect(answerProblem(field('age'), 0), isNotNull);
      expect(answerProblem(field('age'), 121), isNotNull);
      expect(answerProblem(field('age'), 3.5), isNotNull);
      expect(answerProblem(field('age'), '31'), isNotNull);
    });

    test('choices must be options', () {
      expect(answerProblem(field('size'), 'm'), isNull);
      expect(answerProblem(field('size'), 'xl'), isNotNull);
      expect(answerProblem(field('food'), ['veg', 'fish']), isNull);
      expect(answerProblem(field('food'), ['veg', 'beef']), isNotNull);
    });

    test('dates, pictures and members', () {
      expect(answerProblem(field('day'), '2026-11-02'), isNull);
      expect(answerProblem(field('day'), 'tomorrow'), isNotNull);
      expect(
        answerProblem(
          field('photo'),
          const FormImageAnswer(bucket: 'chat-images', path: 'g/forms/f/a.jpg'),
        ),
        isNull,
      );
      expect(answerProblem(field('photo'), 'a.jpg'), isNotNull);
      expect(answerProblem(field('buddy'), 'user-3'), isNull);
    });

    test('the first problem comes in question order', () {
      final first = firstAnswerProblem(fields, {'size': 'm'});
      expect(first?.field.id, 'name');
      expect(firstAnswerProblem(fields, {'name': 'Ada', 'size': 'm'}), isNull);
    });

    test('clean answers drop blanks and trim text', () {
      expect(
        cleanAnswers(fields, {
          'name': '  Ada ',
          'story': '   ',
          'food': <String>[],
          'size': 's',
        }),
        {'name': 'Ada', 'size': 's'},
      );
    });

    test('answers survive the trip to the server and back', () {
      final answers = answersFromJson({
        'name': 'Ada',
        'age': 31,
        'food': ['veg'],
        'photo': {'bucket': 'chat-images', 'path': 'g/forms/f/a.jpg'},
      });
      expect(answers['photo'], isA<FormImageAnswer>());
      expect(answersToJson(answers)['photo'], {
        'bucket': 'chat-images',
        'path': 'g/forms/f/a.jpg',
      });
      expect(answers['food'], ['veg']);
    });
  });

  group('the builder', () {
    test('a draft needs a title, questions with titles and two choices', () {
      FormDraft draft(List<FormFieldDef> fields, {String title = 'T'}) =>
          FormDraft(title: title, fields: fields);
      expect(draftProblem(draft(const [], title: '')), isNotNull);
      expect(draftProblem(draft(const [])), contains('at least one'));
      expect(
        draftProblem(
          draft(const [
            FormFieldDef(id: 'q1', type: FormFieldType.shortText, label: ' '),
          ]),
        ),
        contains('Question 1'),
      );
      expect(
        draftProblem(
          draft(const [
            FormFieldDef(
              id: 'q1',
              type: FormFieldType.singleChoice,
              label: 'Pick',
              options: [
                FormOption(id: 'o1', label: 'A'),
                FormOption(id: 'o2', label: ' '),
              ],
            ),
          ]),
        ),
        contains('two choices'),
      );
      expect(
        draftProblem(
          draft(const [
            FormFieldDef(
              id: 'q1',
              type: FormFieldType.number,
              label: 'N',
              min: 5,
              max: 1,
            ),
          ]),
        ),
        isNotNull,
      );
      expect(
        draftProblem(
          draft(const [
            FormFieldDef(id: 'q1', type: FormFieldType.shortText, label: 'A'),
          ]),
        ),
        isNull,
      );
    });

    test('new ids do not clash', () {
      expect(newFormFieldId(const []), 'q1');
      expect(newFormFieldId(const ['q1', 'q3']), 'q4');
      expect(newFormOptionId(const ['o1', 'o2']), 'o3');
      expect(
        newFormField(FormFieldType.singleChoice, const ['q1']).options,
        hasLength(2),
      );
    });

    test('blank choices are not sent, and the wire shape is the server\'s', () {
      final draft = sendableDraft(
        const FormDraft(
          title: ' Trip ',
          settings: FormSettings(anonymous: true, maxResponses: 30),
          fields: [
            FormFieldDef(
              id: 'q1',
              type: FormFieldType.singleChoice,
              label: ' Pick ',
              required: true,
              options: [
                FormOption(id: 'o1', label: 'A '),
                FormOption(id: 'o2', label: ''),
                FormOption(id: 'o3', label: 'B'),
              ],
            ),
            FormFieldDef(
              id: 'q2',
              type: FormFieldType.number,
              label: 'N',
              min: 1,
              integerOnly: true,
            ),
          ],
        ),
      );
      expect(draft.title, 'Trip');
      expect(draft.fields.first.toJson(), {
        'id': 'q1',
        'type': 'single_choice',
        'label': 'Pick',
        'required': true,
        'options': [
          {'id': 'o1', 'label': 'A'},
          {'id': 'o3', 'label': 'B'},
        ],
      });
      expect(draft.fields.last.toJson(), {
        'id': 'q2',
        'type': 'number',
        'label': 'N',
        'required': false,
        'min': 1.0,
        'integer': true,
      });
      expect(draft.settings.toJson(), {
        'anonymous': true,
        'one_per_person': true,
        'editable': true,
        'results': 'creator',
        'max_responses': 30,
      });
    });

    test('editing is off when a person may answer more than once', () {
      expect(
        const FormSettings(onePerPerson: false).toJson()['editable'],
        isFalse,
      );
    });
  });

  group('the form', () {
    test('a form reads its settings and its own answer', () {
      final form = FormSnapshot.fromJson({
        'id': 'f',
        'conversation_id': 'c',
        'title': 'T',
        'fields': [
          {'id': 'a', 'type': 'short_text', 'label': 'A'},
          {'id': 'b', 'type': 'hologram', 'label': 'unknown type is skipped'},
        ],
        'settings': {
          'anonymous': true,
          'one_per_person': false,
          'results': 'after_submit',
          'deadline': '2030-01-01T00:00:00.000Z',
          'max_responses': 5,
        },
        'created_by': 'u',
        'response_count': 2,
        'my_response': {
          'id': 'r',
          'answers': {'a': 'x'},
        },
      });
      expect(form.fields, hasLength(1));
      expect(form.settings.anonymous, isTrue);
      expect(form.settings.onePerPerson, isFalse);
      expect(form.settings.results, FormResultsVisibility.afterSubmit);
      expect(form.settings.maxResponses, 5);
      expect(form.myResponse?.answers, {'a': 'x'});
    });

    test('closing: by hand, by the deadline, by the cap', () {
      final now = DateTime(2026, 10, 20, 12);
      expect(snapshot().isClosed(now), isFalse);
      expect(snapshot(closed: true).isClosed(now), isTrue);
      expect(
        snapshot(
          settings: FormSettings(
            deadline: now.subtract(const Duration(minutes: 1)),
          ),
        ).isClosed(now),
        isTrue,
      );
      expect(
        snapshot(
          settings: FormSettings(deadline: now.add(const Duration(days: 1))),
        ).isClosed(now),
        isFalse,
      );
      expect(
        snapshot(
          settings: const FormSettings(maxResponses: 2),
          responseCount: 2,
        ).isFull,
        isTrue,
      );
    });

    test('who can still fill in', () {
      final now = DateTime(2026, 10, 20, 12);
      const mine = FormResponseRow(id: 'r', answers: {'name': 'Ada'});
      expect(snapshot().canFill(now), isTrue);
      expect(snapshot(closed: true).canFill(now), isFalse);
      // Full: nobody new, but someone who answered may still edit.
      const full = FormSettings(maxResponses: 1);
      expect(snapshot(settings: full, responseCount: 1).canFill(now), isFalse);
      expect(
        snapshot(settings: full, responseCount: 1, mine: mine).canFill(now),
        isTrue,
      );
      // One answer that cannot be changed.
      expect(
        snapshot(
          settings: const FormSettings(editable: false),
          mine: mine,
        ).canFill(now),
        isFalse,
      );
      // Several answers allowed: another sheet is fine.
      expect(
        snapshot(
          settings: const FormSettings(onePerPerson: false),
          mine: mine,
        ).canFill(now),
        isTrue,
      );
    });

    test('a message with a form attachment is a form card', () {
      ChatMessage message(
        Map<String, dynamic>? attachment, {
        DateTime? recalled,
      }) => ChatMessage(
        id: 'm',
        conversationId: 'c',
        senderId: 'u',
        type: MessageType.text,
        body: 'x',
        createdAt: DateTime(2026),
        attachment: attachment,
        recalledAt: recalled,
      );
      expect(
        message({
          'kind': 'form',
          'form_id': 'f',
          'title': 'T',
        }).formCard?.formId,
        'f',
      );
      expect(message({'kind': 'chain', 'chain_id': 'c'}).formCard, isNull);
      expect(message(null).formCard, isNull);
      expect(
        message({
          'kind': 'form',
          'form_id': 'f',
        }, recalled: DateTime(2026)).formCard,
        isNull,
      );
    });

    test('the server\'s refusals are told apart', () {
      FormFailureKind kind(String message, {String? code, Object? details}) =>
          FormException.fromPostgrest(
            PostgrestException(message: message, code: code, details: details),
          ).kind;
      expect(kind('form_closed'), FormFailureKind.closed);
      expect(kind('form_full'), FormFailureKind.full);
      expect(kind('form_already_submitted'), FormFailureKind.alreadySubmitted);
      expect(kind('form_not_allowed'), FormFailureKind.notAllowed);
      expect(kind('form_held', code: '42501'), FormFailureKind.held);
      expect(
        kind('form_results_hidden', code: '42501'),
        FormFailureKind.resultsHidden,
      );
      expect(kind('remind_too_soon'), FormFailureKind.remindTooSoon);
      expect(kind('Form not found', code: 'P0002'), FormFailureKind.gone);
      expect(kind('nope', code: '42501'), FormFailureKind.forbidden);
      expect(kind('nope', code: '53400'), FormFailureKind.rateLimited);
      expect(kind('boom'), FormFailureKind.other);
      final refused = FormException.fromPostgrest(
        PostgrestException(
          message: 'form_answer_required',
          code: '22023',
          details: 'size',
        ),
      );
      expect(refused.kind, FormFailureKind.answerRequired);
      expect(refused.fieldId, 'size');
      expect(refused.message, isNotEmpty);
    });
  });

  group('csv', () {
    final form = snapshot();
    final rows = [
      const FormResponseRow(
        id: 'a',
        userId: 'user-3',
        answers: {
          'name': 'Bob',
          'story': 'Line one\nline "two", three',
          'age': 31,
          'size': 'm',
          'food': ['veg', 'fish'],
          'day': '2026-11-02',
          'photo': FormImageAnswer(
            bucket: 'chat-images',
            path: 'g/forms/f/pic-1.jpg',
          ),
          'buddy': 'user-4',
        },
      ),
      const FormResponseRow(
        id: 'b',
        userId: 'user-4',
        answers: {'name': '=HYPERLINK("http://evil")', 'size': 's', 'age': -2},
      ),
    ];

    test('one row per sheet with the person and a column per question', () {
      final csv = buildFormCsv(
        form,
        results(rows),
        formatTime: (_) => '2026-10-20 09:00',
      );
      expect(csv.startsWith('﻿'), isTrue);
      final lines = csv.substring(1).split('\r\n');
      expect(
        lines.first,
        'Name,Submitted,Updated,Your name,Anything to add?,Age,T-shirt size,Food,Arrival day,A photo,Buddy',
      );
      expect(
        csv,
        contains(
          'Bob,,,Bob,"Line one\nline ""two"", three",31,M,Veg; Fish,2026-11-02,pic-1.jpg,Cy',
        ),
      );
      expect(csv.endsWith('\r\n'), isTrue);
    });

    test('a cell a spreadsheet would run as a formula is neutralised', () {
      final csv = buildFormCsv(form, results(rows));
      expect(csv, contains("'=HYPERLINK"));
      // A plain negative number stays a number.
      expect(csv, contains(',-2,'));
      expect(csvCell('+1 555'), "'+1 555");
      expect(csvCell('@home'), "'@home");
      expect(csvCell('-5'), '-5');
      expect(csvCell('-abc'), "'-abc");
    });

    test('an anonymous form has no person, no time and nobody to name', () {
      final anonymous = results(
        [
          const FormResponseRow(
            id: 'a',
            answers: {'name': 'Someone said this', 'size': 'l'},
          ),
        ],
        anonymous: true,
        people: const {},
      );
      final csv = buildFormCsv(snapshot(), anonymous);
      final header = csv.substring(1).split('\r\n').first;
      expect(header, startsWith('Your name,'));
      expect(csv, isNot(contains('Submitted')));
      expect(csv, isNot(contains('Name,')));
      expect(csv, contains('Someone said this'));
    });

    test('file names are safe', () {
      expect(formCsvFileName('Hike sign-up'), 'Hike sign-up.csv');
      expect(formCsvFileName(r'a/b\c:d*?"<>|'), 'a b c d.csv');
      expect(formCsvFileName('   '), 'form.csv');
      expect(formCsvFileName('x' * 100).length, 64);
    });
  });

  group('statistics', () {
    final form = snapshot();
    final rows = [
      const FormResponseRow(
        id: 'a',
        userId: 'user-3',
        answers: {
          'name': 'Bob',
          'age': 20,
          'size': 'm',
          'food': ['veg', 'fish'],
          'day': '2026-11-02',
          'buddy': 'user-4',
          'photo': FormImageAnswer(bucket: 'b', path: 'p'),
        },
      ),
      const FormResponseRow(
        id: 'b',
        userId: 'user-4',
        answers: {
          'name': 'Cy',
          'age': 40,
          'size': 'm',
          'food': ['veg'],
          'day': '2026-11-02',
          'buddy': 'user-4',
        },
      ),
      const FormResponseRow(
        id: 'c',
        userId: 'user-5',
        answers: {'name': 'Di', 'age': 30, 'size': 's', 'day': '2026-11-03'},
      ),
    ];
    final stats = formStats(form, results(rows));
    FormFieldStats of(String id) => stats.firstWhere((s) => s.field.id == id);

    test('choices count each option, including the ones nobody picked', () {
      final size = of('size');
      expect(
        {for (final b in size.bars) b.label: b.count},
        {'S': 1, 'M': 2, 'L': 0},
      );
      expect(size.bars.firstWhere((b) => b.label == 'M').fraction, 1);
      expect(size.bars.firstWhere((b) => b.label == 'S').fraction, 0.5);
      final food = of('food');
      expect(
        {for (final b in food.bars) b.label: b.count},
        {'Veg': 2, 'Fish': 1, 'Meat': 0},
      );
      expect(food.answered, 2);
    });

    test('numbers have a summary and a histogram', () {
      final age = of('age');
      expect(age.number?.min, 20);
      expect(age.number?.max, 40);
      expect(age.number?.mean, 30);
      expect(age.number?.median, 30);
      expect(age.bars.map((b) => b.count).reduce((a, b) => a + b), 3);
    });

    test('dates, members, text and pictures', () {
      expect(
        {for (final b in of('day').bars) b.label: b.count},
        {'2026-11-02': 2, '2026-11-03': 1},
      );
      expect({for (final b in of('buddy').bars) b.label: b.count}, {'Cy': 2});
      expect(of('name').texts, ['Bob', 'Cy', 'Di']);
      expect(of('photo').images, hasLength(1));
      expect(of('story').answered, 0);
    });
  });
}
