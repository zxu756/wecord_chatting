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
import 'package:wecord/features/circles/circle_channel_thread_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_events_screen.dart';
import 'package:wecord/features/circles/circle_invite_screen.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/features/home/home_sidebar.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/features/shell/wecord_shell.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/conversation.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRouter = AuthRouterNotifier(ref.read(authStateProvider));
  ref.listen<AsyncValue<AuthUser?>>(authStateProvider, (previous, next) {
    authRouter.authState = next;
  });

  final pushedPageObserver = PushedPageObserver();
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
      if (signedIn && (onAuthRoute || onLoadingRoute)) {
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
      ShellRoute(
        observers: [pushedPageObserver],
        builder: (context, state, child) {
          final placement = _placementFor(state);
          final location = state.uri.toString();
          if (placement.tab == WeCordTab.home) {
            homeTabMemory.location = location;
          }
          return ProfileBootstrapGate(
            child: WeCordShell(
              placement: placement,
              pushedPages: pushedPageObserver.pushedPages,
              onOpenVoice: (session) {
                final path = CircleChannelThreadScreen.pathFor(
                  session.circleId,
                  session.conversationId,
                );
                if (state.uri.path != path) {
                  context.push(path);
                }
              },
              onTabSelected: (tab) {
                switch (tab) {
                  case WeCordTab.home:
                    context.go(homeTabMemory.location);
                  case WeCordTab.messages:
                    context.go(ChatsScreen.path);
                  case WeCordTab.notifications:
                    context.go(InboxScreen.path);
                  case WeCordTab.you:
                    context.go(SettingsScreen.path);
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
            // page beside it shows the friends.
            builder: (context, state) =>
                const _WideOr(wide: ContactsScreen(), narrow: ChatsScreen()),
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
                // Phones hide the tabs here, so offer the way back.
                onBack: wide
                    ? null
                    : () => context.canPop()
                          ? context.pop()
                          : context.go(ChatsScreen.path),
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

/// Remembers where the phone Home tab was left (Home or a circle), so
/// switching back to the tab returns there.
final homeTabMemory = _HomeTabMemory();

class _HomeTabMemory {
  String location = HomeScreen.path;
}

/// Where [state]'s page sits in the navigation: which tab it is the root
/// of, what the rail highlights and whether Home's sidebar shows.
ShellPlacement _placementFor(GoRouterState state) {
  final segments = state.uri.pathSegments;
  final first = segments.isEmpty ? '' : segments.first;
  final rest = segments.length;
  final circles = CircleRoutes.path.substring(1);

  switch ('/$first') {
    case HomeScreen.path:
      return const ShellPlacement(
        tab: WeCordTab.home,
        homeSelected: true,
        homeSection: HomeSection.friends,
      );
    case ChatsScreen.path:
      if (rest == 1) {
        return const ShellPlacement(
          tab: WeCordTab.messages,
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
        tab: WeCordTab.notifications,
        homeSelected: true,
        homeSection: HomeSection.inbox,
      );
    case SettingsScreen.path:
      return const ShellPlacement(tab: WeCordTab.you);
  }
  if (first == circles && rest >= 2) {
    final circleHome = rest == 2;
    return ShellPlacement(
      tab: circleHome ? WeCordTab.home : null,
      selectedCircleId: segments[1],
      pageHasSidebar: circleHome,
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
