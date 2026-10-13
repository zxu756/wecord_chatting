import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/shared/api/signed_url_refresh.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/message.dart';

/// Inline custom emoji in message text.
const customEmojiInlineSize = 22.0;

/// Custom emoji in a message of nothing but emoji.
const customEmojiJumboSize = 48.0;

const stickerSize = 160.0;

/// An emoji or sticker image from the `circle-emojis` bucket, [size] square.
/// Shows [fallback] while there is no image (loading, not a member of its
/// circle, deleted).
class CustomEmojiImage extends ConsumerWidget {
  const CustomEmojiImage({
    required this.storagePath,
    required this.size,
    required this.fallback,
    this.semanticLabel,
    super.key,
  });

  final String storagePath;
  final double size;
  final Widget fallback;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(circleEmojiImageProvider(storagePath));
    return switch (image) {
      AsyncData(value: final provider?) => Image(
        image: provider,
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: semanticLabel,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          // The cached signed URL may have expired: sign it again.
          refreshSignedUrlSoon('emoji:$storagePath', () {
            try {
              ref.invalidate(circleEmojiImageProvider(storagePath));
            } catch (_) {
              // The widget is gone; the next one to show it signs it.
            }
          });
          return fallback;
        },
      ),
      AsyncLoading() => SizedBox.square(dimension: size),
      _ => fallback,
    };
  }
}

/// How a reaction reads in text: the emoji itself, or `:name:` for custom
/// emoji.
String reactionLabel(MessageReaction reaction, Map<String, CircleEmoji> byId) {
  final id = reaction.customEmojiId;
  if (id == null) {
    return reaction.emoji;
  }
  final name = byId[id]?.name ?? reaction.customName;
  return name == null ? ':emoji:' : ':$name:';
}

/// A `:` and at least two name characters being typed right before the
/// cursor.
final _emojiQueryPattern = RegExp(r'(?:^|\s):([a-zA-Z0-9_]{2,32})$');

/// The lowercased name typed after a `:` right before the cursor of
/// [value], or null when the cursor is not in one.
String? emojiQueryAt(TextEditingValue value) {
  return _emojiMatch(value)?.group(1)?.toLowerCase();
}

RegExpMatch? _emojiMatch(TextEditingValue value) {
  final text = value.text;
  final selection = value.selection;
  final cursor = selection.isValid ? selection.baseOffset : text.length;
  final safeCursor = cursor.clamp(0, text.length);
  return _emojiQueryPattern.firstMatch(text.substring(0, safeCursor));
}

/// Up to [limit] custom emoji (not stickers) whose name contains [query]:
/// names starting with it first, then [circleId]'s own.
List<CircleEmoji> customEmojiCandidates(
  List<CircleEmoji> emojis,
  String query, {
  String? circleId,
  int limit = 8,
}) {
  final matches = [
    for (final emoji in emojis)
      if (!emoji.isSticker && emoji.name.contains(query)) emoji,
  ];
  int rank(CircleEmoji emoji) {
    return (emoji.name.startsWith(query) ? 0 : 2) +
        (emoji.circleId == circleId ? 0 : 1);
  }

  matches.sort((left, right) {
    final byRank = rank(left).compareTo(rank(right));
    return byRank != 0 ? byRank : left.name.compareTo(right.name);
  });
  return matches.take(limit).toList(growable: false);
}

final _customEmojiTokenPattern = RegExp(
  r'<:([a-z0-9_]{2,32}):([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})>',
);
final _shortcodePattern = RegExp(r':([a-z0-9_]{2,32}):');

/// The custom emoji picked while writing a message. The composer shows them
/// as `:name:`; [encode] turns them (and other `:name:` of usable emoji)
/// into `<:name:id>` tokens when the message is sent.
class CustomEmojiDraft {
  final _picked = <String, CircleEmoji>{};

