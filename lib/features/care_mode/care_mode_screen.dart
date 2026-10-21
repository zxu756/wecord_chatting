import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the Care mode page (the options behind the switch).
Future<void> openCareModeSettings(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (context) => const CareModeScreen()),
  );
}

/// Settings → Appearance → Care mode: the one switch for the elders' mode,
/// and, once it is on, a row to its options. Turning the switch on or off
/// changes sizes only; nothing on the page behind is lost.
class CareModeSettingsGroup extends ConsumerWidget {
  const CareModeSettingsGroup({this.showIcon = true, super.key});

  final bool showIcon;

  static const switchKey = ValueKey('care-mode-switch');
  static const optionsKey = ValueKey('care-mode-options-row');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(careModeProvider.select((s) => s.enabled));
    return SettingsGroup(
      children: [
        SettingsRow.toggle(
          key: switchKey,
          icon: showIcon ? Icons.elderly_rounded : null,
          title: tr('Care mode'),
          subtitle: tr(
            'Bigger text and buttons, a simpler home, and messages read aloud',
          ),
          value: enabled,
          onChanged: (value) =>
              unawaited(ref.read(careModeProvider.notifier).setEnabled(value)),
        ),
        if (enabled)
          SettingsRow(
            key: optionsKey,
            icon: showIcon ? Icons.tune_rounded : null,
            title: tr('Care mode options'),
            onTap: () => unawaited(openCareModeSettings(context)),
          ),
      ],
    );
  }
}

/// The Care mode page: the switch and its three options.
class CareModeScreen extends ConsumerWidget {
  const CareModeScreen({super.key});

  static const simpleHomeKey = ValueKey('care-mode-simple-home');
  static const readAloudKey = ValueKey('care-mode-read-aloud');
  static const highContrastKey = ValueKey('care-mode-high-contrast');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(careModeProvider);
    final controller = ref.read(careModeProvider.notifier);
    return SettingsPage(
      key: const ValueKey('care-mode-screen'),
      title: tr('Care mode'),
      children: [
        const SizedBox(height: 12),
        SettingsGroup(
          footer: tr(
            'Care mode is for this device only. It does not change anything for the people you talk to, and turning it off puts everything back.',
          ),
          children: [
            SettingsRow.toggle(
              key: CareModeSettingsGroup.switchKey,
              icon: Icons.elderly_rounded,
              title: tr('Care mode'),
              subtitle: tr(
                'Bigger text and buttons, a simpler home, and messages read aloud',
              ),
              value: settings.enabled,
              onChanged: (value) => unawaited(controller.setEnabled(value)),
            ),
          ],
        ),
        SettingsGroup(
          header: tr('Options'),
          footer: settings.enabled
              ? null
              : tr('These apply while Care mode is on.'),
          children: [
            SettingsRow.toggle(
              key: simpleHomeKey,
              icon: Icons.home_outlined,
              title: tr('Simple home'),
              subtitle: tr(
                'Only Messages, Friends and Moments, and fewer buttons in chats',
              ),
              value: settings.simpleHome,
              onChanged: (value) => unawaited(controller.setSimpleHome(value)),
            ),
            SettingsRow.toggle(
              key: readAloudKey,
              icon: Icons.volume_up_outlined,
              title: tr('Read messages aloud'),
              subtitle: tr(
                'Press and hold a text message, then choose Read aloud',
              ),
              value: settings.readAloud,
              onChanged: (value) => unawaited(controller.setReadAloud(value)),
            ),
            SettingsRow.toggle(
              key: highContrastKey,
              icon: Icons.contrast_rounded,
              title: tr('Stronger colors'),
              subtitle: tr('Darker text and clearer lines, easier to read'),
              value: settings.highContrast,
              onChanged: (value) =>
                  unawaited(controller.setHighContrast(value)),
            ),
          ],
        ),
      ],
    );
  }
}
