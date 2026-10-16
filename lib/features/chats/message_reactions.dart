import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/custom_emoji.dart';
import 'package:wecord/features/chats/sheet_rows.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

const quickReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🎉'];

// Space-separated so the built-in picker stays compact; split when rendered.
List<(String, String)> get _pickerEmojiGroups => [
  (
    tr('Smileys'),
    '😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 '
        '😉 😊 😇 🥰 😍 🤩 😘 😋 😛 😜 '
        '🤪 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 '
        '😏 😒 🙄 😬 😌 😔 😪 😴 😷 🤒 '
        '🥵 🥶 🥴 😵 🤯 🥳 😎 🤓 🧐 😕 '
        '😟 🙁 😮 😯 😲 😳 🥺 😦 😧 😨 '
        '😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 '
        '😫 🥱 😤 😡 😠 🤬 😈 💀 🤡 👻',
  ),
  (
    tr('Gestures'),
    '👍 👎 👌 🤌 ✌️ 🤞 🤟 🤘 🤙 👈 '
        '👉 👆 👇 ☝️ 👋 🤚 ✋ 🖖 👏 🙌 '
        '👐 🤲 🤝 🙏 ✍️ 💪 🫡 🫶 👀 🧠',
  ),
  (
    tr('Hearts'),
    '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 '
        '❣️ 💕 💞 💓 💗 💖 💘 💝 💯 💢',
  ),
  (
    tr('Nature & food'),
    '🐶 🐱 🐭 🐰 🦊 🐻 🐼 🐨 🐯 🦁 '
        '🐸 🐵 🐔 🐧 🐦 🦄 🐝 🦋 🐢 🐙 '
        '🌸 🌹 🌻 🌈 ☀️ 🌙 ⭐ 🔥 ❄️ 🌊 '
        '🍎 🍓 🍉 🍑 🍕 🍔 🍟 🍜 🍣 🍰 '
        '🍪 🍫 🍿 ☕ 🍵 🍺 🍻 🥂 🧋 🍦',
  ),
  (
    tr('Activities & objects'),
    '🎉 🎊 🎈 🎁 🏆 🥇 ⚽ 🏀 🎮 🎲 '
        '🎵 🎶 🎤 🎧 🎬 📷 💡 📌 📎 ✏️ '
        '📚 💻 📱 ⏰ 💰 💎 🔔 🚀 ✈️ 🏠',
  ),
  (
    tr('Symbols'),
    '✅ ❌ ⭕ ❗ ❓ ‼️ ⁉️ ⚠️ 🚫 💤 '
        '✨ 💫 🆗 🆒 🆕 🔝 ➕ ➖ 💬 👑',
  ),
];

/// Picks an emoji: a unicode one, or with [includeCustom] the current
/// user's custom emoji as `custom:<uuid>` ([circleId]'s under "This
/// circle", the rest under "Your emoji").
Future<String?> showEmojiReactionPicker(
  BuildContext context, {
  String? title,
  bool includeCustom = false,
  String? circleId,
}) {
  return showWeCordSheet<String>(
    context,
    title: title ?? tr('Add reaction'),
    builder: (sheetContext, _) =>
        EmojiReactionPicker(includeCustom: includeCustom, circleId: circleId),
  );
}

/// The emoji grid of the reaction picker sheet: the user's custom emoji
/// (with [includeCustom]) and then the unicode groups. Tapping one pops
/// the sheet with it.
class EmojiReactionPicker extends ConsumerWidget {
  const EmojiReactionPicker({
    this.includeCustom = false,
    this.circleId,
    super.key,
  });

