import 'package:flutter/material.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/home/home_sidebar.dart';
import 'package:wecord/features/notifications/notification_shell_listener.dart';
import 'package:wecord/features/push/push_shell_listener.dart';
import 'package:wecord/features/shell/keyboard_shortcuts.dart';
import 'package:wecord/features/voice/direct_call_view.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/macos_title_bar.dart';

/// Where the current page sits in the app's navigation.
class ShellPlacement {
  const ShellPlacement({
    this.homeSelected = false,
    this.selectedCircleId,
    this.homeSection,
    this.selectedConversationId,
    this.pageHasSidebar = false,
  });

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

/// The signed-in app frame. Wide layouts keep the circle rail on the left,
/// with the Home sidebar beside it on Home pages. Phones show pages full
/// screen: the phone home (and a circle's channels) bring the rail and the
/// floating user panel themselves, other pages stack on top with a back
/// button.
class WeCordShell extends StatelessWidget {
  const WeCordShell({
    required this.placement,
    required this.child,
    this.onOpenVoice,
    super.key,
  });

  final ShellPlacement placement;
  final Widget child;

  /// Opens the voice channel of the current call.
  final ValueChanged<VoiceSession>? onOpenVoice;

  @override
  Widget build(BuildContext context) {
    // Keyed so the pages keep their state when the frame around them
    // changes (sidebar shown or hidden, window resized).
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
      final frame = Row(
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
      );
      return Scaffold(
        // In the macOS app the rail keeps the traffic lights clear itself;
        // pages beside it start at the top of the window.
        body: drawsUnderMacosTitleBar
            ? MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: frame,
              )
            : frame,
      );
    }

    return Scaffold(body: shellChild);
  }

  static final _bodyKey = GlobalKey(debugLabel: 'shell-body');
}
