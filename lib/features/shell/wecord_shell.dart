import 'package:flutter/material.dart';
import 'package:wecord/features/notifications/notification_shell_listener.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';

class WeCordShell extends StatelessWidget {
  const WeCordShell({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
    this.onOpenVoice,
    this.voicePanelInSidebar = false,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  /// Opens the voice channel of the current call.
  final ValueChanged<VoiceSession>? onOpenVoice;

  /// Whether the page shows a circle's channel sidebar, which has its own
  /// voice panel on wide screens (so the rail leaves it out).
  final bool voicePanelInSidebar;

  /// From this width the shell uses a navigation rail instead of the
  /// bottom navigation bar.
  static const railBreakpoint = 720.0;

  @override
  Widget build(BuildContext context) {
    final useRail = MediaQuery.sizeOf(context).width >= railBreakpoint;
    final shellChild = NotificationShellListener(child: child);

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              trailing: voicePanelInSidebar
                  ? null
                  : VoiceRailIndicator(onOpen: onOpenVoice),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: Text('Chats'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.contacts_outlined),
                  selectedIcon: Icon(Icons.contacts),
                  label: Text('Contacts'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.groups_outlined),
                  selectedIcon: Icon(Icons.groups),
                  label: Text('Circles'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: Text('Me'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shellChild),
          ],
        ),
      );
    }

    return Scaffold(
      body: shellChild,
      // While in a voice call, its panel sits above the navigation bar on
      // every page.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VoiceConnectedPanel(onOpen: onOpenVoice),
          NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'Chats',
              ),
              NavigationDestination(
                icon: Icon(Icons.contacts_outlined),
                selectedIcon: Icon(Icons.contacts),
                label: 'Contacts',
              ),
              NavigationDestination(
                icon: Icon(Icons.groups_outlined),
                selectedIcon: Icon(Icons.groups),
                label: 'Circles',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Me',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
