import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/admin/admin_console_screen.dart';
import 'package:wecord/features/admin/admin_entry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'admin_fakes.dart';

Widget _app(FakeAdminBackend backend) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(
          body: SingleChildScrollView(child: AdminConsoleEntry()),
        ),
      ),
      GoRoute(
        path: AdminConsoleScreen.path,
        builder: (context, state) => const AdminConsoleScreen(),
      ),
    ],
  );
  return ProviderScope(
    overrides: backend.overrides,
    child: MaterialApp.router(theme: WeCordTheme.light(), routerConfig: router),
  );
}

void main() {
  testWidgets('Settings shows no admin row to a normal user', (tester) async {
    final backend = FakeAdminBackend(role: null);
    await tester.pumpWidget(_app(backend));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-admin-console')), findsNothing);
    expect(find.text('Admin console'), findsNothing);
    expect(backend.calls('admin_my_role'), hasLength(1));
  });

  testWidgets('an admin sees the row and it opens the console', (tester) async {
    final backend = FakeAdminBackend(role: 'owner');
    await tester.pumpWidget(_app(backend));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-admin-console')),
      findsOneWidget,
    );
    expect(find.text('Owner'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-admin-console')));
    await tester.pumpAndSettle();
    expect(find.byType(AdminConsoleScreen), findsOneWidget);
    expect(find.text('No open reports.'), findsOneWidget);
  });

  testWidgets('a failed role lookup hides the row', (tester) async {
    // admin_my_role is not answered: like an offline server.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...(FakeAdminBackend()..role = 'owner').overrides.take(1)],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: const Scaffold(body: AdminConsoleEntry()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-admin-console')), findsNothing);
  });
}
