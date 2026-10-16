import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The rewrite shortcut (handled by the message field, see
/// `ComposerShortcut.rewriteWithAi`) as the user's platform writes it.
String aiRewriteShortcutLabel() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.iOS => '⌘⇧E',
    _ => 'Ctrl+Shift+E',
  };
}

/// The sparkle button in the composer that opens the rewrite sheet. Gone
/// when AI isn't available (not set up, or switched off).
class AiComposerButton extends ConsumerWidget {
  const AiComposerButton({
    required this.size,
    required this.onPressed,
    this.circleId,
    super.key,
  });

  final double size;
  final VoidCallback? onPressed;
  final String? circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(aiAvailableProvider(circleId))) {
      return const SizedBox.shrink();
    }
    final shortcut = switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => ' (${aiRewriteShortcutLabel()})',
      _ => '',
    };
    return WeCordIconButton(
      key: const ValueKey('composer-ai-button'),
      tooltip: '${tr('Rewrite with AI')}$shortcut',
      icon: Icons.auto_awesome_rounded,
      size: size,
      iconSize: 20,
      variant: WeCordButtonVariant.ghost,
      onPressed: onPressed,
    );
  }
}
