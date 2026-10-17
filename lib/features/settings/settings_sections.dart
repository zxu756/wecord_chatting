import 'dart:async';

import 'package:wecord/features/settings/data_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/presence/presence_status_sheet.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/push/push_controller.dart';
import 'package:wecord/features/push/push_settings_tile.dart';
import 'package:wecord/features/settings/account_deletion.dart';
import 'package:wecord/features/settings/custom_status_sheet.dart';
import 'package:wecord/features/settings/settings_providers.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/settings/two_factor_settings_screen.dart';
import 'package:wecord/features/shell/keyboard_shortcuts.dart';
import 'package:wecord/features/voice/voice_settings_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/theme/density_controller.dart';
import 'package:wecord/shared/theme/glass_effects_controller.dart';
import 'package:wecord/shared/theme/theme_mode_controller.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The account card at the top of the phone settings: avatar with
/// presence, name, and Edit (opens the profile editor).
class SettingsAccountCard extends ConsumerWidget {
  const SettingsAccountCard({
    required this.profile,
    required this.onEdit,
    super.key,
  });

  final Profile profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final presence = ref.watch(ownPresenceProvider);
    return WeCordPressable(
      key: const ValueKey('settings-account-card'),
      onPressed: onEdit,
      semanticLabel: tr('Edit profile'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.03), c.panel)
                : c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
          ),
          child: Row(
            children: [
              ProfileAvatar(
                key: const ValueKey('settings-account-avatar'),
                name: profile.displayLabel,
                avatarUrl: profile.avatarUrl,
                size: 58,
                presence: presenceColor(context, presence),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr('Profile, banner and pronouns'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ExcludeSemantics(
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: c.raised,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    tr('Edit'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Online / Idle / Do Not Disturb / Invisible and the custom status.
class SettingsStatusGroup extends ConsumerWidget {
  const SettingsStatusGroup({required this.profile, super.key});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final presence = ref.watch(ownPresenceProvider);
    final status = activeCustomStatus(profile.customStatus);
    final expiresAt = status?.expiresAt;
    return SettingsGroup(
      header: tr('Status'),
      children: [
        SettingsRow(
          key: const ValueKey('presence-status-tile'),
          title: tr('Online status'),
          icon: Icons.online_prediction_rounded,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PresenceIndicator(
                status: presence,
                borderColor: c.panel,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                presence.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
            ],
          ),
          showChevron: true,
          onTap: () => showPresenceStatusSheet(context),
        ),
        SettingsRow(
          key: const ValueKey('custom-status-tile'),
          title: status == null
              ? tr('Set status')
              : (status.text ?? status.emoji ?? tr('Status')),
          subtitle: status == null
              ? null
              : expiresAt == null
              ? tr("Doesn't clear")
              : formatStatusExpiry(expiresAt),
          icon: status == null
              ? Icons.add_reaction_outlined
              : Icons.emoji_emotions_outlined,
          trailing: status?.emoji == null || status?.text == null
              ? null
              : Text(status!.emoji!, style: const TextStyle(fontSize: 20)),
          showChevron: true,
          onTap: () => _editCustomStatus(context, ref, status),
        ),
      ],
    );
  }

  Future<void> _editCustomStatus(
    BuildContext context,
    WidgetRef ref,
    CustomStatus? current,
  ) async {
    final saved = await showCustomStatusSheet(context, current: current);
    if (saved == true) {
      ref.invalidate(currentProfileProvider);
    }
  }
}

/// When a custom status clears: "Clears at 14:30" or a date.
String formatStatusExpiry(DateTime expiresAt) {
  final local = expiresAt.toLocal();
  final now = DateTime.now();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) {
    return tr('Clears at {time}', {'time': time});
  }
  return tr('Clears on {month}/{day} at {time}', {
    'month': local.month,
    'day': local.day,
    'time': time,
  });
}

/// Light, dark or following the system, as preview cards: compact on
/// phones, large with a sketch of the app on desktop.
class ThemeModePicker extends ConsumerWidget {
  const ThemeModePicker({this.large = false, super.key});

  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(themeModeProvider);
    final options = [
      (ThemeMode.light, tr('Light')),
      (ThemeMode.dark, tr('Dark')),
      (ThemeMode.system, tr('System')),
    ];
    return Semantics(
      key: const ValueKey('theme-mode'),
      container: true,
      label: tr('Theme'),
      child: Row(
        children: [
          for (final (index, (mode, label)) in options.indexed) ...[
            if (index > 0) SizedBox(width: large ? 14 : 8),
            Expanded(
              child: _ThemeCard(
                key: ValueKey('theme-mode-${mode.name}'),
                mode: mode,
                label: label,
                large: large,
                selected: mode == selected,
                onPressed: () => ref.read(themeModeProvider.notifier).set(mode),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.mode,
    required this.label,
    required this.large,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final ThemeMode mode;
  final String label;
  final bool large;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final radius = large ? 18.0 : WeCordRadii.lg;
    return WeCordPressable(
      selected: selected,
      semanticLabel: label,
      onPressed: () {
        if (!selected) {
          WeCordHaptics.selection();
          onPressed();
        }
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        final border = selected
            ? Border.all(color: c.accent, width: 2)
            : Border.all(color: hovered ? c.faint : c.line);
        final text = Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: large ? 13.5 : 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: c.ink,
          ),
        );
        if (large) {
          return AnimatedContainer(
            duration: WeCordMotion.quick,
            padding: EdgeInsets.all(selected ? 9 : 10),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: BorderRadius.circular(radius),
              border: border,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 96, child: _ThemeSketch(mode: mode)),
                const SizedBox(height: 8),
                text,
              ],
            ),
          );
        }
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          height: 84,
          padding: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: c.paper,
            borderRadius: BorderRadius.circular(radius),
            border: border,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ThemeSwatch(mode: mode),
              const SizedBox(height: 6),
              text,
            ],
          ),
        );
      },
    );
  }
}

