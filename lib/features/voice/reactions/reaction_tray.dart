import 'package:flutter/material.dart';
import 'package:wecord/features/voice/reactions/reaction_message.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The emoji a call offers, in a glass pill above the control bar. Tapping
/// one calls [onPick]; its answer says whether it was sent (false when the
/// rate limit held it back).
class ReactionTray extends StatelessWidget {
  const ReactionTray({required this.onPick, super.key});

  final Future<bool> Function(String emoji) onPick;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: tr('Reactions'),
      child: WeCordGlass(
        key: const ValueKey('voice-reaction-tray'),
        elevation: GlassElevation.menu,
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Wrap(
          alignment: WrapAlignment.center,
          children: [
            for (final emoji in callReactionEmojis)
              _EmojiButton(emoji: emoji, onPick: onPick),
          ],
        ),
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({required this.emoji, required this.onPick});

  final String emoji;
  final Future<bool> Function(String emoji) onPick;

  @override
  Widget build(BuildContext context) {
    return WeCordPressable(
      key: ValueKey('voice-reaction-$emoji'),
      semanticLabel: tr('Send {emoji}', {'emoji': emoji}),
      tooltip: tr('Send {emoji}', {'emoji': emoji}),
      excludeSemantics: true,
      shape: const CircleBorder(),
      pressedScale: 0.86,
      onPressed: () => onPick(emoji),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hovered
                ? context.tokens.colors.ink.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 24, height: 1)),
        );
      },
    );
  }
}
