import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/shell/wecord_shell.dart';

void main() {
  testWidgets('switches between primary tabs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeCordShell(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          child: const Text('Current screen'),
        ),
      ),
    );

    expect(find.text('Chats'), findsWidgets);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Circles'), findsOneWidget);
    expect(find.text('Me'), findsOneWidget);
  });
}