/// The small 44×30 swatch on a phone theme card.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    const light = WeCordPalette.light;
    const dark = WeCordPalette.dark;
    final c = context.tokens.colors;
    return Container(
      width: 44,
      height: 30,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: mode == ThemeMode.dark ? dark.panel : light.panel,
        gradient: mode == ThemeMode.system
            ? LinearGradient(
                colors: [light.panel, light.panel, dark.panel, dark.panel],
                stops: const [0, 0.5, 0.5, 1],
              )
            : null,
        border: mode == ThemeMode.dark && !context.tokens.isDark
            ? null
            : Border.all(color: c.line),
      ),
    );
  }
}

/// A sketch of the app (rail, panel, two bubbles) in a theme's colors,
/// for the desktop theme cards.
class _ThemeSketch extends StatelessWidget {
  const _ThemeSketch({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    if (mode == ThemeMode.system) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: const Row(
          children: [
            Expanded(child: _ThemeSketchPane(palette: WeCordPalette.light)),
            Expanded(child: _ThemeSketchPane(palette: WeCordPalette.dark)),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: _ThemeSketchPane(
        palette: mode == ThemeMode.dark
            ? WeCordPalette.dark
            : WeCordPalette.light,
        full: true,
      ),
    );
  }
}

class _ThemeSketchPane extends StatelessWidget {
  const _ThemeSketchPane({required this.palette, this.full = false});

  final WeCordPalette palette;
  final bool full;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.rail,
      padding: const EdgeInsets.all(8),
      child: !full
          ? null
          : Row(
              children: [
                Container(
                  width: 18,
                  decoration: BoxDecoration(
                    color: palette.track,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: palette.panel,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.6,
                          child: _bar(palette.raised),
                        ),
                        const SizedBox(height: 6),
                        FractionallySizedBox(
                          alignment: Alignment.centerRight,
                          widthFactor: 0.4,
                          child: _bar(
                            identical(palette, WeCordPalette.dark)
                                ? palette.accent
                                : palette.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  static Widget _bar(Color color) => Container(
    height: 8,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

/// Glass effects on or off.
class GlassEffectsRow extends ConsumerWidget {
  const GlassEffectsRow({this.showIcon = true, super.key});

  final bool showIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsRow.toggle(
      key: const ValueKey('glass-effects'),
      icon: showIcon ? Icons.blur_on_rounded : null,
      title: tr('Glass effects'),
      subtitle: tr(
        'Floating bars and menus are translucent. Turn off to save power.',
      ),
      value: ref.watch(glassEffectsProvider),
      onChanged: (value) => ref.read(glassEffectsProvider.notifier).set(value),
    );
  }
}

/// Comfortable, Default or Compact lists and messages: a segmented control
/// beside its label in the desktop window, below it on phones.
class DensityRow extends ConsumerWidget {
  const DensityRow({this.showIcon = true, super.key});

  final bool showIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final picker = WeCordSegmented<WeCordDensity>(
      key: const ValueKey('density'),
      expand: true,
      semanticLabel: tr('Density'),
      selected: ref.watch(densityProvider),
      onChanged: (density) => ref.read(densityProvider.notifier).set(density),
      segments: [
        WeCordSegment(
          key: const ValueKey('density-comfortable'),
          value: WeCordDensity.comfortable,
          label: tr('Comfortable'),
        ),
        WeCordSegment(
          key: const ValueKey('density-standard'),
          value: WeCordDensity.standard,
          label: tr('Default'),
        ),
        WeCordSegment(
          key: const ValueKey('density-compact'),
          value: WeCordDensity.compact,
          label: tr('Compact'),
        ),
      ],
    );
    final label = Row(
      children: [
        if (showIcon) ...[
          const SettingsIconTile(icon: Icons.density_medium_rounded),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('Density'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  tr('How much space lists and messages take.'),
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Padding(
      key: const ValueKey('density-row'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 560
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [label, const SizedBox(height: 12), picker],
              )
            : Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 16),
                  SizedBox(width: 360, child: picker),
                ],
              ),
      ),
    );
  }
}

/// The name of [language] in its own words.
String appLanguageLabel(AppLanguage language) => switch (language) {
  AppLanguage.system => tr('System'),
  AppLanguage.english => 'English',
  AppLanguage.chinese => '中文',
};

/// Lets the user pick the interface language from a sheet.
Future<void> showLanguageSheet(BuildContext context) {
  return showWeCordSheet<void>(
    context,
    title: tr('Language'),
    builder: (context, _) => const SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: LanguageOptions(popOnPick: true),
      ),
    ),
  );
}

/// System / English / 中文 as rows with a check on the current one.
class LanguageOptions extends ConsumerWidget {
  const LanguageOptions({this.popOnPick = false, super.key});

  /// Closes the sheet it is in after a pick.
  final bool popOnPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final current = ref.watch(appLanguageProvider);
    return SettingsGroup(
      key: const ValueKey('app-language'),
      color: popOnPick ? c.well : null,
      separatorIndent: 14,
      children: [
        for (final language in AppLanguage.values)
          SettingsRow(
            key: ValueKey('app-language-${language.name}'),
            title: appLanguageLabel(language),
            subtitle: language == AppLanguage.system
                ? tr('Follow the language of this device')
                : null,
            trailing: language == current
                ? Icon(Icons.check_rounded, size: 20, color: c.accent)
                : const SizedBox(width: 20),
            onTap: () {
              WeCordHaptics.selection();
              unawaited(ref.read(appLanguageProvider.notifier).set(language));
              if (popOnPick) {
                Navigator.of(context).pop();
              }
            },
          ),
      ],
    );
  }
}

/// Opens Voice & video settings.
class VoiceSettingsRow extends StatelessWidget {
  const VoiceSettingsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      key: const ValueKey('voice-settings-tile'),
      icon: Icons.headset_mic_outlined,
      title: tr('Voice & video'),
      subtitle: tr('Push to talk, noise suppression and echo cancellation'),
      onTap: () => openVoiceSettings(context),
    );
  }
}

/// Notifications on or off, previews, push on this browser, the device
/// permission and a test notification.
class NotificationSettingsGroups extends ConsumerStatefulWidget {
  const NotificationSettingsGroups({this.showHeader = true, super.key});

  /// Whether the first group is headed "Notifications" (not on a page
  /// already titled so).
  final bool showHeader;

  @override
  ConsumerState<NotificationSettingsGroups> createState() =>
      _NotificationSettingsGroupsState();
}

class _NotificationSettingsGroupsState
    extends ConsumerState<NotificationSettingsGroups> {
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final preferences =
        ref.watch(currentNotificationPreferencesProvider).value ??
        NotificationPreferences.defaults;
    final permission =
        ref.watch(currentNotificationPermissionStatusProvider).value ??
        NotificationPermissionStatus.notRequested;
    final granted = permission == NotificationPermissionStatus.granted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.showHeader) const SizedBox(height: 16),
        SettingsGroup(
          header: widget.showHeader ? tr('Notifications') : null,
          children: [
            SettingsRow.toggle(
              key: const ValueKey('notifications-enabled'),
              icon: Icons.notifications_none_rounded,
              title: tr('Notifications'),
              value: preferences.enabled,
              onChanged: (enabled) =>
                  _save(preferences.copyWith(enabled: enabled)),
            ),
            SettingsRow.toggle(
              key: const ValueKey('notifications-previews'),
              icon: Icons.chat_bubble_outline_rounded,
              title: tr('Message previews'),
              value: preferences.showPreviews,
              onChanged: preferences.enabled
                  ? (show) => _save(preferences.copyWith(showPreviews: show))
                  : null,
            ),
            // Only where web push is available (the tile is empty elsewhere).
            if (ref.watch(pushStatusProvider).value case final push?
                when push != PushStatus.unsupported)
              const PushSettingsTile(),
          ],
        ),
        const SizedBox(height: 12),
        SettingsGroup(
          footer: _errorText,
          children: [
            SettingsRow(
              key: const ValueKey('notifications-permission'),
              icon: granted
                  ? Icons.verified_outlined
                  : Icons.notifications_paused_outlined,
              tone: granted ? SettingsTone.success : SettingsTone.neutral,
              title: tr('Request permission'),
              subtitle: _permissionStatusLabel(permission),
              onTap: _requestPermission,
              showChevron: false,
            ),
            SettingsRow(
              key: const ValueKey('notifications-test'),
              icon: Icons.send_outlined,
              title: tr('Send test notification'),
              onTap: _sendTest,
              showChevron: false,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _save(NotificationPreferences preferences) async {
    await ref.read(notificationPreferencesRepositoryProvider).save(preferences);
    ref.invalidate(currentNotificationPreferencesProvider);
  }

  Future<void> _requestPermission() async {
    await ref.read(localNotificationServiceProvider).requestPermission();
    ref.invalidate(currentNotificationPermissionStatusProvider);
  }

  Future<void> _sendTest() async {
    final service = ref.read(localNotificationServiceProvider);
    final status = await service.requestPermission();
    ref.invalidate(currentNotificationPermissionStatusProvider);
    if (status != NotificationPermissionStatus.granted) {
      if (mounted) {
        setState(() {
          _errorText = tr('Notifications are not allowed on this device.');
        });
      }
      return;
    }
    try {
      await service.showMessageNotification(
        conversationId: 'settings-test',
        title: 'WeCord',
        body: tr('Notifications are working.'),
      );
      if (mounted && _errorText != null) {
        setState(() => _errorText = null);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = tr('Could not send test notification. Try again.');
        });
      }
    }
  }
}

String _permissionStatusLabel(NotificationPermissionStatus status) {
  return switch (status) {
    NotificationPermissionStatus.notRequested => tr('Permission not requested'),
    NotificationPermissionStatus.granted => tr('Permission granted'),
    NotificationPermissionStatus.denied => tr('Permission denied'),
    NotificationPermissionStatus.unavailable => tr('Notifications unavailable'),
  };
}

/// Show when you are online, two-step verification and blocked users.
class PrivacySettingsGroup extends ConsumerWidget {
  const PrivacySettingsGroup({this.header, super.key});

  final String? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twoFactorOn = switch (ref.watch(twoFactorFactorProvider)) {
      AsyncData(:final value) => value != null,
      _ => null,
    };
    final blockedCount = ref.watch(blockedUsersProvider).value?.length;
    return SettingsGroup(
      header: header,
      children: [
        SettingsRow.toggle(
          key: const ValueKey('show-online-status'),
          icon: Icons.visibility_outlined,
          title: tr('Show when you are online'),
          subtitle: tr('When off, everyone else sees you as offline.'),
          value:
              ref.watch(presenceSettingsProvider).value?.showOnlineStatus ??
              true,
          onChanged: (show) => _setShowOnline(context, ref, show),
        ),
        SettingsRow(
          key: const ValueKey('two-factor-settings-tile'),
          icon: Icons.phonelink_lock_outlined,
          tone: twoFactorOn == true
              ? SettingsTone.success
              : SettingsTone.neutral,
          title: tr('Two-step verification'),
          subtitle: tr(
            'Ask for a code from an authenticator app when signing in',
          ),
          trailing: twoFactorOn == null ? null : _StateLabel(on: twoFactorOn),
          showChevron: true,
          onTap: () => openTwoFactorSettings(context),
        ),
        SettingsRow(
          key: const ValueKey('blocked-users-tile'),
          icon: Icons.block_rounded,
          title: tr('Blocked users'),
          subtitle: tr('Manage people you have blocked'),
          value: blockedCount == null || blockedCount == 0
              ? null
              : '$blockedCount',
          onTap: () => showBlockedUsersSheet(context, ref),
        ),
        SettingsRow(
          key: const ValueKey('data-export-tile'),
          icon: Icons.download_rounded,
          title: tr('Download my data'),
          subtitle: tr('Get a copy of your profile, friends and messages'),
          onTap: () => openDataExport(context),
        ),
      ],
    );
  }

  Future<void> _setShowOnline(
    BuildContext context,
    WidgetRef ref,
    bool show,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(presenceSettingsProvider.notifier)
          .setShowOnlineStatus(show);
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(tr('Could not save privacy settings. Try again.')),
        ),
      );
    }
  }
}

