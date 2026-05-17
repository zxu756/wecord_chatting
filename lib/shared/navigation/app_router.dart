import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circles_screen.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/features/shell/wecord_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRouter = AuthRouterNotifier(ref.read(authStateProvider));
  ref.listen<AsyncValue<AuthUser?>>(authStateProvider, (previous, next) {
    authRouter.authState = next;
  });

  final router = GoRouter(
    initialLocation: ChatsScreen.path,
    refreshListenable: authRouter,
    redirect: (context, state) {
      final authState = authRouter.authState;
      final location = state.uri.path;
      final onAuthRoute = location == AuthScreen.path;
      final onLoadingRoute = location == LoadingScreen.path;

      if (authState.isLoading) {
        return onLoadingRoute ? null : LoadingScreen.path;
      }

      if (authState.hasError) {
        return onAuthRoute ? null : AuthScreen.path;
      }

      final signedIn = authState.valueOrNull != null;

      if (!signedIn && !onAuthRoute) {
        return AuthScreen.path;
      }
      if (signedIn && (onAuthRoute || onLoadingRoute)) {
        return ChatsScreen.path;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: LoadingScreen.path,
        builder: (context, state) => const LoadingScreen(),
      ),
      GoRoute(
        path: AuthScreen.path,
        builder: (context, state) => const AuthScreen(),
      ),
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
            path: '/chats/:conversationId',
            builder: (context, state) {
              return ChatThreadScreen(
                conversationId: state.pathParameters['conversationId']!,
              );
            },
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

  ref.onDispose(() {
    router.dispose();
    authRouter.dispose();
  });
  return router;
});

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  static const path = '/loading';

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Loading')));
  }
}

class AuthRouterNotifier extends ChangeNotifier {
  AuthRouterNotifier(this._authState);

  AsyncValue<AuthUser?> _authState;

  AsyncValue<AuthUser?> get authState => _authState;

  set authState(AsyncValue<AuthUser?> value) {
    _authState = value;
    notifyListeners();
  }
}

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
