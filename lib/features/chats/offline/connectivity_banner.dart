import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/offline/connectivity.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A pill saying the app is offline (messages wait in the outbox) or
/// reconnecting; nothing while online. It slides in and out.
class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({this.padding = EdgeInsets.zero, super.key});

  /// Around the pill, when it shows.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(networkStatusProvider);
    final pill = switch (status) {
      NetworkStatus.online => null,
      NetworkStatus.offline => _StatusPill(
        key: const ValueKey('connectivity-offline'),
        icon: Icons.cloud_off_rounded,
        label: tr('Offline — messages will send when you reconnect'),
        warning: true,
      ),
      NetworkStatus.reconnecting => _StatusPill(
        key: const ValueKey('connectivity-reconnecting'),
        label: tr('Reconnecting…'),
        warning: false,
      ),
    };
    return AnimatedSize(
      duration: WeCordMotion.durationOf(context, WeCordMotion.base),
      curve: WeCordMotion.standard,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: WeCordMotion.durationOf(context, WeCordMotion.base),
        switchInCurve: WeCordMotion.standard,
        switchOutCurve: WeCordMotion.standard,
        child: pill == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                key: ValueKey(status),
                padding: padding,
                child: Center(child: pill),
              ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.warning,
    this.icon,
    super.key,
  });

  final String label;
  final IconData? icon;

  /// Offline reads as a warning; reconnecting as a quiet note.
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final foreground = warning ? c.warningText : c.muted;
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: warning ? c.warningSoft : c.raised,
            borderRadius: BorderRadius.circular(WeCordRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon case final icon?)
                Icon(icon, size: 16, color: foreground)
              else
                SizedBox.square(
                  dimension: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: foreground,
                  ),
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