/// "On" in green or "Off", after a setting's title.
class _StateLabel extends StatelessWidget {
  const _StateLabel({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Text(
      on ? trIn('settings-state', 'On') : trIn('settings-state', 'Off'),
      style: TextStyle(
        fontSize: 13,
        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
        color: on ? c.successText : c.muted,
      ),
    );
  }
}

/// Sign out, and delete the account for good.
class AccountActionsGroup extends ConsumerStatefulWidget {
  const AccountActionsGroup({
    required this.username,
    this.header,
    this.showSignOut = true,
    super.key,
  });

  final String username;
  final String? header;
  final bool showSignOut;

  @override
  ConsumerState<AccountActionsGroup> createState() =>
      _AccountActionsGroupState();
}

class _AccountActionsGroupState extends ConsumerState<AccountActionsGroup> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      header: widget.header,
      children: [
        if (widget.showSignOut)
          SettingsRow(
            key: const ValueKey('sign-out'),
            icon: Icons.logout_rounded,
            title: tr('Sign out'),
            showChevron: false,
            onTap: _busy ? null : () => signOutEverywhere(ref),
          ),
        SettingsRow(
          key: const ValueKey('delete-account'),
          icon: Icons.delete_forever_outlined,
          title: tr('Delete account'),
          subtitle: tr('Remove your login and profile for good'),
          destructive: true,
          showChevron: false,
          onTap: _busy ? null : _delete,
        ),
      ],
    );
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await confirmAndDeleteAccount(context, ref, username: widget.username);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

