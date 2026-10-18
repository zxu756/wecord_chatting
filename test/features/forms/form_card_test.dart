import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/forms/form_card.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'form_fakes.dart';

Widget cardApp(FakeFormRepository repository, {ThemeData? theme}) {
  return ProviderScope(
    retry: (count, error) => null,
    overrides: formOverrides(repository),
    child: MaterialApp(
      theme: theme ?? WeCordTheme.light(),
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: FormCardView(
            card: FormCard(formId: 'form-1', title: 'Hike sign-up'),
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

void main() {
  testWidgets('the card shows the count, the deadline and a Fill in button', (
    tester,
  ) async {
    final repository = FakeFormRepository(
      description: 'Meet at the gate at 8.',
      settings: FormSettings(
        maxResponses: 30,
        deadline: DateTime.now().add(const Duration(days: 1, hours: 3)),
      ),
    );
    for (var i = 0; i < 12; i++) {
      repository.addSheet('u$i', 'Person $i', {'name': 'P$i', 'size': 's'});
    }
    await tester.pumpWidget(cardApp(repository));
    await settle(tester);

    expect(find.text('Hike sign-up'), findsOneWidget);
    expect(find.text('Meet at the gate at 8.'), findsOneWidget);
    expect(find.textContaining('12/30 submitted'), findsOneWidget);
    expect(find.textContaining('8 questions'), findsOneWidget);
    expect(find.textContaining('Closes'), findsOneWidget);
    expect(find.byKey(const ValueKey('form-fill-form-1')), findsOneWidget);
    expect(find.text('Fill in'), findsOneWidget);
    // Not the creator, and the answers are for the creator: no Results.
    expect(find.byKey(const ValueKey('form-results-form-1')), findsNothing);
  });

  testWidgets('the creator also gets Results; an anonymous form says so', (
    tester,
  ) async {
    final repository = FakeFormRepository(
      me: 'user-2',
      settings: const FormSettings(anonymous: true),
    );
    await tester.pumpWidget(cardApp(repository));
    await settle(tester);

    expect(find.byKey(const ValueKey('form-results-form-1')), findsOneWidget);
    expect(find.text('Anonymous'), findsOneWidget);
    expect(find.textContaining('0 submitted'), findsOneWidget);
  });

  testWidgets('after answering the button says Edit; a closed form has none', (
    tester,
  ) async {
    final repository = FakeFormRepository()
      ..addSheet('user-1', 'Me', {'name': 'Me', 'size': 'm'});
    await tester.pumpWidget(cardApp(repository));
    await settle(tester);
    expect(find.byKey(const ValueKey('form-edit-form-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('form-fill-form-1')), findsNothing);

    repository.closed = true;
    repository.touch();
    await settle(tester);
    expect(find.text('Closed'), findsOneWidget);
    expect(find.byKey(const ValueKey('form-edit-form-1')), findsNothing);
  });

  testWidgets('a form with all its answers says Full', (tester) async {
    final repository = FakeFormRepository(
      settings: const FormSettings(maxResponses: 1),
    )..addSheet('user-5', 'Eve', {'name': 'Eve', 'size': 's'});
    await tester.pumpWidget(cardApp(repository));
    await settle(tester);
    expect(find.text('Full'), findsOneWidget);
    expect(find.byKey(const ValueKey('form-fill-form-1')), findsNothing);
  });

  testWidgets('tapping Fill in opens the fill-in page', (tester) async {
    await tester.pumpWidget(cardApp(FakeFormRepository()));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-fill-form-1')));
    await settle(tester);
    expect(find.byKey(const ValueKey('form-fill-page')), findsOneWidget);
    expect(
      find.textContaining('Your name', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('an unreadable form can be tried again', (tester) async {
    final repository = FakeFormRepository()
      ..getError = const FormException(FormFailureKind.gone);
    await tester.pumpWidget(cardApp(repository));
    await settle(tester);
    expect(find.textContaining('Tap to try again'), findsOneWidget);
    await tester.tap(find.textContaining('Tap to try again'));
    await settle(tester);
    expect(find.text('Fill in'), findsOneWidget);
  });

  testWidgets('the card follows the form live', (tester) async {
    final repository = FakeFormRepository();
    await tester.pumpWidget(cardApp(repository));
    await settle(tester);
    expect(find.textContaining('0 submitted'), findsOneWidget);
    repository
      ..addSheet('user-5', 'Eve', {'name': 'Eve', 'size': 's'})
      ..touch();
    await settle(tester);
    expect(find.textContaining('1 submitted'), findsOneWidget);
  });

  testWidgets('the dark card draws too', (tester) async {
    await tester.pumpWidget(
      cardApp(FakeFormRepository(), theme: WeCordTheme.dark()),
    );
    await settle(tester);
    expect(find.text('Hike sign-up'), findsOneWidget);
  });
}
