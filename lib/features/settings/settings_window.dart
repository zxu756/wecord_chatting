import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:wecord/features/accessibility/chat_text_scale.dart';
import 'package:wecord/features/admin/admin_entry.dart';
import 'package:wecord/features/feedback/feedback_entry.dart';
import 'package:wecord/features/ai/ai_settings.dart';
import 'package:wecord/features/chats/quick_reaction.dart';
import 'package:wecord/features/legal/about_screen.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/pwa/install_app_tile.dart';
import 'package:wecord/features/qr/qr_entries.dart';
import 'package:wecord/features/settings/chat_settings.dart';
import 'package:wecord/features/settings/profile_editor.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/features/settings/settings_providers.dart';
import 'package:wecord/features/settings/settings_sections.dart';
import 'package:wecord/features/voice/voice_settings_screen.dart';
import 'package:wecord/features/wallpapers/wallpaper_settings.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The pages of the desktop settings window, in nav order.
enum SettingsWindowSection {
  profile,
  privacy,
  appearance,
  voice,
  ai,
  chats,
  notifications,
  shortcuts,
  language,
}

/// The page the settings window last showed, so a window that is opened
/// again (or rebuilt under it) comes back on the same page.
final settingsWindowSectionProvider = StateProvider<SettingsWindowSection>(
  (ref) => SettingsWindowSection.appearance,
);

/// The desktop settings window as a route over the whole app: a centered
/// rounded window on a blurred, dimmed app (plain dimming when glass
/// effects are off or motion is reduced).
Route<void> settingsWindowRoute(
  BuildContext context, {
  SettingsWindowSection? initial,
}) {
  final reduceMotion = WeCordMotion.reduceMotion(context);
  final spring = WeCordMotion.smooth;
  return RawDialogRoute<void>(
    barrierDismissible: true,
    barrierLabel: tr('Close settings'),
    barrierColor: null,
    transitionDuration: reduceMotion ? Duration.zero : spring.duration,
    pageBuilder: (context, animation, secondaryAnimation) =>
        SettingsWindow(initial: initial),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final c = context.tokens.colors;
      final glass = WeCordAppearance.glassOf(context);
      final eased = CurvedAnimation(
        parent: animation,
        curve: spring.curve,
        reverseCurve: Curves.easeInCubic,
      );
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final t = animation.value;
                  final scrim = ColoredBox(
                    color: c.scrim.withValues(
                      alpha: c.scrim.a * t * (glass ? 0.85 : 1.2).clamp(0, 1),
                    ),
                  );
                  if (!glass || t == 0) {
                    return scrim;
                  }
                  return BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 6 * t, sigmaY: 6 * t),
                    child: scrim,
                  );
                },
              ),
            ),
          ),
          FadeTransition(
            opacity: eased,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(eased),
              child: child,
            ),
          ),
        ],
      );
    },
  );
}

/// Settings on desktop: a 248px nav of categories (account header on
/// top, sign out at the bottom) beside the chosen page.
class SettingsWindow extends ConsumerStatefulWidget {
  const SettingsWindow({this.initial, super.key});

  /// The page to open on; the last page shown when null.
  final SettingsWindowSection? initial;

