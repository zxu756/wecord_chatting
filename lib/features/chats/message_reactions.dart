import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

const quickReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🎉'];

// Space-separated so the built-in picker stays compact; split when rendered.
const _pickerEmojiGroups = <(String, String)>[
  (
    'Smileys',
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
    'Gestures',
    '👍 👎 👌 🤌 ✌️ 🤞 🤟 🤘 🤙 👈 '
        '👉 👆 👇 ☝️ 👋 🤚 ✋ 🖖 👏 🙌 '
        '👐 🤲 🤝 🙏 ✍️ 💪 🫡 🫶 👀 🧠',
  ),
  (
    'Hearts',
    '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 '
        '❣️ 💕 💞 💓 💗 💖 💘 💝 💯 💢',
  ),
  (
    'Nature & food',
    '🐶 🐱 🐭 🐰 🦊 🐻 🐼 🐨 🐯 🦁 '
        '🐸 🐵 🐔 🐧 🐦 🦄 🐝 🦋 🐢 🐙 '
        '🌸 🌹 🌻 🌈 ☀️ 🌙 ⭐ 🔥 ❄️ 🌊 '
        '🍎 🍓 🍉 🍑 🍕 🍔 🍟 🍜 🍣 🍰 '
        '🍪 🍫 🍿 ☕ 🍵 🍺 🍻 🥂 🧋 🍦',
  ),
  (
    'Activities & objects',
    '🎉 🎊 🎈 🎁 🏆 🥇 ⚽ 🏀 🎮 🎲 '
        '🎵 🎶 🎤 🎧 🎬 📷 💡 📌 📎 ✏️ '
        '📚 💻 📱 ⏰ 💰 💎 🔔 🚀 ✈️ 🏠',
  ),
  (
    'Symbols',
    '✅ ❌ ⭕ ❗ ❓ ‼️ ⁉️ ⚠️ 🚫 💤 '
        '✨ 💫 🆗 🆒 🆕 🔝 ➕ ➖ 💬 👑',
  ),
];

Future<String?> showEmojiReactionPicker(
  BuildContext context, {
  String title = 'Add reaction',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => EmojiReactionPicker(title: title),
  );
}

class EmojiReactionPicker extends StatelessWidget {
  const EmojiReactionPicker({this.title = 'Add reaction', super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  for (final (label, emojis) in _pickerEmojiGroups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                      child: Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
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
          ],
        ),
      ),
    );
  }
}

class QuickReactionBar extends StatelessWidget {
  const QuickReactionBar({
    required this.reactedEmojis,
    required this.onSelect,
    required this.onMore,
    super.key,
  });

  final Set<String> reactedEmojis;
  final ValueChanged<String> onSelect;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final emoji in quickReactionEmojis)
            _EmojiButton(
              emoji: emoji,
              isSelected: reactedEmojis.contains(emoji),
              onTap: () => onSelect(emoji),
            ),
          IconButton(
            tooltip: 'More reactions',
            onPressed: onMore,
            icon: const Icon(Icons.add_reaction_outlined),
          ),
        ],
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({
    required this.emoji,
    required this.onTap,
    this.isSelected = false,
  });

  final String emoji;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 24)),
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
      spacing: 4,
      runSpacing: 4,
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

class _ReactionChip extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMine = reaction.reactedByMe;
    final foreground = isMine
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: isMine,
      label: '${reaction.emoji} ${reaction.count}',
      child: Material(
        color: isMine
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        shape: StadiumBorder(
          side: BorderSide(
            color: isMine ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(reaction.emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 4),
                Text(
                  '${reaction.count}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: isMine ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Reacted with ${widget.emoji}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: FutureBuilder<List<Profile>>(
                future: _reactors,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Could not load reactions.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    );
                  }
                  final reactors = snapshot.data;
                  if (reactors == null) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (reactors.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No one has reacted with this yet.'),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      for (final profile in reactors)
                        ListTile(
                          leading: _ReactorAvatar(profile: profile),
                          title: Text(profile.displayLabel),
                          subtitle: Text('@${profile.username}'),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactorAvatar extends ConsumerWidget {
  const _ReactorAvatar({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayUrl = ref
        .watch(avatarDisplayUrlProvider(profile.avatarUrl))
        .valueOrNull;
    final image = displayUrl == null ? null : NetworkImage(displayUrl);
    final label = profile.displayLabel.trim();
    return CircleAvatar(
      backgroundImage: image,
      onBackgroundImageError: image == null ? null : (_, _) {},
      child: image == null
          ? Text(label.isEmpty ? '?' : label.characters.first.toUpperCase())
          : null,
    );
  }
}
