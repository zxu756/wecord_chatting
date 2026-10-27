import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/admin/admin_console_screen.dart';
import 'package:wecord/features/agenda/agenda_screen.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/auth/password_recovery.dart';
import 'package:wecord/features/auth/set_new_password_screen.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/features/auth/two_factor_challenge_screen.dart';
import 'package:wecord/features/auth/profile_bootstrap_gate.dart';
import 'package:wecord/features/app_lock/chat_lock_gate.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/circles/circle_channel_thread_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_events_screen.dart';
import 'package:wecord/features/knowledge_base/kb_screen.dart';
import 'package:wecord/features/member_honors/honors_screen.dart';
import 'package:wecord/features/circles/circle_invite_link.dart';
import 'package:wecord/features/circles/circle_invite_screen.dart';
import 'package:wecord/features/circles/circle_posts_screens.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/discovery/discovery_screen.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/features/home/home_sidebar.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/legal/legal_document.dart';
import 'package:wecord/features/legal/legal_screen.dart';
import 'package:wecord/features/notes/public/public_note.dart';
import 'package:wecord/features/notes/public/public_note_screen.dart';
import 'package:wecord/features/error_reports/error_reporting_hooks.dart';
import 'package:wecord/features/error_reports/redirect_tracking.dart';
import 'package:wecord/features/friend_tags/friend_tags_screen.dart';
import 'package:wecord/features/later/saved_messages_screen.dart';
import 'package:wecord/features/moments/moment_composer_screen.dart';
import 'package:wecord/features/moments/moment_detail_screen.dart';
import 'package:wecord/features/moments/moment_topics_screen.dart';
import 'package:wecord/features/moments/moments_screen.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/qr/qr_link_screens.dart';
import 'package:wecord/features/qr/qr_links.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/features/share_target/protocol_links.dart';
import 'package:wecord/features/share_target/share_target_screen.dart';
import 'package:wecord/features/shell/wecord_shell.dart';
import 'package:wecord/features/events2/event_check_in.dart';
import 'package:wecord/features/group_space/album_screen.dart';
import 'package:wecord/features/group_space/folder_screen.dart';
import 'package:wecord/features/group_space/group_space_screen.dart';
import 'package:wecord/features/voice/call_links/call_link_screen.dart';
import 'package:wecord/features/discovery/public_circle_link.dart';
import 'package:wecord/features/discovery/public_circle_screen.dart';
import 'package:wecord/features/voice/call_links/call_links.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/workspace/workspace_screen.dart';
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
    // A shared call link opened in the browser (https://site/call/<code>)
    // has no route after a '#', so its page is found from the address.
    initialLocation:
        (kIsWeb
            ? callLinkLocationFor(Uri.base) ??
                  checkInLocationFor(Uri.base) ??
                  qrLinkLocationFor(Uri.base) ??
                  protocolLinkLocationFor(Uri.base) ??
                  publicNoteLocationFor(Uri.base) ??
                  circleInviteLocationFor(Uri.base) ??
                  publicCircleLocationFor(Uri.base)
            : null) ??
        HomeScreen.path,
    refreshListenable: authRouter,
    redirect: trackRedirects(errorReporter, (context, state) {
      final authState = authRouter.authState;
      final location = state.uri.path;
      final onAuthRoute = location == AuthScreen.path;
      final onLoadingRoute = location == LoadingScreen.path;
      final pendingLocation = _pendingLocation(state.uri);

      // The policy pages are open to everybody, signed in or not (sign-up
      // links to them).
      if (location.startsWith('${LegalRoutes.prefix}/')) {
        return null;
      }
      // A published note is open to anybody holding its link (the link is
      // the secret); it needs no sign-in.
      if (location.startsWith('$publicNoteRoutePrefix/')) {
        return null;
      }

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

      final signedIn = authState.value != null;

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
    }),
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
            path: SavedMessagesScreen.path,
            builder: (context, state) => const SavedMessagesScreen(),
          ),
          GoRoute(
            path: MomentsScreen.path,
            builder: (context, state) => const MomentsScreen(),
            routes: [
              GoRoute(
                path: 'compose',
                builder: (context, state) => const MomentComposerScreen(),
              ),
              GoRoute(
                path: 'of/:userId',
                builder: (context, state) => MomentsScreen(
                  key: ValueKey('moments-of-${state.pathParameters['userId']}'),
                  userId: state.pathParameters['userId'],
                ),
              ),
              // Topics (#话题): the ones friends use, and the Moments with one.
              GoRoute(
                path: 'topics',
                builder: (context, state) => const MomentTopicsScreen(),
              ),
              GoRoute(
                path: 'tag/:tag',
                builder: (context, state) => MomentsScreen(
                  key: ValueKey('moments-tag-${state.pathParameters['tag']}'),
                  tag: state.pathParameters['tag'],
                ),
              ),
              GoRoute(
                path: ':postId',
                builder: (context, state) => MomentDetailScreen(
                  key: ValueKey('moment-${state.pathParameters['postId']}'),
                  postId: state.pathParameters['postId']!,
                  focusComment: state.uri.queryParameters['comment'] == '1',
                  replyToId: state.uri.queryParameters['reply'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: FriendTagsScreen.path,
            builder: (context, state) => const FriendTagsScreen(),
          ),
          GoRoute(
            path: GlobalMessageSearchScreen.path,
            builder: (context, state) => GlobalMessageSearchScreen(
              launch: GlobalMessageSearchScreen.launchFrom(
                state.uri.queryParameters,
              ),
            ),
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
              final conversationId = state.pathParameters['conversationId']!;
              // Phones show the thread full screen, so offer the way back
              // (to Home when it was opened from a link or notification).
              void back() => context.canPop()
                  ? context.pop()
                  : context.go(HomeScreen.path);
              // A chat the person locked opens only after Face ID, Touch ID,
              // the passcode or the PIN (G2).
              return ChatLockGate(
                conversationId: conversationId,
                onBack: back,
                child: ChatThreadScreen(
                  conversationId: conversationId,
                  title: title,
                  avatarUrl: avatarUrl,
                  conversationType: conversationType,
                  onBack: wide ? null : back,
                ),
              );
            },
          ),
          GoRoute(
            path: '/chats/:conversationId/media',
            builder: (context, state) {
              final conversationId = state.pathParameters['conversationId']!;
              return ChatLockGate(
                conversationId: conversationId,
                child: ChatMediaScreen(conversationId: conversationId),
              );
            },
          ),
          // A group chat's space (B6): albums and folders. ?tab=albums|files.
          GoRoute(
            path: '/chats/:conversationId/space',
            builder: (context, state) {
              final conversationId = state.pathParameters['conversationId']!;
              return ChatLockGate(
                conversationId: conversationId,
                child: GroupSpaceScreen(
                  conversationId: conversationId,
                  initialTab: GroupSpaceScreen.tabFrom(
                    state.uri.queryParameters,
                  ),
                ),
              );
            },
          ),
          GoRoute(
            path: '/chats/:conversationId/space/albums/:albumId',
            builder: (context, state) {
              final conversationId = state.pathParameters['conversationId']!;
              final albumId = state.pathParameters['albumId']!;
              return ChatLockGate(
                conversationId: conversationId,
                child: AlbumScreen(
                  key: ValueKey('space-album-$albumId'),
                  conversationId: conversationId,
                  albumId: albumId,
                  title: state.extra is String ? state.extra! as String : null,
                ),
              );
            },
          ),
          GoRoute(
            path: '/chats/:conversationId/space/events/:eventId',
            builder: (context, state) {
              final conversationId = state.pathParameters['conversationId']!;
              final eventId = state.pathParameters['eventId']!;
              return ChatLockGate(
                conversationId: conversationId,
                child: AlbumScreen(
                  key: ValueKey('space-event-$eventId'),
                  conversationId: conversationId,
                  eventId: eventId,
                  title: state.extra is String ? state.extra! as String : null,
                ),
              );
            },
          ),
          GoRoute(
            path: '/chats/:conversationId/space/files',
            builder: (context, state) {
              final conversationId = state.pathParameters['conversationId']!;
              return ChatLockGate(
                conversationId: conversationId,
                child: FolderScreen(conversationId: conversationId),
              );
            },
          ),
          GoRoute(
            path: '/chats/:conversationId/space/folders/:folderId',
            builder: (context, state) {
              final conversationId = state.pathParameters['conversationId']!;
              final folderId = state.pathParameters['folderId']!;
              return ChatLockGate(
                conversationId: conversationId,
                child: FolderScreen(
                  key: ValueKey('space-folder-$folderId'),
                  conversationId: conversationId,
                  folderId: folderId,
                  title: state.extra is String ? state.extra! as String : null,
                ),
              );
            },
          ),
          // A conversation's notes and lists as a page; ?tab=, ?note=,
          // ?list= and ?item= say what is open.
          GoRoute(
            path: '/chats/:conversationId/workspace',
            builder: (context, state) {
              final query = state.uri.queryParameters;
              final conversationId = state.pathParameters['conversationId']!;
              return ChatLockGate(
                conversationId: conversationId,
                child: WorkspaceScreen(
                  conversationId: conversationId,
                  title: state.extra is String ? state.extra! as String : null,
                  tab: WorkspaceScreen.tabFrom(query),
                  noteId: query['note'],
                  listId: query['list'],
                  itemId: query['item'],
                ),
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
              return UserProfileScreen(
                userId: state.pathParameters['userId']!,
                source: FriendSource.fromWire(
                  state.uri.queryParameters['source'],
                ),
              );
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
              // The circle's knowledge base; ?page= opens one page (from the
              // newcomer guide).
              GoRoute(
                path: 'knowledge',
                builder: (context, state) {
                  return KnowledgeBaseScreen(
                    circleId: state.pathParameters['circleId']!,
                    initialPageId: state.uri.queryParameters['page'],
                  );
                },
              ),
              // The circle's member honors (C7).
              GoRoute(
                path: 'honors',
                builder: (context, state) {
                  return MemberHonorsScreen(
                    circleId: state.pathParameters['circleId']!,
                  );
                },
              ),
              // The circle's posts, filtered by ?tag= or ?featured=1, and one
              // post (a link from a push or the search).
              GoRoute(
                path: 'posts',
                builder: (context, state) {
                  final query = state.uri.queryParameters;
                  return CirclePostsScreen(
                    key: ValueKey('posts-${state.uri}'),
                    circleId: state.pathParameters['circleId']!,
                    tag: query['tag'],
                    featuredOnly: query['featured'] == '1',
                  );
                },
                routes: [
                  GoRoute(
                    path: ':postId',
                    builder: (context, state) {
                      return CirclePostDetailScreen(
                        circleId: state.pathParameters['circleId']!,
                        postId: state.pathParameters['postId']!,
                      );
                    },
                  ),
                ],
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
          // A person's or a group's QR code opened as a link.
          GoRoute(
            path: '${UserQrLinkScreen.path}/:code',
            builder: (context, state) {
              return UserQrLinkScreen(
                key: ValueKey('user-qr-${state.pathParameters['code']}'),
                code: state.pathParameters['code']!,
              );
            },
          ),
          GoRoute(
            path: '${GroupQrJoinScreen.path}/:code',
            builder: (context, state) {
              return GroupQrJoinScreen(
                key: ValueKey('group-qr-${state.pathParameters['code']}'),
                code: state.pathParameters['code']!,
              );
            },
          ),
          GoRoute(
            path: '${CallLinkScreen.path}/:code',
            builder: (context, state) {
              return CallLinkScreen(
                key: ValueKey('call-link-${state.pathParameters['code']}'),
                code: state.pathParameters['code']!,
              );
            },
          ),
          // An event's check-in link (https://site/checkin/<code>).
          GoRoute(
            path: '${EventCheckInLinkScreen.path}/:code',
            builder: (context, state) {
              return EventCheckInLinkScreen(
                key: ValueKey('check-in-${state.pathParameters['code']}'),
                code: state.pathParameters['code']!,
              );
            },
          ),
          // The admin console. Hidden: Settings lists it for admins only,
          // and the page shows nothing to anybody else.
          GoRoute(
            path: AdminConsoleScreen.path,
            builder: (context, state) => const AdminConsoleScreen(),
          ),
          GoRoute(
            path: AgendaScreen.path,
            builder: (context, state) => const AgendaScreen(),
          ),
          // Where "Share to WeCord" from another app lands (see
          // web/wecord_sw.js): pick a chat for what was shared.
          GoRoute(
            path: ShareTargetScreen.path,
            builder: (context, state) => const ShareTargetScreen(),
          ),
          // A public circle's page (https://site/c/<slug>): the button on its
          // web page leads here. Signed-out visitors sign in first.
          GoRoute(
            path: '${PublicCircleScreen.path}/:slug',
            redirect: (context, state) =>
                isCircleSlug(
                  normalizeCircleSlug(state.pathParameters['slug'] ?? ''),
                )
                ? null
                : HomeScreen.path,
            builder: (context, state) => PublicCircleScreen(
              key: ValueKey('public-circle-${state.pathParameters['slug']}'),
              slug: normalizeCircleSlug(state.pathParameters['slug']!),
            ),
          ),
        ],
      ),
      // Terms, privacy policy and community guidelines, outside the app
      // shell so they open before sign-in too.
      GoRoute(
        path: '${LegalRoutes.prefix}/:slug',
        redirect: (context, state) =>
            LegalDocument.fromSlug(state.pathParameters['slug']) == null
            ? HomeScreen.path
            : null,
        builder: (context, state) => LegalDocumentScreen(
          key: ValueKey('legal-route-${state.pathParameters['slug']}'),
          document: LegalDocument.fromSlug(state.pathParameters['slug'])!,
        ),
      ),
      // A published note, read only, open before sign-in too.
      GoRoute(
        path: '$publicNoteRoutePrefix/:token',
        redirect: (context, state) =>
            isPublicNoteToken(state.pathParameters['token'] ?? '')
            ? null
            : HomeScreen.path,
        builder: (context, state) => PublicNoteScreen(
          key: ValueKey('public-note-${state.pathParameters['token']}'),
          token: state.pathParameters['token']!,
        ),
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
        previous.value?.id == value.value?.id;
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

/// Invite, call and QR code links opened while signed out (or before auth resolves)
/// ride along as `?from=` on /loading, /auth and /verify-sign-in, and are
/// reopened after sign-in.
String? _pendingLocation(Uri uri) {
  final candidate =
      uri.path == AuthScreen.path ||
          uri.path == LoadingScreen.path ||
          uri.path == TwoFactorChallengeScreen.path
      ? uri.queryParameters['from']
      : uri.path;
  if (candidate != null &&
      (candidate == ShareTargetScreen.path ||
          candidate.startsWith('${CircleInviteScreen.path}/') ||
          candidate.startsWith('${CallLinkScreen.path}/') ||
          candidate.startsWith('${EventCheckInLinkScreen.path}/') ||
          candidate.startsWith('${UserQrLinkScreen.path}/') ||
          candidate.startsWith('${GroupQrJoinScreen.path}/'))) {
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
    case SavedMessagesScreen.path:
      return const ShellPlacement(
        homeSelected: true,
        homeSection: HomeSection.saved,
      );
    case MomentsScreen.path:
      return const ShellPlacement(
        homeSelected: true,
        homeSection: HomeSection.moments,
      );
    case AgendaScreen.path:
      return const ShellPlacement(
        homeSelected: true,
        homeSection: HomeSection.agenda,
      );
    case FriendTagsScreen.path:
      return const ShellPlacement(
        homeSelected: true,
        homeSection: HomeSection.friends,
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