  @override
  ConsumerState<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends ConsumerState<SettingsWindow> {
  late SettingsWindowSection _section =
      widget.initial ?? ref.read(settingsWindowSectionProvider);
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1140, maxHeight: 800),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: tr('Settings'),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  key: const ValueKey('settings-window'),
                  decoration: BoxDecoration(
                    color: c.paper,
                    borderRadius: BorderRadius.circular(WeCordRadii.xxl),
                    boxShadow: tokens.shadows.dialog,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SettingsNav(
                        selected: _section,
                        onSelect: (section) {
                          setState(() => _section = section);
                          ref
                                  .read(settingsWindowSectionProvider.notifier)
                                  .state =
                              section;
                        },
                      ),
                      Expanded(
                        child: SettingsWindowScope(
                          onClose: _close,
                          child: ScaffoldMessenger(
                            key: _messengerKey,
                            child: HeroControllerScope.none(
                              child: Navigator(
                                key: ValueKey(_section),
                                onGenerateRoute: (settings) =>
                                    MaterialPageRoute<void>(
                                      settings: settings,
                                      builder: (context) =>
                                          _SectionPage(section: _section),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsNav extends ConsumerWidget {
  const _SettingsNav({required this.selected, required this.onSelect});

  final SettingsWindowSection selected;
  final ValueChanged<SettingsWindowSection> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final profile = ref.watch(currentProfileProvider).value;
    final name = profile?.displayLabel ?? '';
    Widget item(SettingsWindowSection section, IconData icon, String label) {
      return _NavItem(
        key: ValueKey('settings-nav-${section.name}'),
        icon: icon,
        label: label,
        selected: section == selected,
        onPressed: () => onSelect(section),
      );
    }

    Widget groupLabel(String text, {double top = 8}) => Padding(
      padding: EdgeInsets.fromLTRB(10, top, 10, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: c.subtle,
        ),
      ),
    );

    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(right: BorderSide(color: c.lineSoft)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 14),
      child: FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 16),
              child: Row(
                children: [
                  ProfileAvatar(
                    name: name,
                    avatarUrl: profile?.avatarUrl,
                    size: 40,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                          ),
                        ),
                        WeCordPressable(
                          key: const ValueKey('settings-nav-edit-profile'),
                          pressedScale: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          onPressed: () =>
                              onSelect(SettingsWindowSection.profile),
                          builder: (context, states) => Text(
                            tr('Edit profile'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.accentText,
                              decoration: states.contains(WidgetState.hovered)
                                  ? TextDecoration.underline
                                  : null,
                              decorationColor: c.accentText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  groupLabel(tr('Account')),
                  item(
                    SettingsWindowSection.profile,
                    Icons.person_outline_rounded,
                    tr('My profile'),
                  ),
                  item(
                    SettingsWindowSection.privacy,
                    Icons.shield_outlined,
                    tr('Privacy & Safety'),
                  ),
                  groupLabel(tr('App'), top: 12),
                  item(
                    SettingsWindowSection.appearance,
                    Icons.palette_outlined,
                    tr('Appearance'),
                  ),
                  item(
                    SettingsWindowSection.chats,
                    Icons.chat_bubble_outline_rounded,
                    tr('Chats'),
                  ),
                  item(
                    SettingsWindowSection.voice,
                    Icons.headset_mic_outlined,
                    tr('Voice & video'),
                  ),
                  item(
                    SettingsWindowSection.ai,
                    Icons.auto_awesome_outlined,
                    tr('AI'),
                  ),
                  item(
                    SettingsWindowSection.notifications,
                    Icons.notifications_none_rounded,
                    tr('Notifications'),
                  ),
                  if (!usesTouchInput(context))
                    item(
                      SettingsWindowSection.shortcuts,
                      Icons.keyboard_outlined,
                      tr('Keyboard shortcuts'),
                    ),
                  item(
                    SettingsWindowSection.language,
                    Icons.translate_rounded,
                    tr('Language'),
                  ),
                ],
              ),
            ),
            _NavItem(
              key: const ValueKey('settings-nav-sign-out'),
              icon: Icons.logout_rounded,
              label: tr('Sign out'),
              danger: true,
              onPressed: () => unawaited(signOutEverywhere(ref)),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.danger = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: WeCordPressable(
        selected: selected,
        pressedScale: 0.98,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.sm),
        ),
        onPressed: onPressed,
        builder: (context, states) {
          final hovered = states.contains(WidgetState.hovered);
          final foreground = danger
              ? c.dangerText
              : selected
              ? c.ink
              : Color.lerp(c.muted, c.ink, 0.35)!;
          return AnimatedContainer(
            duration: WeCordMotion.quick,
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? (tokens.isDark ? c.raised : c.panel)
                  : hovered
                  ? c.ink.withValues(alpha: 0.05)
                  : c.ink.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(WeCordRadii.sm),
              boxShadow: selected ? tokens.shadows.hairline : null,
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One page of the window.
class _SectionPage extends ConsumerWidget {
  const _SectionPage({required this.section});

  final SettingsWindowSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    List<Widget> withProfile(List<Widget> Function(Profile) build) {
      return switch (profile) {
        AsyncData(:final value) => build(value),
        AsyncError(:final error) => [SettingsErrorText(error)],
        _ => const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      };
    }

    switch (section) {
      case SettingsWindowSection.profile:
        return SettingsPage(
          title: tr('My profile'),
          children: withProfile(
            (profile) => [
              const SizedBox(height: 12),
              ProfileEditor(profile: profile),
              SettingsStatusGroup(profile: profile),
              const SizedBox(height: 12),
              const ProfileToolsGroup(),
            ],
          ),
        );
      case SettingsWindowSection.privacy:
        return SettingsPage(
          title: tr('Privacy & Safety'),
          children: withProfile(
            (profile) => [
              const SizedBox(height: 16),
              const PrivacySettingsGroup(),
              const AdminConsoleEntry(),
              const FeedbackSettingsEntry(),
              const AboutSettingsEntry(),
              AccountActionsGroup(
                username: profile.username,
                header: tr('Account'),
                showSignOut: false,
              ),
            ],
          ),
        );
      case SettingsWindowSection.appearance:
        return SettingsPage(
          title: tr('Appearance'),
          children: [
            SettingsSectionHeader(tr('Theme')),
            const ThemeModePicker(large: true),
            SettingsGroup(
              header: tr('Display'),
              children: const [
                GlassEffectsRow(showIcon: false),
                DensityRow(showIcon: false),
                ChatTextSizeRow(showIcon: false),
                ChatWallpaperRow(showIcon: false),
              ],
            ),
            const InstallAppGroup(),
          ],
        );
      case SettingsWindowSection.voice:
        // Voice brings its own page; the window adds its close button.
        return Stack(
          children: [
            const VoiceSettingsScreen(),
            Positioned(
              top: 10,
              right: 14,
              child: WeCordIconButton(
                key: const ValueKey('settings-window-close'),
                icon: Icons.close_rounded,
                tooltip: tr('Close settings'),
                variant: WeCordButtonVariant.onPaper,
                size: 36,
                iconSize: 18,
                onPressed: SettingsWindowScope.maybeOf(context)?.onClose,
              ),
            ),
          ],
        );
      case SettingsWindowSection.ai:
        return SettingsPage(
          title: tr('AI'),
          children: const [
            SizedBox(height: 16),
            AiSettingsGroup(showHeader: false),
          ],
        );
      case SettingsWindowSection.chats:
        return SettingsPage(
          title: tr('Chats'),
          children: const [
            SizedBox(height: 16),
            ChatSettingsGroup(),
            QuickReactionSettingsGroup(),
          ],
        );
      case SettingsWindowSection.notifications:
        return SettingsPage(
          title: tr('Notifications'),
          children: const [NotificationSettingsGroups(showHeader: false)],
        );
      case SettingsWindowSection.shortcuts:
        return SettingsPage(
          title: tr('Keyboard shortcuts'),
          children: [
            const SizedBox(height: 16),
            const KeyboardShortcutsGroup(),
          ],
        );
      case SettingsWindowSection.language:
        return SettingsPage(
          title: tr('Language'),
          children: [
            SettingsSectionHeader(tr('Interface language')),
            const LanguageOptions(),
          ],
        );
    }
  }
}
