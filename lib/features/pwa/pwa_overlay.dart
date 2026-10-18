import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/pwa/pwa_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Floats the "Update available" toast, and in an iOS Safari tab the
/// one-time "Add to Home Screen" hint, over the whole app (sign-in
/// included). Sits in `MaterialApp.builder`, above the router.
class PwaOverlayHost extends ConsumerWidget {
  const PwaOverlayHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateReady = ref.watch(
      pwaStateProvider.select((s) => s.updateReady),
    );
    final showHint = ref.watch(iosInstallHintProvider);
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showHint && !updateReady)
                  const _Floating(
                    key: ValueKey('pwa-ios-hint'),
                    child: IosInstallHintCard(),
                  ),
                if (updateReady)
                  const _Floating(
                    key: ValueKey('pwa-update-toast'),
                    child: UpdateToast(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fades and rises into place; no motion when reduced motion is asked for.
class _Floating extends StatelessWidget {
  const _Floating({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: WeCordMotion.durationOf(context, WeCordMotion.slow),
      curve: WeCordMotion.standard,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: child,
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: child,
        ),
      ),
    );
  }
}

/// "Update available — Reload": a new version has downloaded.
class UpdateToast extends ConsumerWidget {
  const UpdateToast({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        type: MaterialType.transparency,
        child: WeCordGlass(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                size: 20,
                color: c.accentText,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr('Update available'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              WeCordButton(
                key: const ValueKey('pwa-update-reload'),
                label: tr('Reload'),
                size: WeCordButtonSize.small,
                variant: WeCordButtonVariant.accent,
                onPressed: () => unawaited(
                  ref.read(pwaStateProvider.notifier).applyUpdate(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS Safari has no install button; this says where to find it.
class IosInstallHintCard extends ConsumerWidget {
  const IosInstallHintCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Material(
        type: MaterialType.transparency,
        child: WeCordGlass(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(Icons.ios_share_rounded, size: 20, color: c.accentText),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr('Install WeCord: tap Share, then Add to Home Screen.'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: c.ink),
                ),
              ),
              WeCordIconButton(
                key: const ValueKey('pwa-ios-hint-dismiss'),
                icon: Icons.close_rounded,
                tooltip: tr('Dismiss'),
                variant: WeCordButtonVariant.ghost,
                size: 32,
                iconSize: 18,
                onPressed: () => unawaited(
                  ref.read(iosInstallHintProvider.notifier).dismiss(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