  final bool includeCustom;
  final String? circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = includeCustom
        ? [
            for (final emoji
                in ref.watch(usableEmojisProvider).value ??
                    const <CircleEmoji>[])
              if (!emoji.isSticker) emoji,
          ]
        : const <CircleEmoji>[];
    final customGroups = [
      (
        label: tr('This circle'),
        emojis: [
          for (final emoji in custom)
            if (emoji.circleId == circleId) emoji,
        ],
      ),
      (
        label: tr('Your emoji'),
        emojis: [
          for (final emoji in custom)
            if (emoji.circleId != circleId) emoji,
        ],
      ),
    ];
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.min(480, MediaQuery.sizeOf(context).height * 0.62),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            for (final group in customGroups)
              if (group.emojis.isNotEmpty) ...[
                _PickerSectionHeader(group.label),
                Wrap(
                  children: [
                    for (final emoji in group.emojis)
                      _CustomEmojiButton(
                        emoji: emoji,
                        onTap: () =>
                            Navigator.of(context).pop(emoji.reactionValue),
                      ),
                  ],
                ),
              ],
            for (final (label, emojis) in _pickerEmojiGroups) ...[
              _PickerSectionHeader(label),
              Wrap(
                children: [
                  for (final emoji in emojis.split(' '))
                    _EmojiButton(
                      emoji: emoji,
                      onTap: () => Navigator.of(context).pop(emoji),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A group's name above its emoji: 12/700 in the subtle color.
class _PickerSectionHeader extends StatelessWidget {
  const _PickerSectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: context.tokens.colors.subtle,
        ),
      ),
    );
  }
}

/// The quick reactions over a long-pressed message: a glass pill of
/// emoji (the ones already picked tinted) and a button for the full
/// picker. [compact] is the smaller row at the top of a desktop context
/// menu, on the menu's own glass.
class QuickReactionBar extends StatelessWidget {
  const QuickReactionBar({
    required this.reactedEmojis,
    required this.onSelect,
    required this.onMore,
    this.compact = false,
    super.key,
  });

  final Set<String> reactedEmojis;
  final ValueChanged<String> onSelect;
  final VoidCallback onMore;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Seven finger-sized buttons share the width of a narrow phone: 48 where
    // there is room (Material's touch target), a little less on 360 wide.
    final size = compact
        ? 32.0
        : ((MediaQuery.sizeOf(context).width - 44) /
                  (quickReactionEmojis.length + 1))
              .clamp(40.0, 48.0);
    final row = Row(
      mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: compact
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.start,
      children: [
        for (final emoji in quickReactionEmojis)
          _QuickEmojiButton(
            emoji: emoji,
            size: size,
            isSelected: reactedEmojis.contains(emoji),
            onTap: () {
              WeCordHaptics.selection();
              onSelect(emoji);
            },
          ),
        WeCordPressable(
          onPressed: onMore,
          tooltip: tr('More reactions'),
          semanticLabel: tr('More reactions'),
          shape: const CircleBorder(),
          minTapSize: Size.zero,
          pressedScale: 0.9,
          builder: (context, states) {
            final c = context.tokens.colors;
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: states.contains(WidgetState.hovered)
                    ? c.raisedStrong
                    : c.raised,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_rounded, size: size * 0.5, color: c.muted),
            );
          },
        ),
      ],
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
        child: row,
      );
    }
    return WeCordGlass(
      key: const ValueKey('quick-reaction-bar'),
      elevation: GlassElevation.menu,
      borderRadius: BorderRadius.circular(30),
      padding: const EdgeInsets.all(6),
      child: row,
    );
  }
}

class _QuickEmojiButton extends StatelessWidget {
  const _QuickEmojiButton({
    required this.emoji,
    required this.size,
    required this.isSelected,
    required this.onTap,
  });

  final String emoji;
  final double size;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onTap,
      selected: isSelected,
      semanticLabel: tr('React with {emoji}', {'emoji': emoji}),
      excludeSemantics: true,
      pressedScale: 0.85,
      shape: const CircleBorder(),
      minTapSize: Size.zero,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? c.accentSoft
                : hovered
                ? c.ink.withValues(alpha: 0.06)
                : c.ink.withValues(alpha: 0),
          ),
          // The emoji is a picture in a fixed button: it keeps its size
          // when the text size grows.
          child: Text(
            emoji,
            textScaler: TextScaler.noScaling,
            style: TextStyle(fontSize: size * 0.56),
          ),
        );
      },
    );
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _QuickEmojiButton(
      emoji: emoji,
      size: 48,
      isSelected: false,
      onTap: onTap,
    );
  }
}

class _CustomEmojiButton extends StatelessWidget {
  const _CustomEmojiButton({required this.emoji, required this.onTap});

  final CircleEmoji emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      key: ValueKey('custom-emoji-option-${emoji.id}'),
      onPressed: onTap,
      tooltip: ':${emoji.name}:',
      pressedScale: 0.85,
      shape: const CircleBorder(),
      builder: (context, states) => AnimatedContainer(
        duration: WeCordMotion.quick,
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.ink.withValues(
            alpha: states.contains(WidgetState.hovered) ? 0.06 : 0,
          ),
        ),
        child: CustomEmojiImage(
          storagePath: emoji.storagePath,
          size: 28,
          semanticLabel: ':${emoji.name}:',
          fallback: Text(
            ':${emoji.name}:',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10),
          ),
        ),
      ),
    );
  }
}

