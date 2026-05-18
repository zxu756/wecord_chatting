import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circles_screen.dart';

void main() {
  testWidgets('circles starter shell shows creation entry point', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    expect(find.text('Circles'), findsOneWidget);
    expect(find.text('Private spaces for familiar groups'), findsOneWidget);
    expect(find.text('Create Circle'), findsOneWidget);
  });

  testWidgets('create circle entry explains upcoming channels', (tester) async {
    await tester.pumpWidget(_app());

    await tester.tap(find.text('Create Circle'));
    await tester.pumpAndSettle();

    expect(find.text('Circle creation is coming next'), findsOneWidget);
    expect(
      find.text(
        'Text channels, announcements, and invited members will live here.',
      ),
      findsOneWidget,
    );
  });
}

Widget _app() {
  return const ProviderScope(child: MaterialApp(home: CirclesScreen()));
}
