import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';

/// What a quick switcher entry opens.
enum QuickSwitchKind { direct, group, channel, circle }

/// A place the quick switcher can jump to.
class QuickSwitchItem {
  const QuickSwitchItem({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.avatarUrl,
    this.conversation,
    this.lastActivityAt,
    this.unread = false,
  });

  final QuickSwitchKind kind;

  /// The conversation id, or the circle id for circles.
  final String id;
  final String title;

  /// The circle a channel belongs to.
  final String? subtitle;
  final String? avatarUrl;

  /// Set for direct messages, groups and channels.
  final ConversationSummary? conversation;
  final DateTime? lastActivityAt;
  final bool unread;
}

/// Every direct message, group, channel and circle the user can open.
List<QuickSwitchItem> quickSwitchItems({
  required List<ConversationSummary> conversations,
  required List<CircleSummary> circles,
}) {
  final circleNames = {for (final circle in circles) circle.id: circle.name};
  return [
    for (final conversation in conversations)
      if (_kindOf(conversation) case final kind?)
        QuickSwitchItem(
          kind: kind,
          id: conversation.id,
          title: conversation.title?.trim().isNotEmpty == true
              ? conversation.title!.trim()
              : tr('Conversation'),
          subtitle: circleNames[conversation.circleId],
          avatarUrl: conversation.avatarUrl,
          conversation: conversation,
          lastActivityAt: conversation.lastMessageAt,
          unread:
              (conversation.unreadCount > 0 || conversation.isMarkedUnread) &&
              !conversation.isMuted,
        ),
    for (final circle in circles)
      QuickSwitchItem(
        kind: QuickSwitchKind.circle,
        id: circle.id,
        title: circle.name,
        avatarUrl: circle.avatarUrl,
        lastActivityAt: circle.latestActivityAt,
        unread: circle.unreadCount > 0 && !circle.isMuted,
      ),
  ];
}

QuickSwitchKind? _kindOf(ConversationSummary conversation) {
  return switch (conversation.type) {
    ConversationType.direct => QuickSwitchKind.direct,
    ConversationType.group => QuickSwitchKind.group,
    ConversationType.channel when conversation.circleId != null =>
      QuickSwitchKind.channel,
    _ => null,
  };
}

/// How well [query] matches [text], higher is better, or null when it does
/// not: the whole text, then its start, the start of a word, anywhere, and
/// last its letters in order with gaps.
int? quickSwitchScore(String query, String text) {
  final needle = query.trim().toLowerCase();
  final haystack = text.trim().toLowerCase();
  if (needle.isEmpty) {
    return 0;
  }
  if (haystack == needle) {
    return 1000;
  }
  if (haystack.startsWith(needle)) {
    return 900 - (haystack.length - needle.length).clamp(0, 99);
  }
  final index = haystack.indexOf(needle);
  if (index > 0) {
    final before = haystack[index - 1];
    final atWord = RegExp(r'[\s\-_.#@/]').hasMatch(before);
    return (atWord ? 700 : 500) - index.clamp(0, 99);
  }
  // Letters in order: "gnrl" finds "general".
  var position = 0;
  var gaps = 0;
  for (final char in needle.split('')) {
    final found = haystack.indexOf(char, position);
    if (found < 0) {
      return null;
    }
    gaps += found - position;
    position = found + 1;
  }
  return 300 - gaps.clamp(0, 299);
}

/// [items] matching [query], best first. A leading `@` keeps direct
/// messages and groups, `#` channels and `*` circles. Without a query the
/// most recent places come first.
List<QuickSwitchItem> searchQuickSwitchItems(
  List<QuickSwitchItem> items,
  String query, {
  int limit = 30,
}) {
  var text = query.trim();
  Set<QuickSwitchKind>? kinds;
  if (text.isNotEmpty) {
    kinds = switch (text[0]) {
      '@' => {QuickSwitchKind.direct, QuickSwitchKind.group},
      '#' => {QuickSwitchKind.channel},
      '*' => {QuickSwitchKind.circle},
      _ => null,
    };
    if (kinds != null) {
      text = text.substring(1).trim();
    }
  }
  final scored = <(QuickSwitchItem, int)>[];
  for (final item in items) {
    if (kinds != null && !kinds.contains(item.kind)) {
      continue;
    }
    if (text.isEmpty) {
      scored.add((item, 0));
      continue;
    }
    final titleScore = quickSwitchScore(text, item.title);
    final subtitle = item.subtitle;
    final subtitleScore = subtitle == null
        ? null
        : quickSwitchScore(text, subtitle);
    final best = switch ((titleScore, subtitleScore)) {
      (final int title?, _) => title,
      // Matching only the circle name ranks below any title match.
      (null, final int circle?) => circle ~/ 4,
      _ => null,
    };
    if (best != null) {
      scored.add((item, best));
    }
  }
  int recency(QuickSwitchItem item) =>
      item.lastActivityAt?.millisecondsSinceEpoch ?? 0;
  scored.sort((left, right) {
    final byScore = right.$2.compareTo(left.$2);
    if (byScore != 0) {
      return byScore;
    }
    if (left.$1.unread != right.$1.unread) {
      return left.$1.unread ? -1 : 1;
    }
    return recency(right.$1).compareTo(recency(left.$1));
  });
  return [for (final (item, _) in scored.take(limit)) item];
}

