import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/auth/password_recovery.dart';
import 'package:wecord/features/auth/set_new_password_screen.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/features/auth/two_factor_challenge_screen.dart';
import 'package:wecord/features/auth/profile_bootstrap_gate.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/circles/circle_channel_thread_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_events_screen.dart';
import 'package:wecord/features/circles/circle_invite_screen.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/discovery/discovery_screen.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/features/home/home_sidebar.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/features/shell/wecord_shell.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/conversation.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRouter = AuthRouterNotifier(ref.read(authStateProvider));
  ref.listen<AsyncValue<AuthUser?>>(authStateProvider, (previous, next) {
    authRouter.authState = next;
  });
  authRouter.recoveringPassword = ref.read(passwordRecoveryPendingProvider);
  ref.listen<bool>(passwordRecoveryPendingProvider, (previous, next) {
    authRouter.recoveringPassword = next;
  });
  authRouter.twoFactorPending = ref.read(twoFactorPendingProvider);
  ref.listen<bool>(twoFactorPendingProvider, (previous, next) {
    authRouter.twoFactorPending = next;
  });

  final router = GoRouter(
    initialLocation: HomeScreen.path,
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
      // Two-step verification: the code comes before anything else.
      final onTwoFactorRoute = location == TwoFactorChallengeScreen.path;
      if (signedIn && authRouter.twoFactorPending) {
        return onTwoFactorRoute
            ? null
            : _withPendingLocation(
                TwoFactorChallengeScreen.path,
                pendingLocation,
              );
      }
      // Opened from a password reset link: choose a new password first.
      final onNewPasswordRoute = location == SetNewPasswordScreen.path;
      if (signedIn && authRouter.recoveringPassword) {
        return onNewPasswordRoute ? null : SetNewPasswordScreen.path;
      }
      if (signedIn &&
          (onAuthRoute ||
              onLoadingRoute ||
              onNewPasswordRoute ||
              onTwoFactorRoute)) {
        return pendingLocation ?? HomeScreen.path;
      }
      // Circles are listed in the rail; there is no page of them.
      if (location == CircleRoutes.path || location == '/') {
        return HomeScreen.path;
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
      GoRoute(
        path: SetNewPasswordScreen.path,
        builder: (context, state) => const SetNewPasswordScreen(),
      ),
      GoRoute(
        path: TwoFactorChallengeScreen.path,
        builder: (context, state) => const TwoFactorChallengeScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return ProfileBootstrapGate(
            child: WeCordShell(
              placement: _placementFor(state),
              onOpenVoice: (session) {
                final path = voiceSessionPath(session);
                if (state.uri.path != path) {
                  context.push(path);
                }
              },
              child: child,
            ),
          );
        },
        routes: [
          GoRoute(
            path: HomeScreen.path,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: ChatsScreen.path,
            // Wide layouts list direct messages in the Home sidebar, so the
            // page beside it shows the friends; phones list them on Home.
            builder: (context, state) =>
                const _WideOr(wide: ContactsScreen(), narrow: HomeScreen()),
          ),
          GoRoute(
            path: InboxScreen.path,
            builder: (context, state) => const InboxScreen(),
          ),
          GoRoute(
            path: GlobalMessageSearchScreen.path,
            builder: (context, state) => const GlobalMessageSearchScreen(),
          ),
          GoRoute(
            path: DiscoveryScreen.path,
            builder: (context, state) => const DiscoveryScreen(),
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
              if (extra case ChatThreadRouteExtra(:final circleId?)) {
                return CircleChannelThreadScreen(
                  circleId: circleId,
                  conversationId: state.pathParameters['conversationId']!,
                  title: title,
                  conversationType: conversationType == ConversationType.thread
                      ? ConversationType.thread
                      : ConversationType.channel,
                );
              }
              final wide = isWideLayout(MediaQuery.sizeOf(context).width);
              return ChatThreadScreen(
                conversationId: state.pathParameters['conversationId']!,
                title: title,
                avatarUrl: avatarUrl,
                conversationType: conversationType,
                // Phones show the thread full screen, so offer the way back
                // (to Home when it was opened from a link or notification).
                onBack: wide
                    ? null
                    : () => context.canPop()
                          ? context.pop()
                          : context.go(HomeScreen.path),
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
            path: '${CircleRoutes.path}/:circleId',
            builder: (context, state) {
              return CircleDetailScreen(
                circleId: state.pathParameters['circleId']!,
                initialConversationId: state.uri.queryParameters['c'],
              );
            },
            routes: [
              // The circle's events; ?event= opens one (from a reminder).
              GoRoute(
                path: 'events',
                builder: (context, state) {
                  return CircleEventsScreen(
                    circleId: state.pathParameters['circleId']!,
                    initialEventId: state.uri.queryParameters['event'],
                  );
                },
              ),
              // Circle channels opened full screen on narrow layouts. Living
              // under /circles keeps the Circles destination highlighted.
              GoRoute(
                path: 'channels/:conversationId',
                builder: (context, state) {
                  final extra = state.extra;
                  return CircleChannelThreadScreen(
                    circleId: state.pathParameters['circleId']!,
                    conversationId: state.pathParameters['conversationId']!,
                    title: switch (extra) {
                      ChatThreadRouteExtra(:final title) => title,
                      String() => extra,
                      _ => null,
                    },
                    conversationType: switch (extra) {
                      ChatThreadRouteExtra(type: ConversationType.thread) =>
                        ConversationType.thread,
                      _ => ConversationType.channel,
                    },
                  );
                },
              ),
            ],
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
    return Scaffold(body: Center(child: Text(tr('Loading'))));
  }
}

class AuthRouterNotifier extends ChangeNotifier {
  AuthRouterNotifier(this._authState);

  AsyncValue<AuthUser?> _authState;

  AsyncValue<AuthUser?> get authState => _authState;

  set authState(AsyncValue<AuthUser?> value) {
    final previous = _authState;
    _authState = value;
    // Auth also reports refreshed tokens and re-read users (two-step
    // checks do that); only a different signed-in state should re-run the
    // redirects, since a refresh rebuilds pages and drops windows over them.
    final sameState =
        previous.isLoading == value.isLoading &&
        previous.hasError == value.hasError &&
        previous.valueOrNull?.id == value.valueOrNull?.id;
    if (!sameState) {
      notifyListeners();
    }
  }

  var _twoFactorPending = false;

  /// See twoFactorPendingProvider.
  bool get twoFactorPending => _twoFactorPending;

  set twoFactorPending(bool value) {
    if (value == _twoFactorPending) {
      return;
    }
    _twoFactorPending = value;
    notifyListeners();
  }

  var _recoveringPassword = false;

  /// See passwordRecoveryPendingProvider.
  bool get recoveringPassword => _recoveringPassword;

  set recoveringPassword(bool value) {
    if (value == _recoveringPassword) {
      return;
    }
    _recoveringPassword = value;
    notifyListeners();
  }
}

/// Invite links opened while signed out (or before auth resolves) ride along
/// as `?from=` on /loading, /auth and /verify-sign-in, and are reopened
/// after sign-in.
String? _pendingLocation(Uri uri) {
  final candidate =
      uri.path == AuthScreen.path ||
          uri.path == LoadingScreen.path ||
          uri.path == TwoFactorChallengeScreen.path
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

/// Where [state]'s page sits in the navigation: what the rail highlights
/// and whether Home's sidebar shows (wide layouts).
ShellPlacement _placementFor(GoRouterState state) {
  final segments = state.uri.pathSegments;
  final first = segments.isEmpty ? '' : segments.first;
  final rest = segments.length;
  final circles = CircleRoutes.path.substring(1);

  switch ('/$first') {
    case HomeScreen.path:
      return const ShellPlacement(
        homeSelected: true,
        homeSection: HomeSection.friends,
      );
    case ChatsScreen.path:
      if (rest == 1) {
        return const ShellPlacement(
          homeSelected: true,
          homeSection: HomeSection.friends,
        );
      }
      // A circle channel opened by conversation id belongs to its circle.
      if (state.extra case ChatThreadRouteExtra(:final circleId?)) {
        return ShellPlacement(selectedCircleId: circleId);
      }
      return ShellPlacement(
        homeSelected: true,
        homeSection: HomeSection.conversation,
        selectedConversationId: segments[1],
      );
    case ContactsScreen.path:
      return const ShellPlacement(
        homeSelected: true,
        homeSection: HomeSection.friends,
      );
    case InboxScreen.path:
      return const ShellPlacement(
        homeSelected: true,
        homeSection: HomeSection.inbox,
      );
    case DiscoveryScreen.path:
      return const ShellPlacement(exploreSelected: true);
    // Wide layouts show settings as a window over Home.
    case SettingsScreen.path:
      return const ShellPlacement(
        homeSelected: true,
        homeSection: HomeSection.friends,
      );
  }
  if (first == circles && rest >= 2) {
    return ShellPlacement(
      selectedCircleId: segments[1],
      pageHasSidebar: rest == 2,
    );
  }
  return const ShellPlacement();
}

/// Picks [wide] or [narrow] for the current screen width.
class _WideOr extends StatelessWidget {
  const _WideOr({required this.wide, required this.narrow});

  final Widget wide;
  final Widget narrow;

  @override
  Widget build(BuildContext context) {
    return isWideLayout(MediaQuery.sizeOf(context).width) ? wide : narrow;
  }
}