  /// Replaces the `:name` being typed in [controller] with `:emoji: `.
  /// Returns false when the cursor is not in one.
  bool insert(TextEditingController controller, CircleEmoji emoji) {
    final text = controller.text;
    final match = _emojiMatch(controller.value);
    if (match == null) {
      return false;
    }
    final selection = controller.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    final safeCursor = cursor.clamp(0, text.length);
    final prefix = text.substring(0, safeCursor);
    final tokenStart = match.start + (prefix[match.start] == ':' ? 0 : 1);
    final shortcode = ':${emoji.name}: ';
    controller.value = TextEditingValue(
      text: text.replaceRange(tokenStart, safeCursor, shortcode),
      selection: TextSelection.collapsed(offset: tokenStart + shortcode.length),
    );
    _picked[emoji.name] = emoji;
    return true;
  }

  /// [body] with `<:name:id>` tokens of known emoji shown as `:name:` for
  /// editing; they turn back into tokens on save.
  String decode(String body, Map<String, CircleEmoji> usableById) {
    return body.replaceAllMapped(_customEmojiTokenPattern, (match) {
      final emoji = usableById[match.group(2)];
      if (emoji == null || emoji.name != match.group(1)) {
        return match.group(0)!;
      }
      _picked[emoji.name] = emoji;
      return ':${emoji.name}:';
    });
  }

  /// [text] with every `:name:` outside code that names a picked emoji, or
  /// else one of [usable] (preferring [circleId]'s), written as a token.
  String encode(
    String text, {
    required List<CircleEmoji> usable,
    String? circleId,
  }) {
    CircleEmoji? resolve(String name) {
      final picked = _picked[name];
      if (picked != null) {
        return picked;
      }
      CircleEmoji? found;
      for (final emoji in usable) {
        if (emoji.isSticker || emoji.name != name) {
          continue;
        }
        if (emoji.circleId == circleId) {
          return emoji;
        }
        found ??= emoji;
      }
      return found;
    }

    return encodeCustomEmojiShortcodes(text, resolve);
  }

  void clear() => _picked.clear();
}

/// [text] with each `:name:` outside code spans, code blocks and existing
/// tokens replaced by `<:name:id>` when [resolve] knows the name.
String encodeCustomEmojiShortcodes(
  String text,
  CircleEmoji? Function(String name) resolve,
) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < text.length) {
    final char = text[index];
    if (char == r'\' && index + 1 < text.length) {
      buffer.write(text.substring(index, index + 2));
      index += 2;
      continue;
    }
    if (char == '`') {
      var run = 0;
      while (index + run < text.length && text[index + run] == '`') {
        run++;
      }
      final fence = '`' * run;
      final close = text.indexOf(fence, index + run);
      final end = close == -1 ? index + run : close + run;
      buffer.write(text.substring(index, end));
      index = end;
      continue;
    }
    if (char == '<') {
      final token = _customEmojiTokenPattern.matchAsPrefix(text, index);
      if (token != null) {
        buffer.write(token.group(0));
        index = token.end;
        continue;
      }
    }
    if (char == ':') {
      final match = _shortcodePattern.matchAsPrefix(text, index);
      final emoji = match == null ? null : resolve(match.group(1)!);
      if (match != null && emoji != null) {
        buffer.write(emoji.token);
        index = match.end;
        continue;
      }
    }
    buffer.write(char);
    index++;
  }
  return buffer.toString();
}

/// The custom emoji suggested above the composer while `:name` is typed.
class CustomEmojiCandidateList extends StatelessWidget {
  const CustomEmojiCandidateList({
    required this.candidates,
    required this.onSelect,
    required this.maxHeight,
    super.key,
  });

  final List<CircleEmoji> candidates;
  final ValueChanged<CircleEmoji> onSelect;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('custom-emoji-candidates'),
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final emoji in candidates)
              ListTile(
                key: ValueKey('custom-emoji-candidate-${emoji.id}'),
                dense: true,
                leading: SizedBox.square(
                  dimension: 32,
                  child: Center(
                    child: CustomEmojiImage(
                      storagePath: emoji.storagePath,
                      size: 28,
                      fallback: const Icon(Icons.emoji_emotions_outlined),
                    ),
                  ),
                ),
                title: Text(':${emoji.name}:'),
                subtitle: emoji.circleName == null
                    ? null
                    : Text(
                        emoji.circleName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () => onSelect(emoji),
              ),
          ],
        ),
      ),
    );
  }
}

