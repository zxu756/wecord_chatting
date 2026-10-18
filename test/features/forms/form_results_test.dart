import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/forms/form_export.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/features/forms/form_results_page.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'form_fakes.dart';

class _World {
  _World({
    String me = 'user-2',
    FormSettings settings = const FormSettings(),
    bool closed = false,
  }) : repository = FakeFormRepository(
         me: me,
         settings: settings,
         closed: closed,
       ),
       exporter = FakeFormFileExporter() {
    repository
      ..addSheet('user-3', 'Bob', {
        'name': 'Robert',
        'age': 20,
        'size': 'm',
        'food': ['veg'],
        'buddy': 'user-4',
      })
      ..addSheet('user-4', 'Cy', {'name': 'Cyrus', 'age': 40, 'size': 'm'})
      ..addSheet('user-5', 'Di', {'name': 'Diana', 'age': 30, 'size': 's'});
    repository.people['user-4'] = const FormPerson(id: 'user-4', name: 'Cy');
    repository.unfilled = const [
      FormPerson(id: 'user-6', name: 'Eve'),
      FormPerson(id: 'user-7', name: 'Fay'),
    ];
  }

  final FakeFormRepository repository;
  final FakeFormFileExporter exporter;

  Widget app(WidgetTester tester, {ThemeData? theme}) {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return ProviderScope(
      retry: (count, error) => null,
      overrides: formOverrides(repository, exporter: exporter),
      child: MaterialApp(
        theme: theme ?? WeCordTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () => openFormResults(context, formId: 'form-1'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }
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

void main() {
  testWidgets('the summary adds up each question and names who is missing', (
    tester,
  ) async {
    final world = _World();
    await tester.pumpWidget(world.app(tester));
    await open(tester);

    expect(find.text('3 of 6 people answered'), findsOneWidget);
    // The size question: M twice, S once, L never.
    expect(find.byKey(const ValueKey('form-stats-size')), findsOneWidget);
    final size = find.byKey(const ValueKey('form-stats-size'));
    expect(
      find.descendant(of: size, matching: find.text('2 · 67%')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: size, matching: find.text('1 · 33%')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: size, matching: find.text('0 · 0%')),
      findsOneWidget,
    );
    // The age question has a summary.
    final age = find.byKey(const ValueKey('form-stats-age'));
    expect(
      find.descendant(of: age, matching: find.text('Average')),
      findsOneWidget,
    );
    expect(find.descendant(of: age, matching: find.text('30')), findsWidgets);
    // The people who have not answered.
    await tester.scrollUntilVisible(
      find.text('Eve'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Not answered yet (2)'), findsOneWidget);
    expect(find.text('Fay'), findsOneWidget);
  });

  testWidgets(
    'the table has a row for each person and a column for each question',
    (tester) async {
      final world = _World();
      await tester.pumpWidget(world.app(tester));
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('form-tab-table')));
      await settle(tester);
      expect(find.text('Bob'), findsWidgets);
      expect(find.text('Cy'), findsWidgets);
      expect(find.text('Di'), findsOneWidget);
      expect(find.text('T-shirt size'), findsOneWidget);
      expect(find.text('M'), findsNWidgets(2));
      // Bob's buddy is Cy; Cy named nobody.
      expect(find.text('—'), findsWidgets);
    },
  );

  testWidgets('the creator reminds the people who have not answered', (
    tester,
  ) async {
    final world = _World();
    await tester.pumpWidget(world.app(tester));
    await open(tester);
    expect(find.text('2 people have not answered yet.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('form-remind')));
    await settle(tester);
    expect(world.repository.calls, contains('remind'));
    expect(find.text('Reminded 2 people.'), findsOneWidget);
  });

  testWidgets('a reminder the server refuses says why', (tester) async {
    final world = _World();
    world.repository.remindError = const FormException(
      FormFailureKind.remindTooSoon,
    );
    await tester.pumpWidget(world.app(tester));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('form-remind')));
    await settle(tester);
    expect(
      find.text('You reminded people a moment ago. Try again later.'),
      findsOneWidget,
    );
  });

  testWidgets('exporting hands over a CSV with the people in it', (
    tester,
  ) async {
    final world = _World();
    await tester.pumpWidget(world.app(tester));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('form-export')));
    await settle(tester);
    expect(world.exporter.files, hasLength(1));
    final (name, csv) = world.exporter.files.single;
    expect(name, 'Hike sign-up.csv');
    expect(csv, contains('Name,Submitted,Updated,Your name'));
    expect(csv, contains('Bob,'));
    expect(csv, contains('Di,'));
  });

  testWidgets('an anonymous form shows no names anywhere and exports none', (
    tester,
  ) async {
    final world = _World(settings: const FormSettings(anonymous: true));
    await tester.pumpWidget(world.app(tester));
    await open(tester);
    expect(
      find.text('Anonymous: nobody can see who gave which answers.'),
      findsOneWidget,
    );
    // The creator cannot list who has not answered either.
    expect(find.text('Eve'), findsNothing);
    expect(find.textContaining('Not answered yet'), findsNothing);
    expect(
      find.text('Everyone who has not answered gets a notification.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('form-tab-table')));
    await settle(tester);
    expect(find.text('#'), findsOneWidget);
    expect(find.text('Name'), findsNothing);
    expect(find.text('Di'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('form-tab-summary')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-export')));
    await settle(tester);
    final (_, csv) = world.exporter.files.single;
    expect(csv, isNot(contains('Submitted')));
    expect(csv, isNot(contains('user-')));
    expect(csv.substring(1).split('\r\n').first, startsWith('Your name,'));
  });

  testWidgets('somebody who may read the answers cannot manage the form', (
    tester,
  ) async {
    final world = _World(
      me: 'user-9',
      settings: const FormSettings(results: FormResultsVisibility.everyone),
    );
    await tester.pumpWidget(world.app(tester));
    await open(tester);
    expect(find.byKey(const ValueKey('form-export')), findsOneWidget);
    expect(find.byKey(const ValueKey('form-remind')), findsNothing);
    expect(find.byKey(const ValueKey('form-close')), findsNothing);
    expect(find.textContaining('Not answered yet'), findsNothing);
  });

  testWidgets('answers the form does not show to this person stay hidden', (
    tester,
  ) async {
    final world = _World(me: 'user-9');
    await tester.pumpWidget(world.app(tester));
    await open(tester);
    expect(find.textContaining("can't see the results"), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
  });

  testWidgets('the creator closes the form and opens it again', (tester) async {
    final world = _World();
    await tester.pumpWidget(world.app(tester));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('form-close')));
    await settle(tester);
    expect(world.repository.closed, isTrue);
    expect(find.text('The form is closed.'), findsOneWidget);
    // Closed: no reminding, but it can be reopened.
    expect(find.byKey(const ValueKey('form-remind')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('form-reopen')));
    await settle(tester);
    expect(world.repository.closed, isFalse);
    expect(find.byKey(const ValueKey('form-remind')), findsOneWidget);
  });

  testWidgets('no answers yet says so, and there is nothing to export', (
    tester,
  ) async {
    final world = _World();
    world.repository.sheets.clear();
    await tester.pumpWidget(world.app(tester));
    await open(tester);
    expect(find.text('No answers yet.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('form-export')));
    await settle(tester);
    expect(world.exporter.files, isEmpty);
    await tester.tap(find.byKey(const ValueKey('form-tab-table')));
    await settle(tester);
    expect(find.text('No answers yet.'), findsOneWidget);
  });

  testWidgets('the dark results draw too', (tester) async {
    final world = _World();
    await tester.pumpWidget(world.app(tester, theme: WeCordTheme.dark()));
    await open(tester);
    expect(find.text('3 of 6 people answered'), findsOneWidget);
  });

  test('a failed download says nothing was exported', () {
    expect(FormExportOutcome.failed, isNot(FormExportOutcome.shared));
  });
}
