import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circles_screen.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/features/shell/wecord_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: ChatsScreen.path,
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return WeCordShell(
            selectedIndex: _selectedIndexForLocation(state.uri.path),
            onDestinationSelected: (index) {
              switch (index) {
                case 0:
                  context.go(ChatsScreen.path);
                case 1:
                  context.go(ContactsScreen.path);
                case 2:
                  context.go(CirclesScreen.path);
                case 3:
                  context.go(SettingsScreen.path);
              }
            },
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: ChatsScreen.path,
            builder: (context, state) => const ChatsScreen(),
          ),
          GoRoute(
            path: ContactsScreen.path,
            builder: (context, state) => const ContactsScreen(),
          ),
          GoRoute(
            path: CirclesScreen.path,
            builder: (context, state) => const CirclesScreen(),
          ),
          GoRoute(
            path: SettingsScreen.path,
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

int _selectedIndexForLocation(String location) {
  if (location.startsWith(ContactsScreen.path)) {
    return 1;
  }
  if (location.startsWith(CirclesScreen.path)) {
    return 2;
  }
  if (location.startsWith(SettingsScreen.path)) {
    return 3;
  }
  return 0;
}
