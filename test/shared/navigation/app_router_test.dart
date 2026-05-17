import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';

void main() {
  testWidgets('opens Chats as the default screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: WeCordApp()));
    await tester.pumpAndSettle();

    expect(find.text('Chats'), findsWidgets);
    expect(find.text('No conversations yet'), findsOneWidget);
  });
}