class MessageReactionChips extends StatelessWidget {
  const MessageReactionChips({
    required this.reactions,
    required this.onToggle,
    required this.onShowReactors,
    super.key,
  });

  final List<MessageReaction> reactions;
  final ValueChanged<String> onToggle;
  final ValueChanged<MessageReaction> onShowReactors;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      // Touch chips carry their own spacing in their taller hit area.
      runSpacing: usesTouchInput(context) ? 0 : 4,
      children: [
        for (final reaction in reactions)
          _ReactionChip(
            key: ValueKey('reaction-chip-${reaction.emoji}'),
            reaction: reaction,
            onTap: () => onToggle(reaction.emoji),
            onLongPress: () => onShowReactors(reaction),
          ),
      ],
    );
  }
}

class _ReactionChip extends ConsumerWidget {
  const _ReactionChip({
    required this.reaction,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final MessageReaction reaction;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usable = ref.watch(usableEmojisByIdProvider);
    final label = reactionLabel(reaction, usable);
    final customEmoji = switch (reaction.customEmojiId) {
      final id? => usable[id],
      null => null,
    };
    final Widget glyph = customEmoji != null
        ? CustomEmojiImage(
            storagePath: customEmoji.storagePath,
            size: 18,
            semanticLabel: label,
            fallback: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          )
        : reaction.customEmojiId != null
        // Names can be long; the chip stays a chip.
        ? ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          )
        : Text(reaction.emoji, style: const TextStyle(fontSize: 14));
    final isMine = reaction.reactedByMe;
    final c = context.tokens.colors;
    final touch = usesTouchInput(context);
    return WeCordPressable(
      onPressed: onTap,
      onLongPress: onLongPress,
      selected: isMine,
      semanticLabel: '$label ${reaction.count}',
      excludeSemantics: true,
      pressedScale: 0.92,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        final chip = AnimatedContainer(
          key: const ValueKey('reaction-body'),
          duration: WeCordMotion.quick,
          curve: WeCordMotion.standard,
          height: 26,
          padding: EdgeInsets.symmetric(horizontal: isMine ? 7.5 : 9),
          decoration: BoxDecoration(
            color: isMine
                ? c.panel
                : hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.05), c.raised)
                : c.raised,
            borderRadius: BorderRadius.circular(13),
            border: isMine ? Border.all(color: c.accent, width: 1.5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              glyph,
              const SizedBox(width: 5),
              Text(
                '${reaction.count}',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.1,
                  color: isMine ? c.accentText : c.ink,
                  fontWeight: isMine ? FontWeight.w700 : FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
        // The chip stays compact, but taps just above or below it still
        // count on touch screens, so the target is finger-sized.
        return touch
            ? ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: minTouchTargetSize,
                  minHeight: minTouchTargetSize,
                ),
                child: Center(widthFactor: 1, child: chip),
              )
            : chip;
      },
    );
  }
}

class MessageReactorsSheet extends ConsumerStatefulWidget {
  const MessageReactorsSheet({
    required this.messageId,
    required this.emoji,
    super.key,
  });

  final String messageId;
  final String emoji;

  @override
  ConsumerState<MessageReactorsSheet> createState() =>
      _MessageReactorsSheetState();
}

class _MessageReactorsSheetState extends ConsumerState<MessageReactorsSheet> {
  late final Future<List<Profile>> _reactors = ref
      .read(chatsRepositoryProvider)
      .listMessageReactors(messageId: widget.messageId, emoji: widget.emoji);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.min(460, MediaQuery.sizeOf(context).height * 0.6),
        ),
        child: FutureBuilder<List<Profile>>(
          future: _reactors,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SheetNote(
                text: tr('Could not load reactions.'),
                error: true,
              );
            }
            final reactors = snapshot.data;
            if (reactors == null) {
              return const SheetSpinner();
            }
            if (reactors.isEmpty) {
              return SheetNote(text: tr('No one has reacted with this yet.'));
            }
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              children: [
                for (final profile in reactors)
                  SheetListRow(
                    key: ValueKey('reactor-${profile.id}'),
                    leading: ProfileAvatar(
                      name: profile.displayLabel,
                      avatarUrl: profile.avatarUrl,
                      size: 40,
                    ),
                    title: profile.displayLabel,
                    subtitle: '@${profile.username}',
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
