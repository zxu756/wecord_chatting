import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/pwa/pwa_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Settings row "Install WeCord": the browser's install dialog on desktop
/// Chrome and Edge, a Share-menu hint on iOS Safari. Nothing once WeCord
/// runs as an installed app, or where the browser offers no way to install.
class InstallAppTile extends ConsumerWidget {
  const InstallAppTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pwaStateProvider);
    if (state.standalone || !(state.canInstall || state.iosSafari)) {
      return const SizedBox.shrink();
    }
    if (state.canInstall) {
      return SettingsRow(
        key: const ValueKey('install-app'),
        icon: Icons.install_desktop_rounded,
        title: tr('Install WeCord'),
        subtitle: tr('Open WeCord in its own window, with an icon of its own.'),
        onTap: () => unawaited(ref.read(pwaStateProvider.notifier).install()),
      );
    }
    return SettingsRow(
      key: const ValueKey('install-app-ios'),
      icon: Icons.ios_share_rounded,
      title: tr('Install WeCord'),
      subtitle: tr('Tap Share, then Add to Home Screen.'),
    );
  }
}

/// [InstallAppTile] in a group of its own; nothing at all when WeCord can't
/// be installed here (or already is).
class InstallAppGroup extends ConsumerWidget {
  const InstallAppGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pwaStateProvider);
    if (state.standalone || !(state.canInstall || state.iosSafari)) {
      return const SizedBox.shrink();
    }
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: SettingsGroup(children: [InstallAppTile()]),
    );
  }
}