/// Opens the quick switcher and goes where the user picks.
Future<void> showQuickSwitcher(BuildContext context) async {
  final item = await showDialog<QuickSwitchItem>(
    context: context,
    builder: (context) => const QuickSwitcherDialog(),
  );
  if (item == null || !context.mounted) {
    return;
  }
  openQuickSwitchItem(context, item);
}

void openQuickSwitchItem(BuildContext context, QuickSwitchItem item) {
  final conversation = item.conversation;
  if (conversation != null) {
    openConversation(context, conversation);
    return;
  }
  openPage(context, circleLocation(item.id));
}

class QuickSwitcherDialog extends ConsumerStatefulWidget {
  const QuickSwitcherDialog({super.key});

  @override
  ConsumerState<QuickSwitcherDialog> createState() =>
      _QuickSwitcherDialogState();
}

class _QuickSwitcherDialogState extends ConsumerState<QuickSwitcherDialog> {
  final _controller = TextEditingController();
  var _highlighted = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<QuickSwitchItem> _results() {
    final items = quickSwitchItems(
      conversations:
          ref.watch(conversationsProvider).valueOrNull ??
          const <ConversationSummary>[],
      circles:
          ref.watch(circleSummariesProvider).valueOrNull ??
          const <CircleSummary>[],
    );
    return searchQuickSwitchItems(items, _controller.text);
  }

  KeyEventResult _handleKey(
    FocusNode node,
    KeyEvent event,
    List<QuickSwitchItem> results,
  ) {
    if (event is KeyUpEvent || results.isEmpty) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() {
        _highlighted = (_highlighted + step) % results.length;
      });
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      _pick(results);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _pick(List<QuickSwitchItem> results) {
    if (results.isEmpty) {
      return;
    }
    Navigator.of(
      context,
    ).pop(results[_highlighted.clamp(0, results.length - 1)]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final results = _results();
    final highlighted = results.isEmpty
        ? -1
        : _highlighted.clamp(0, results.length - 1);

    return Dialog(
      key: const ValueKey('quick-switcher'),
      alignment: const Alignment(0, -0.5),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (node, event) => _handleKey(node, event, results),
                child: TextField(
                  key: const ValueKey('quick-switcher-field'),
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.go,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search),
                    hintText: tr('Where would you like to go?'),
                  ),
                  onChanged: (_) => setState(() => _highlighted = 0),
                  onSubmitted: (_) => _pick(results),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          tr('Nothing matches. Try another name.'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: results.length,
                        itemBuilder: (context, index) => _QuickSwitchTile(
                          item: results[index],
                          highlighted: index == highlighted,
                          onTap: () =>
                              Navigator.of(context).pop(results[index]),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  'Tip: start with @ for direct messages, # for channels or * '
                  'for circles.',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickSwitchTile extends StatelessWidget {
  const _QuickSwitchTile({
    required this.item,
    required this.highlighted,
    required this.onTap,
  });

  final QuickSwitchItem item;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final leading = switch (item.kind) {
      QuickSwitchKind.channel => CircleAvatar(
        radius: 16,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: Icon(Icons.tag, size: 18, color: colorScheme.onSurfaceVariant),
      ),
      _ => FallbackAvatar(
        title: item.title,
        avatarUrl: item.avatarUrl,
        radius: 16,
      ),
    };
    final kindLabel = switch (item.kind) {
      QuickSwitchKind.direct => tr('Direct message'),
      QuickSwitchKind.group => tr('Group'),
      QuickSwitchKind.channel => item.subtitle ?? tr('Channel'),
      QuickSwitchKind.circle => tr('Circle'),
    };
    return Material(
      key: ValueKey('quick-switch-${item.id}'),
      color: highlighted ? colorScheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: item.unread ? FontWeight.w700 : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  kindLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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