/// Stops push on this device, then signs out.
Future<void> signOutEverywhere(WidgetRef ref) async {
  await stopPushForSignOut(ref);
  await ref.read(authRepositoryProvider).signOut();
}

/// The app-wide keyboard shortcuts with their keys.
class KeyboardShortcutsGroup extends StatelessWidget {
  const KeyboardShortcutsGroup({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SettingsGroup(
      key: const ValueKey('keyboard-shortcuts-list'),
      separatorIndent: 18,
      children: [
        for (final (keys, label) in keyboardShortcutRows())
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  for (final (index, key) in keys.indexed) ...[
                    if (index > 0) const SizedBox(width: 4),
                    KeyCap(key),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A key on the keyboard ("Ctrl", "K").
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(WeCordRadii.xs + 1),
        border: Border(bottom: BorderSide(color: c.line, width: 2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: c.ink,
        ),
      ),
    );
  }
}

/// The people the user blocked, each with Unblock.
Future<void> showBlockedUsersSheet(BuildContext context, WidgetRef ref) {
  return showWeCordSheet<void>(
    context,
    title: tr('Blocked users'),
    builder: (context, _) => const BlockedUsersSheet(),
  );
}

class BlockedUsersSheet extends ConsumerStatefulWidget {
  const BlockedUsersSheet({super.key});

  @override
  ConsumerState<BlockedUsersSheet> createState() => _BlockedUsersSheetState();
}

class _BlockedUsersSheetState extends ConsumerState<BlockedUsersSheet> {
  String? _unblockingUserId;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final blockedUsers = ref.watch(blockedUsersProvider);
    Widget message(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Text(text, style: TextStyle(fontSize: 14, color: c.muted)),
    );
    return SafeArea(
      top: false,
      child: blockedUsers.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => message('$error'),
        data: (users) {
          if (users.isEmpty) {
            return message(tr('You have not blocked anyone.'));
          }
          return ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final unblocking = _unblockingUserId == user.id;
              return Padding(
                key: ValueKey('blocked-user-${user.id}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    ProfileAvatar(
                      name: user.displayLabel,
                      avatarUrl: user.avatarUrl,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            '@${user.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    WeCordButton(
                      label: tr('Unblock'),
                      variant: WeCordButtonVariant.secondary,
                      size: WeCordButtonSize.small,
                      loading: unblocking,
                      onPressed: unblocking ? null : () => _unblock(user.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _unblock(String userId) async {
    setState(() => _unblockingUserId = userId);
    try {
      await ref.read(settingsRepositoryProvider).unblockUser(userId);
      ref.invalidate(blockedUsersProvider);
    } finally {
      if (mounted) {
        setState(() => _unblockingUserId = null);
      }
    }
  }
}
