import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/home/home_sidebar.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/notifications/notification_shell_listener.dart';
import 'package:wecord/features/push/push_shell_listener.dart';
import 'package:wecord/features/shell/keyboard_shortcuts.dart';
import 'package:wecord/features/voice/direct_call_view.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';

/// The phone navigation bar's tabs.
enum WeCordTab { home, messages, notifications, you }

/// Where the current page sits in the app's navigation.
class ShellPlacement {
  const ShellPlacement({
    this.tab,
    this.homeSelected = false,
    this.selectedCircleId,
    this.homeSection,
    this.selectedConversationId,
    this.pageHasSidebar = false,
  });

  /// The phone tab whose root page this is; null hides the navigation bar
  /// (pages opened on top of a tab).
  final WeCordTab? tab;

  /// Whether the rail highlights Home.
  final bool homeSelected;

  /// The circle the rail highlights.
  final String? selectedCircleId;

  /// On wide layouts, shows the Home sidebar with this entry selected.
  final HomeSection? homeSection;

  /// The direct message selected in the Home sidebar.
  final String? selectedConversationId;

  /// Whether the page brings its own sidebar (a circle's channels), which
  /// then shows the voice panel instead of the rail.
  final bool pageHasSidebar;
}

/// Counts full-screen pages pushed with [Navigator.push] on top of the
/// router's pages (channel feeds, events, settings screens), so phones can
/// hide the tabs there like on routed pages. Sheets and dialogs don't count.
class PushedPageObserver extends NavigatorObserver {
  final ValueNotifier<int> pushedPages = ValueNotifier(0);
  var _count = 0;

  static bool _counts(Route<dynamic>? route) {
    return route is PageRoute && route.settings is! Page;
  }

  void _update(int delta) {
    _count = (_count + delta).clamp(0, 1 << 20);
    // Navigator callbacks can arrive mid-build; tell listeners afterwards.
    final count = _count;
    scheduleMicrotask(() => pushedPages.value = count);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route)) {
      _update(1);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route)) {
      _update(-1);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route)) {
      _update(-1);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _update((_counts(newRoute) ? 1 : 0) - (_counts(oldRoute) ? 1 : 0));
  }
}

/// The signed-in app frame. Wide layouts keep the circle rail on the left,
/// with the Home sidebar beside it on Home pages; phones get a bottom bar
/// with Home, Messages, Notifications and You on each tab's root page.
class WeCordShell extends ConsumerWidget {
  const WeCordShell({
    required this.placement,
    required this.onTabSelected,
    required this.child,
    this.onOpenVoice,
    this.pushedPages,
    super.key,
  });

  final ShellPlacement placement;

  /// How many pages are pushed on top of the current one (see
  /// [PushedPageObserver]); phones hide the tabs while any are.
  final ValueListenable<int>? pushedPages;
  final ValueChanged<WeCordTab> onTabSelected;
  final Widget child;

  /// Opens the voice channel of the current call.
  final ValueChanged<VoiceSession>? onOpenVoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keyed so the pages keep their state when the frame around them
    // changes (sidebar or tabs shown or hidden, window resized).
    final shellChild = KeyedSubtree(
      key: _bodyKey,
      child: AppKeyboardShortcuts(
        child: NotificationShellListener(
          child: IncomingCallListener(child: PushShellListener(child: child)),
        ),
      ),
    );

    if (isWideLayout(MediaQuery.sizeOf(context).width)) {
      final homeSection = placement.homeSection;
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleRail(
              homeSelected: placement.homeSelected,
              selectedCircleId: placement.selectedCircleId,
              showVoiceIndicator:
                  homeSection == null && !placement.pageHasSidebar,
              onOpenVoice: onOpenVoice,
            ),
            if (homeSection != null) ...[
              HomeSidebar(
                section: homeSection,
                selectedConversationId: placement.selectedConversationId,
                onOpenVoice: onOpenVoice,
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(child: shellChild),
          ],
        ),
      );
    }

    final tab = placement.tab;
    if (tab == null) {
      return Scaffold(body: shellChild);
    }
    final pushedPages = this.pushedPages;
    if (pushedPages == null) {
      return _withTabs(ref, tab, shellChild);
    }
    return ValueListenableBuilder<int>(
      valueListenable: pushedPages,
      child: shellChild,
      builder: (context, pushed, body) =>
          pushed > 0 ? Scaffold(body: body) : _withTabs(ref, tab, body!),
    );
  }

  static final _bodyKey = GlobalKey(debugLabel: 'shell-body');

  Widget _withTabs(WidgetRef ref, WeCordTab tab, Widget shellChild) {
    final directUnread = ref.watch(directUnreadCountProvider);
    final inboxCount = ref.watch(inboxBadgeCountProvider);
    return Scaffold(
      body: shellChild,
      // While in a voice call, its panel sits above the navigation bar.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VoiceConnectedPanel(onOpen: onOpenVoice),
          NavigationBar(
            selectedIndex: tab.index,
            onDestinationSelected: (index) =>
                onTabSelected(WeCordTab.values[index]),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home),
                label: tr('Home'),
              ),
              NavigationDestination(
                icon: _badged(directUnread, Icons.chat_bubble_outline),
                selectedIcon: _badged(directUnread, Icons.chat_bubble),
                label: tr('Messages'),
              ),
              NavigationDestination(
                icon: _badged(inboxCount, Icons.notifications_none),
                selectedIcon: _badged(inboxCount, Icons.notifications),
                label: tr('Notifications'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
                label: tr('You'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _badged(int count, IconData icon) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: Icon(icon),
    );
  }
}