/// Picks one of the current user's stickers: [circleId]'s first, then the
/// other circles'. Returns null when dismissed.
Future<CircleEmoji?> showStickerPicker(
  BuildContext context, {
  String? circleId,
}) {
  return showModalBottomSheet<CircleEmoji>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => StickerPicker(circleId: circleId),
  );
}

class StickerPicker extends ConsumerWidget {
  const StickerPicker({this.circleId, super.key});

  final String? circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final usable = ref.watch(usableEmojisProvider);
    final stickers = [
      for (final emoji in usable.valueOrNull ?? const <CircleEmoji>[])
        if (emoji.isSticker) emoji,
    ];
    final groups = groupEmojisByCircle(stickers, circleId: circleId);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Stickers', style: theme.textTheme.titleLarge),
            ),
            if (usable.isLoading && stickers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (stickers.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text(
                  'No stickers yet. Circles add them under Emoji & stickers.',
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  children: [
                    for (final group in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                        child: Text(
                          group.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final sticker in group.emojis)
                            Tooltip(
                              message: sticker.name,
                              child: InkWell(
                                key: ValueKey('sticker-option-${sticker.id}'),
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => Navigator.of(context).pop(sticker),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: CustomEmojiImage(
                                    storagePath: sticker.storagePath,
                                    size: 88,
                                    fallback: SizedBox.square(
                                      dimension: 88,
                                      child: Center(
                                        child: Text(
                                          sticker.name,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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

typedef CircleEmojiGroup = ({String label, List<CircleEmoji> emojis});

/// [emojis] by circle: [circleId]'s as "This circle" first, then the
/// others under their circle's name.
List<CircleEmojiGroup> groupEmojisByCircle(
  List<CircleEmoji> emojis, {
  String? circleId,
}) {
  final byCircle = <String, List<CircleEmoji>>{};
  for (final emoji in emojis) {
    byCircle.putIfAbsent(emoji.circleId, () => []).add(emoji);
  }
  final groups = <CircleEmojiGroup>[];
  final own = byCircle.remove(circleId);
  if (own != null) {
    groups.add((label: 'This circle', emojis: own));
  }
  final others = byCircle.values.toList()
    ..sort(
      (left, right) => (left.first.circleName ?? '').toLowerCase().compareTo(
        (right.first.circleName ?? '').toLowerCase(),
      ),
    );
  for (final group in others) {
    groups.add((
      label: group.first.circleName ?? 'Other circle',
      emojis: group,
    ));
  }
  return groups;
}

/// A sticker message: the sticker for members of its circle, otherwise a
/// placeholder with its name.
class StickerMessageContent extends ConsumerWidget {
  const StickerMessageContent({
    required this.attachment,
    required this.textColor,
    super.key,
  });

  final StickerAttachment attachment;
  final Color textColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sticker = ref.watch(usableEmojisByIdProvider)[attachment.emojiId];
    final placeholder = Container(
      key: const ValueKey('sticker-placeholder'),
      width: stickerSize,
      height: stickerSize,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sticky_note_2_outlined, color: textColor),
          const SizedBox(height: 8),
          Text(
            stickerPreviewText(attachment.name),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColor),
          ),
        ],
      ),
    );
    if (sticker == null) {
      return placeholder;
    }
    // No tooltip: long presses open the message's actions.
    return CustomEmojiImage(
      key: ValueKey('sticker-image-${sticker.id}'),
      storagePath: sticker.storagePath,
      size: stickerSize,
      fallback: placeholder,
      semanticLabel: stickerPreviewText(sticker.name),
    );
  }
}
