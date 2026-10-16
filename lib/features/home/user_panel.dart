import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/features/home/phone_home.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The signed-in user in the floating glass pill at the bottom of the
/// desktop rail and sidebar: avatar with presence, name and status (tap to
/// change either), the microphone and sound during a call, and settings.
/// The shell places it across the rail and the sidebar.
class UserPanel extends ConsumerWidget {
  const UserPanel({super.key});

  /// Room a sidebar keeps free at its bottom for the panel.
  static const reservedHeight =
      FloatingUserPanel.desktopHeight + bottomGap + 10;

  /// Space between the panel and the window's bottom edge.
  static const bottomGap = 14.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    // Invisible (or online status hidden) shows as such here, though
    // others see the user offline.
    final presence = ref.watch(ownPresenceProvider);
    final status = activeCustomStatus(profile?.customStatus);
    final name = userPanelName(profile);
    final session = ref.watch(voiceSessionProvider);
    final controller = ref.read(voiceSessionProvider.notifier);

    return FloatingUserPanel(
      key: const ValueKey('user-panel'),
      compact: true,
      title: name,
      subtitle: userPanelStatusLine(presence, status),
      semanticLabel: tr('Set your status'),
      onTap: profile == null
          ? null
          : () => showUserStatusPicker(context, ref, status),
      avatar: ResolvedAvatar(
        name: name,
        avatarUrl: profile?.avatarUrl,
        size: 42,
        showPresence: true,
        presence: presence,
        ringColor: tokens.glass.solidFill,
        dotKey: ValueKey('user-panel-presence-${presence.value}'),
      ),
      actions: [
        if (session != null) ...[
          WeCordIconButton(
            key: const ValueKey('user-panel-mic'),
            icon: session.selfMute || session.serverMute
                ? Icons.mic_off_rounded
                : Icons.mic_none_rounded,
            tooltip: voiceMuteTooltip(session),
            variant: WeCordButtonVariant.ghost,
            size: 36,
            iconSize: 19,
            selected: session.selfMute || session.serverMute,
            onPressed: session.isConnected && !session.serverMute
                ? () => runVoiceAction(context, controller.toggleMute)
                : null,
          ),
          WeCordIconButton(
            key: const ValueKey('user-panel-deafen'),
            icon: session.selfDeaf
                ? Icons.headset_off_rounded
                : Icons.headphones_rounded,
            tooltip: voiceDeafenTooltip(session),
            variant: WeCordButtonVariant.ghost,
            size: 36,
            iconSize: 19,
            selected: session.selfDeaf,
            onPressed: session.isConnected
                ? () => runVoiceAction(context, controller.toggleDeafen)
                : null,
          ),
        ],
        WeCordIconButton(
          key: const ValueKey('user-panel-settings'),
          icon: Icons.settings_outlined,
          tooltip: tr('User settings'),
          variant: WeCordButtonVariant.ghost,
          size: 36,
          iconSize: 19,
          onPressed: () => context.go(SettingsScreen.path),
        ),
      ],
    );
  }
}
