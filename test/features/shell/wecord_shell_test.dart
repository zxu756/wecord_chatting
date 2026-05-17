import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/shell/wecord_shell.dart';

void main() {
  testWidgets('switches between primary tabs', (tester) async {
    var selectedIndex = 0;
    final selectedIndexes = <int>[];

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: WeCordShell(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                selectedIndexes.add(index);
                setState(() {
                  selectedIndex = index;
                });
              },
              child: const Text('Current screen'),
            ),
          );
        },
      ),
    );

    expect(find.text('Chats'), findsWidgets);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Circles'), findsOneWidget);
    expect(find.text('Me'), findsOneWidget);

    await tester.tap(find.text('Contacts'));
    await tester.pump();

    await tester.tap(find.text('Circles'));
    await tester.pump();

    await tester.tap(find.text('Me'));
    await tester.pump();

    expect(selectedIndexes, [1, 2, 3]);
  });
}
