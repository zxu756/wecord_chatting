import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/ai/ai_settings.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/features/settings/profile_editor.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/features/settings/settings_providers.dart';
import 'package:wecord/features/settings/settings_sections.dart';
import 'package:wecord/features/settings/settings_window.dart';
import 'package:wecord/features/shell/keyboard_shortcuts.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

export 'package:wecord/features/settings/settings_providers.dart';
export 'package:wecord/features/settings/settings_sections.dart'
    show showBlockedUsersSheet;

/// Settings (`/me`). Phones show a page of grouped settings with the
/// account card on top; wide layouts open the settings window over the
/// app (the friends page behind it) and go Home when it closes.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  static const path = '/me';

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Route<void>? _window;
  NavigatorState? _windowNavigator;
  var _windowScheduled = false;

  @override
  void dispose() {
    _closeWindowSilently();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWideLayout(MediaQuery.sizeOf(context).width);
    if (wide) {
      _scheduleWindow();
      return const ContactsScreen();
    }
    if (_window != null) {
      _closeWindowSilently();
    }
    return const SettingsPhonePage();
  }

  void _scheduleWindow() {
    if (_window != null || _windowScheduled) {
      return;
    }
    _windowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _windowScheduled = false;
      if (!mounted ||
          _window != null ||
          !isWideLayout(MediaQuery.sizeOf(context).width)) {
        return;
      }
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = settingsWindowRoute(context);
      _window = route;
      _windowNavigator = navigator;
      navigator.push(route).then((_) {
        if (_window != route) {
          // Closed by us: the page went away or turned into the phone one.
          return;
        }
        _window = null;
        if (!mounted) {
          return;
        }
        final router = GoRouter.maybeOf(context);
        if (router != null &&
            router.routerDelegate.currentConfiguration.uri.path ==
                SettingsScreen.path) {
          router.go(HomeScreen.path);
        }
      });
    });
  }

  /// Takes the window down without leaving the page.
  void _closeWindowSilently() {
    final route = _window;
    final navigator = _windowNavigator;
    _window = null;
    if (route == null || navigator == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) {
        navigator.removeRoute(route);
      }
    });
  }
}

/// The phone settings page: account card, status, appearance,
/// preferences, notifications, privacy and the account actions.
class SettingsPhonePage extends ConsumerWidget {
  const SettingsPhonePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    return SettingsPage(
      key: const ValueKey('settings-screen'),
      title: tr('Settings'),
      children: switch (profile) {
        AsyncData(:final value) => [
          const SizedBox(height: 12),
          SettingsAccountCard(
            profile: value,
            onEdit: () => openProfileEditor(context),
          ),
          SettingsStatusGroup(profile: value),
          SettingsSectionHeader(tr('Appearance')),
          const SettingsGroup(
            padding: EdgeInsets.all(12),
            children: [ThemeModePicker()],
          ),
          const SizedBox(height: 12),
          const SettingsGroup(children: [GlassEffectsRow(), DensityRow()]),
          SettingsGroup(
            header: tr('Preferences'),
            children: [
              const VoiceSettingsRow(),
              SettingsRow(
                key: const ValueKey('app-language-row'),
                icon: Icons.translate_rounded,
                title: tr('Language'),
                value: appLanguageLabel(ref.watch(appLanguageProvider)),
                onTap: () => showLanguageSheet(context),
              ),
              if (!usesTouchInput(context))
                SettingsRow(
                  key: const ValueKey('keyboard-shortcuts-row'),
                  icon: Icons.keyboard_outlined,
                  title: tr('Keyboard shortcuts'),
                  onTap: () => showKeyboardShortcutsHelp(context),
                ),
            ],
          ),
          const AiSettingsGroup(),
          const NotificationSettingsGroups(),
          PrivacySettingsGroup(header: tr('Privacy & Safety')),
          AccountActionsGroup(username: value.username, header: tr('Account')),
        ],
        AsyncError(:final error) => [SettingsErrorText(error)],
        _ => const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      },
    );
  }
}
