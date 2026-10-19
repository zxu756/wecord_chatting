import 'package:flutter/material.dart';
import 'package:wecord/features/announcements/whats_new_host.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/home/home_sidebar.dart';
import 'package:wecord/features/home/user_panel.dart';
import 'package:wecord/features/location/live_location_sharer.dart';
import 'package:wecord/features/notifications/notification_shell_listener.dart';
import 'package:wecord/features/push/push_shell_listener.dart';
import 'package:wecord/features/pwa/pwa_shell_listener.dart';
import 'package:wecord/features/shell/keyboard_shortcuts.dart';
import 'package:wecord/features/voice/direct_call_view.dart';
import 'package:wecord/features/voice/mini_player/call_mini_player.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/layout/resizable_panels.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Where the current page sits in the app's navigation.
class ShellPlacement {
  const ShellPlacement({
    this.homeSelected = false,
    this.selectedCircleId,
    this.homeSection,
    this.selectedConversationId,
    this.pageHasSidebar = false,
    this.exploreSelected = false,
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

  /// Whether the rail highlights Explore (public circles).
  final bool exploreSelected;
}

/// The signed-in app frame. Wide layouts keep the circle rail on the left
/// on the rail color; beside it, 10 below the window's top, the Home
/// sidebar (with a 22 top-left corner; its right edge resizes it) and the
/// page on a white panel. The glass user panel floats across the rail and
/// the sidebar (Home's, or a circle's channels) and follows its width.
/// Phones show pages full screen: the phone home (and
/// a circle's channels) bring the rail and the floating user panel
/// themselves, other pages stack on top with a back button.
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

  /// Space between the window's top and the sidebar and page.
  static const topGap = 10.0;

  @override
  Widget build(BuildContext context) {
    // Keyed so the pages keep their state when the frame around them
    // changes (sidebar shown or hidden, window resized).
    final shellChild = KeyedSubtree(
      key: _bodyKey,
      child: AppKeyboardShortcuts(
        child: NotificationShellListener(
          child: LiveLocationShellListener(
            child: IncomingCallListener(
              child: PushShellListener(
                child: PwaShellListener(child: WhatsNewHost(child: child)),
              ),
            ),
          ),
        ),
      ),
    );

    // The call's mini player floats over whichever page this is.
    Widget withMiniPlayer(Widget page) =>
        CallMiniPlayerHost(onOpen: onOpenVoice, child: page);

    if (!isWideLayout(MediaQuery.sizeOf(context).width)) {
      return withMiniPlayer(Scaffold(body: shellChild));
    }

    final c = context.tokens.colors;
    final homeSection = placement.homeSection;
    // Whether the user panel spans the rail and a sidebar (Home's, or a
    // circle's channels; both share one width).
    final spansSidebar = homeSection != null || placement.pageHasSidebar;
    const radius = BorderRadius.only(topLeft: Radius.circular(WeCordRadii.xl));

    final Widget content = homeSection != null
        ? ClipRRect(
            borderRadius: radius,
            child: ResizableSidebarRow(
              sidebar: ColoredBox(
                color: c.sidebar,
                child: HomeSidebar(
                  section: homeSection,
                  selectedConversationId: placement.selectedConversationId,
                  onOpenVoice: onOpenVoice,
                  width: null,
                ),
              ),
              content: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: c.lineSoft)),
                ),
                child: ColoredBox(color: c.panel, child: shellChild),
              ),
            ),
          )
        : PanelSurface(topLeftRadius: WeCordRadii.xl, child: shellChild);

    final frame = ColoredBox(
      color: c.rail,
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CircleRail(
                  homeSelected: placement.homeSelected,
                  exploreSelected: placement.exploreSelected,
                  selectedCircleId: placement.selectedCircleId,
                  showVoiceIndicator: !spansSidebar,
                  onOpenVoice: onOpenVoice,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: topGap),
                    child: content,
                  ),
                ),
              ],
            ),
          ),
          if (spansSidebar)
            // Follows the sidebar while it is resized.
            SidebarWidthBuilder(
              available: MediaQuery.sizeOf(context).width - CircleRail.width,
              builder: (context, sidebarWidth) => Positioned(
                left: 10,
                bottom: UserPanel.bottomGap,
                width: CircleRail.width + sidebarWidth - 20,
                child: const UserPanel(),
              ),
            ),
        ],
      ),
    );
    return withMiniPlayer(
      Scaffold(
        backgroundColor: c.rail,
        // In the macOS app the rail keeps the traffic lights clear itself;
        // pages beside it start near the top of the window.
        body: drawsUnderMacosTitleBar
            ? MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: frame,
              )
            : frame,
      ),
    );
  }

  static final _bodyKey = GlobalKey(debugLabel: 'shell-body');
}
