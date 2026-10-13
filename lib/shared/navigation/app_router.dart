import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/auth/profile_bootstrap_gate.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_invite_screen.dart';
import 'package:wecord/features/circles/circles_screen.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
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
      final pendingLocation = _pendingLocation(state.uri);

      if (authState.isLoading) {
        return onLoadingRoute
            ? null
            : _withPendingLocation(LoadingScreen.path, pendingLocation);
      }

      if (authState.hasError) {
        return onAuthRoute
            ? null
            : _withPendingLocation(AuthScreen.path, pendingLocation);
      }

      final signedIn = authState.valueOrNull != null;

      if (!signedIn && !onAuthRoute) {
        return _withPendingLocation(AuthScreen.path, pendingLocation);
      }
      if (signedIn && (onAuthRoute || onLoadingRoute)) {
        return pendingLocation ?? ChatsScreen.path;
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
          return ProfileBootstrapGate(
            child: WeCordShell(
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
            ),
          );
        },
        routes: [
          GoRoute(
            path: ChatsScreen.path,
            builder: (context, state) => const ChatsScreen(),
          ),
          GoRoute(
            path: GlobalMessageSearchScreen.path,
            builder: (context, state) => const GlobalMessageSearchScreen(),
          ),
          GoRoute(
            path: '/chats/:conversationId',
            builder: (context, state) {
              final extra = state.extra;
              final title = switch (extra) {
                ChatThreadRouteExtra(:final title) => title,
                String() => extra,
                _ => null,
              };
              final conversationType = switch (extra) {
                ChatThreadRouteExtra(:final type) => type,
                _ => null,
              };
              final avatarUrl = switch (extra) {
                ChatThreadRouteExtra(:final avatarUrl) => avatarUrl,
                _ => null,
              };
              return ChatThreadScreen(
                conversationId: state.pathParameters['conversationId']!,
                title: title,
                avatarUrl: avatarUrl,
                conversationType: conversationType,
              );
            },
          ),
          GoRoute(
            path: '/chats/:conversationId/media',
            builder: (context, state) {
              return ChatMediaScreen(
                conversationId: state.pathParameters['conversationId']!,
              );
            },
          ),
          GoRoute(
            path: ContactsScreen.path,
            builder: (context, state) => const ContactsScreen(),
          ),
          GoRoute(
            path: '${UserProfileScreen.path}/:userId',
            builder: (context, state) {
              return UserProfileScreen(userId: state.pathParameters['userId']!);
            },
          ),
          GoRoute(
            path: CirclesScreen.path,
            builder: (context, state) => const CirclesScreen(),
          ),
          GoRoute(
            path: '${CirclesScreen.path}/:circleId',
            builder: (context, state) {
              return CircleDetailScreen(
                circleId: state.pathParameters['circleId']!,
              );
            },
          ),
          GoRoute(
            path: '${CircleInviteScreen.path}/:code',
            builder: (context, state) {
              return CircleInviteScreen(code: state.pathParameters['code']!);
            },
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

/// Invite links opened while signed out (or before auth resolves) ride along
/// as `?from=` on /loading and /auth, and are reopened after sign-in.
String? _pendingLocation(Uri uri) {
  final candidate =
      uri.path == AuthScreen.path || uri.path == LoadingScreen.path
      ? uri.queryParameters['from']
      : uri.path;
  if (candidate != null &&
      candidate.startsWith('${CircleInviteScreen.path}/')) {
    return candidate;
  }
  return null;
}

String _withPendingLocation(String path, String? pendingLocation) {
  if (pendingLocation == null) {
    return path;
  }
  return Uri(path: path, queryParameters: {'from': pendingLocation}).toString();
}

int _selectedIndexForLocation(String location) {
  if (location.startsWith(ContactsScreen.path)) {
    return 1;
  }
  if (location.startsWith(CirclesScreen.path) ||
      location.startsWith('${CircleInviteScreen.path}/')) {
    return 2;
  }
  if (location.startsWith(SettingsScreen.path)) {
    return 3;
  }
  return 0;
}
