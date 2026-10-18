import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/forms/form_builder_page.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'form_fakes.dart';

Widget builderApp(WidgetTester tester, FakeFormRepository repository) {
  tester.view.physicalSize = const Size(900, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return ProviderScope(
    retry: (count, error) => null,
    overrides: formOverrides(repository),
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('open'),
              onPressed: () =>
                  showFormBuilder(context, conversationId: 'group-1'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open')));
  await settle(tester);
}

Future<void> addQuestion(WidgetTester tester, FormFieldType type) async {
  final add = find.byKey(const ValueKey('form-add-question'));
  await tester.ensureVisible(add);
  await settle(tester);
  await tester.tap(add);
  await settle(tester);
  await tester.tap(find.byKey(ValueKey('form-type-${type.wire}')));
  await settle(tester);
}

void main() {
  testWidgets('the builder makes a form with every kind of question', (
    tester,
  ) async {
    final repository = FakeFormRepository();
    await tester.pumpWidget(builderApp(tester, repository));
    await open(tester);

    await tester.enterText(
      find.byKey(const ValueKey('form-title-field')),
      '  Hike sign-up ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('form-description-field')),
      'Meet at the gate.',
    );
    // The form starts with one short text question.
    await tester.enterText(
      find.byKey(const ValueKey('form-label-q1')),
      'Your name',
    );
    await tester.tap(find.byKey(const ValueKey('form-required-q1')));
    await settle(tester);

    for (final type in FormFieldType.values.skip(1)) {
      await addQuestion(tester, type);
    }
    expect(find.text('Questions (8)'), findsOneWidget);
    const labels = {
      'q2': 'Story',
      'q3': 'Age',
      'q4': 'Size',
      'q5': 'Food',
      'q6': 'Day',
      'q7': 'Photo',
      'q8': 'Buddy',
    };
    for (final MapEntry(:key, :value) in labels.entries) {
      await tester.ensureVisible(find.byKey(ValueKey('form-label-$key')));
      await tester.enterText(find.byKey(ValueKey('form-label-$key')), value);
    }
    // A number between 1 and 120, whole.
    await tester.ensureVisible(find.byKey(const ValueKey('form-min-q3')));
    await tester.enterText(find.byKey(const ValueKey('form-min-q3')), '1');
    await tester.enterText(find.byKey(const ValueKey('form-max-q3')), '120');
    await tester.tap(find.byKey(const ValueKey('form-integer-q3')));
    await settle(tester);
    // Choices.
    for (final id in ['q4', 'q5']) {
      await tester.ensureVisible(find.byKey(ValueKey('form-option-$id-o1')));
      await tester.enterText(find.byKey(ValueKey('form-option-$id-o1')), 'A');
      await tester.enterText(find.byKey(ValueKey('form-option-$id-o2')), 'B');
    }
    await tester.ensureVisible(
      find.byKey(const ValueKey('form-add-option-q5')),
    );
    await tester.tap(find.byKey(const ValueKey('form-add-option-q5')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('form-option-q5-o3')),
      'C',
    );
    // A hint.
    await tester.ensureVisible(find.byKey(const ValueKey('form-add-hint-q2')));
    await tester.tap(find.byKey(const ValueKey('form-add-hint-q2')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('form-help-q2')),
      'Allergies, rides.',
    );

    // Settings: anonymous, a limit, results for everyone, a deadline.
    await tester.ensureVisible(
      find.byKey(const ValueKey('form-setting-anonymous')),
    );
    await tester.tap(find.byKey(const ValueKey('form-setting-anonymous')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-setting-results')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-results-everyone')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-setting-deadline')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('when-inOneHour')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('form-limit-field')));
    await tester.enterText(
      find.byKey(const ValueKey('form-limit-field')),
      '30',
    );

    await tester.tap(find.byKey(const ValueKey('form-post')));
    await settle(tester);

    expect(repository.created, hasLength(1));
    final (conversation, draft) = repository.created.single;
    expect(conversation, 'group-1');
    expect(draft.title, 'Hike sign-up');
    expect(draft.description, 'Meet at the gate.');
    expect(draft.fields.map((f) => f.type), FormFieldType.values);
    expect(draft.fields.first.required, isTrue);
    expect(draft.fields[1].help, 'Allergies, rides.');
    expect(draft.fields[2].min, 1);
    expect(draft.fields[2].max, 120);
    expect(draft.fields[2].integerOnly, isTrue);
    expect(draft.fields[4].options.map((o) => o.label), ['A', 'B', 'C']);
    expect(draft.settings.anonymous, isTrue);
    expect(draft.settings.results, FormResultsVisibility.everyone);
    expect(draft.settings.maxResponses, 30);
    expect(draft.settings.deadline, isNotNull);
    expect(draft.settings.onePerPerson, isTrue);
    // The builder closed.
    expect(find.byKey(const ValueKey('form-builder-page')), findsNothing);
  });

  testWidgets('what is missing is said once, and nothing is posted', (
    tester,
  ) async {
    final repository = FakeFormRepository();
    await tester.pumpWidget(builderApp(tester, repository));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('form-post')));
    await settle(tester);
    expect(find.text('Give the form a title.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('form-title-field')), 'T');
    await tester.tap(find.byKey(const ValueKey('form-post')));
    await settle(tester);
    expect(find.text('Question 1 needs a title.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('form-label-q1')), 'Q');
    await addQuestion(tester, FormFieldType.singleChoice);
    await tester.enterText(find.byKey(const ValueKey('form-label-q2')), 'Pick');
    await tester.tap(find.byKey(const ValueKey('form-post')));
    await settle(tester);
    expect(find.text('Question 2 needs at least two choices.'), findsOneWidget);
    expect(repository.created, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('form-limit-field')),
      '900',
    );
    await tester.tap(find.byKey(const ValueKey('form-post')));
    await settle(tester);
    expect(find.text('The limit is a number from 1 to 500.'), findsOneWidget);
  });

  testWidgets('questions can be moved and deleted', (tester) async {
    final repository = FakeFormRepository();
    await tester.pumpWidget(builderApp(tester, repository));
    await open(tester);
    await tester.enterText(find.byKey(const ValueKey('form-title-field')), 'T');
    await tester.enterText(
      find.byKey(const ValueKey('form-label-q1')),
      'First',
    );
    await addQuestion(tester, FormFieldType.longText);
    await tester.enterText(
      find.byKey(const ValueKey('form-label-q2')),
      'Second',
    );
    await addQuestion(tester, FormFieldType.number);
    await tester.enterText(
      find.byKey(const ValueKey('form-label-q3')),
      'Third',
    );

    // Drag the third question up above the first.
    final handle = find.byKey(const ValueKey('form-drag-q3'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('form-post')));
    await settle(tester);
    final order = repository.created.single.$2.fields
        .map((f) => f.label)
        .toList();
    expect(order.first, 'Third');
    expect(order.toSet(), {'First', 'Second', 'Third'});
  });

  testWidgets('a question can be deleted unless it is the last one', (
    tester,
  ) async {
    final repository = FakeFormRepository();
    await tester.pumpWidget(builderApp(tester, repository));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('form-remove-q1')));
    await settle(tester);
    expect(find.text('Questions (1)'), findsOneWidget);
    await addQuestion(tester, FormFieldType.date);
    expect(find.text('Questions (2)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('form-remove-q1')));
    await settle(tester);
    expect(find.text('Questions (1)'), findsOneWidget);
    expect(find.byKey(const ValueKey('form-question-q2')), findsOneWidget);
  });

  testWidgets('editing needs one answer per person', (tester) async {
    final repository = FakeFormRepository();
    await tester.pumpWidget(builderApp(tester, repository));
    await open(tester);
    await tester.enterText(find.byKey(const ValueKey('form-title-field')), 'T');
    await tester.enterText(find.byKey(const ValueKey('form-label-q1')), 'Q');
    await tester.ensureVisible(find.byKey(const ValueKey('form-setting-once')));
    await tester.tap(find.byKey(const ValueKey('form-setting-once')));
    await settle(tester);
    // The editing row no longer reacts while several answers are allowed.
    await tester.tap(find.byKey(const ValueKey('form-setting-editable')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-post')));
    await settle(tester);
    final settings = repository.created.single.$2.settings.toJson();
    expect(settings['one_per_person'], isFalse);
    expect(settings['editable'], isFalse);
  });

  testWidgets('the server\'s refusal is shown above the button', (
    tester,
  ) async {
    final repository = FakeFormRepository()
      ..createError = const FormException(FormFailureKind.notAllowed);
    await tester.pumpWidget(builderApp(tester, repository));
    await open(tester);
    await tester.enterText(find.byKey(const ValueKey('form-title-field')), 'T');
    await tester.enterText(find.byKey(const ValueKey('form-label-q1')), 'Q');
    await tester.tap(find.byKey(const ValueKey('form-post')));
    await settle(tester);
    expect(
      find.text('Forms work in groups and circle channels.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('form-builder-page')), findsOneWidget);
    // And the person can post again.
    await tester.tap(find.byKey(const ValueKey('form-post')));
    await settle(tester);
    expect(repository.created, hasLength(1));
  });
}
