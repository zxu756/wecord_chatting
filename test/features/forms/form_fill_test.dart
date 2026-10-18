import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/forms/form_fill_page.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'form_fakes.dart';

Widget fillApp(
  WidgetTester tester,
  FakeFormRepository repository, {
  FakeImagePicker? picker,
}) {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return ProviderScope(
    retry: (count, error) => null,
    overrides: formOverrides(repository, picker: picker),
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('open'),
              onPressed: () => openFormFill(context, formId: 'form-1'),
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

Finder field(String id) => find.byKey(ValueKey('form-input-$id'));

Future<void> show(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await settle(tester);
}

void main() {
  testWidgets('a person fills in all 8 kinds of question and submits', (
    tester,
  ) async {
    final repository = FakeFormRepository();
    final picker = FakeImagePicker();
    await tester.pumpWidget(fillApp(tester, repository, picker: picker));
    await open(tester);

    // Nothing is sent while a required question is empty.
    await tester.tap(find.byKey(const ValueKey('form-submit')));
    await settle(tester);
    expect(repository.submitted, isEmpty);
    expect(find.byKey(const ValueKey('form-error-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('form-error-size')), findsOneWidget);
    expect(find.byKey(const ValueKey('form-fill-banner')), findsOneWidget);

    // Short and long text, a number.
    await tester.enterText(field('name'), '  Bob  ');
    await tester.enterText(field('story'), 'Vegetarian please');
    await tester.enterText(field('age'), '31');
    // Single and multiple choice.
    await show(tester, find.byKey(const ValueKey('form-option-size-m')));
    await tester.tap(find.byKey(const ValueKey('form-option-size-m')));
    await settle(tester);
    await show(tester, find.byKey(const ValueKey('form-option-food-fish')));
    await tester.tap(find.byKey(const ValueKey('form-option-food-fish')));
    await tester.tap(find.byKey(const ValueKey('form-option-food-veg')));
    await settle(tester);
    // A date.
    await show(tester, field('day'));
    await tester.tap(field('day'));
    await settle(tester);
    await tester.tap(find.text('OK'));
    await settle(tester);
    // A picture.
    await show(tester, field('photo'));
    await tester.tap(field('photo'));
    await settle(tester);
    expect(picker.picks, 1);
    expect(repository.uploads, hasLength(1));
    expect(find.byKey(const ValueKey('form-image-photo')), findsOneWidget);
    // A member.
    await show(tester, field('buddy'));
    await tester.tap(field('buddy'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-member-user-4')));
    await settle(tester);
    expect(find.text('Cy'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('form-submit')));
    await settle(tester);

    expect(repository.submitted, hasLength(1));
    final sent = repository.submitted.single;
    expect(sent['name'], 'Bob');
    expect(sent['story'], 'Vegetarian please');
    expect(sent['age'], 31);
    expect(sent['size'], 'm');
    expect(sent['food'], ['veg', 'fish']);
    expect(sent['day'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(sent['photo'], isA<FormImageAnswer>());
    expect(
      (sent['photo']! as FormImageAnswer).path,
      startsWith('group-1/forms/form-1/'),
    );
    expect(sent['buddy'], 'user-4');
    // The page closed and said thanks.
    expect(find.byKey(const ValueKey('form-fill-page')), findsNothing);
    expect(find.text('Thanks, your answers are in.'), findsOneWidget);
  });

  testWidgets('a number is checked against its range', (tester) async {
    final repository = FakeFormRepository();
    await tester.pumpWidget(fillApp(tester, repository));
    await open(tester);
    await tester.enterText(field('name'), 'Bob');
    await tester.enterText(field('age'), '200');
    await tester.tap(find.byKey(const ValueKey('form-option-size-s')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-submit')));
    await settle(tester);
    expect(find.text('At most 120.'), findsOneWidget);
    expect(repository.submitted, isEmpty);
  });

  testWidgets('answers come back to be changed, and the button says Update', (
    tester,
  ) async {
    final repository = FakeFormRepository()
      ..addSheet('user-1', 'Me', {'name': 'Bob', 'size': 's', 'age': 40});
    await tester.pumpWidget(fillApp(tester, repository));
    await open(tester);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('Update my answers'), findsOneWidget);
    await tester.enterText(field('name'), 'Bobby');
    await tester.tap(find.byKey(const ValueKey('form-option-size-l')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-submit')));
    await settle(tester);
    expect(repository.sheets, hasLength(1));
    expect(repository.sheets.single.answers['name'], 'Bobby');
    expect(repository.sheets.single.answers['size'], 'l');
    expect(find.text('Your answers are updated.'), findsOneWidget);
  });

  testWidgets('a closed form shows the answers and nothing to send', (
    tester,
  ) async {
    final repository = FakeFormRepository(closed: true)
      ..addSheet('user-1', 'Me', {'name': 'Bob', 'size': 's'});
    await tester.pumpWidget(fillApp(tester, repository));
    await open(tester);
    expect(find.byKey(const ValueKey('form-submit')), findsNothing);
    expect(find.byKey(const ValueKey('form-fill-notice')), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    final input = tester.widget<TextField>(field('name'));
    expect(input.enabled, isFalse);
  });

  testWidgets('a form that cannot be changed says so after the answer', (
    tester,
  ) async {
    final repository = FakeFormRepository(
      settings: const FormSettings(editable: false),
    )..addSheet('user-1', 'Me', {'name': 'Bob', 'size': 's'});
    await tester.pumpWidget(fillApp(tester, repository));
    await open(tester);
    expect(find.byKey(const ValueKey('form-submit')), findsNothing);
    expect(find.textContaining('can not be changed'), findsOneWidget);
  });

  testWidgets('an anonymous form tells people so before they answer', (
    tester,
  ) async {
    final repository = FakeFormRepository(
      settings: const FormSettings(anonymous: true),
    );
    await tester.pumpWidget(fillApp(tester, repository));
    await open(tester);
    expect(find.byKey(const ValueKey('form-anonymous-notice')), findsOneWidget);
  });

  testWidgets('the server\'s refusal marks the question', (tester) async {
    final repository = FakeFormRepository();
    await tester.pumpWidget(fillApp(tester, repository));
    await open(tester);
    await tester.enterText(field('name'), 'Bob');
    await tester.tap(find.byKey(const ValueKey('form-option-size-s')));
    await settle(tester);
    repository.submitError = const FormException(
      FormFailureKind.answerInvalid,
      fieldId: 'size',
    );
    await tester.tap(find.byKey(const ValueKey('form-submit')));
    await settle(tester);
    expect(find.byKey(const ValueKey('form-error-size')), findsOneWidget);
    expect(find.byKey(const ValueKey('form-fill-banner')), findsOneWidget);
    // And it can be sent again.
    await tester.tap(find.byKey(const ValueKey('form-submit')));
    await settle(tester);
    expect(find.byKey(const ValueKey('form-fill-page')), findsNothing);
  });

  testWidgets('a circle that holds new members\' text says so', (tester) async {
    final repository = FakeFormRepository()..holdText = true;
    await tester.pumpWidget(fillApp(tester, repository));
    await open(tester);
    await tester.enterText(field('name'), 'Bob');
    await tester.tap(find.byKey(const ValueKey('form-option-size-s')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-submit')));
    await settle(tester);
    expect(find.textContaining('without the text'), findsOneWidget);
  });

  testWidgets('a picture over 10 MB is refused before it uploads', (
    tester,
  ) async {
    final repository = FakeFormRepository();
    await tester.pumpWidget(
      fillApp(
        tester,
        repository,
        picker: FakeImagePicker(size: 11 * 1024 * 1024),
      ),
    );
    await open(tester);
    await show(tester, field('photo'));
    await tester.tap(field('photo'));
    await settle(tester);
    expect(repository.uploads, isEmpty);
    expect(find.text('Pictures can be up to 10 MB.'), findsOneWidget);
  });

  testWidgets('a picture that fails to upload says so and can be retried', (
    tester,
  ) async {
    final repository = FakeFormRepository()
      ..uploadError = const FormException(FormFailureKind.imageUpload);
    await tester.pumpWidget(fillApp(tester, repository));
    await open(tester);
    await show(tester, field('photo'));
    await tester.tap(field('photo'));
    await settle(tester);
    expect(find.byKey(const ValueKey('form-error-photo')), findsOneWidget);
    await tester.tap(field('photo'));
    await settle(tester);
    expect(find.byKey(const ValueKey('form-image-photo')), findsOneWidget);
  });

  testWidgets('a form that is gone says so', (tester) async {
    final repository = FakeFormRepository()
      ..getError = const FormException(FormFailureKind.gone);
    await tester.pumpWidget(fillApp(tester, repository));
    await open(tester);
    expect(find.textContaining("isn't available"), findsOneWidget);
  });
}
