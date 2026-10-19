import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/feature_flags/feature_flags_providers.dart';
import 'package:wecord/features/pwa/pwa_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Replaces the app with [UpdateRequiredScreen] while this version is older
/// than the server allows (K4). Sits in `MaterialApp.builder`, above the
/// router, so it also covers sign-in. When the version is fine, or the
/// server has not said, it is just [child].
class AppUpdateGate extends ConsumerWidget {
  const AppUpdateGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(updateRequiredProvider)) {
      return const UpdateRequiredScreen();
    }
    return child;
  }
}

/// "Please update": this version no longer works with the server. On the web
/// the button reloads the page, which picks up the newest version; elsewhere
/// the person updates where they installed the app, and "Check again" asks
/// the server whether that is enough.
class UpdateRequiredScreen extends ConsumerStatefulWidget {
  const UpdateRequiredScreen({this.onWeb, super.key});

  /// For tests: whether to act as the web app. The build's by default.
  final bool? onWeb;

  static const refreshKey = ValueKey('update-required-refresh');
  static const checkKey = ValueKey('update-required-check');

  @override
  ConsumerState<UpdateRequiredScreen> createState() =>
      _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends ConsumerState<UpdateRequiredScreen> {
  var _checking = false;

  Future<void> _checkAgain() async {
    setState(() => _checking = true);
    try {
      await ref.read(featureFlagsProvider.notifier).refresh();
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final web = widget.onWeb ?? kIsWeb;
    final version = ref.watch(appVersionProvider);
    final minimum = ref.watch(minimumVersionProvider);
    return Scaffold(
      key: const ValueKey('update-required-screen'),
      backgroundColor: c.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(WeCordSpace.gutter + 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SettingsIconTile(
                      icon: Icons.system_update_alt_rounded,
                      tone: SettingsTone.accent,
                      size: 64,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    header: true,
                    child: Text(
                      tr('Please update WeCord'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: c.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    web
                        ? tr(
                            'A newer version is ready. Refresh to get it and '
                            'carry on.',
                          )
                        : tr(
                            'This version is too old to keep working. Update '
                            'WeCord where you installed it, then open it '
                            'again.',
                          ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: c.muted,
                      height: 1.45,
                    ),
                  ),
                  if (minimum.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      tr('You have {version}. You need {minimum} or newer.', {
                        'version': version,
                        'minimum': minimum,
                      }),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: c.subtle),
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (web)
                    WeCordButton(
                      key: UpdateRequiredScreen.refreshKey,
                      label: tr('Refresh'),
                      expand: true,
                      size: WeCordButtonSize.large,
                      variant: WeCordButtonVariant.primary,
                      onPressed: () => unawaited(
                        ref.read(pwaStateProvider.notifier).applyUpdate(),
                      ),
                    ),
                  if (!web)
                    WeCordButton(
                      key: UpdateRequiredScreen.checkKey,
                      label: _checking ? tr('Checking...') : tr('Check again'),
                      expand: true,
                      size: WeCordButtonSize.large,
                      variant: WeCordButtonVariant.primary,
                      onPressed: _checking ? null : _checkAgain,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
