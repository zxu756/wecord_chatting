// Extension point 2 of the chat page: the bubble footer slot.
//
// Small things that belong to a message but are not its content (the
// "edited" mark, a task chip, the thread chip, reactions, the review mark,
// the read receipt) are entries in this slot. A feature adds one by writing a
// [BubbleFooterEntry] in its own file and listing it in
// `bubble_footer_registrations.dart`. Two places exist:
//
//  * [BubbleFooterPlacement.insideBubble]: after the message's content, inside
//    the bubble (or card), e.g. "edited".
//  * [BubbleFooterPlacement.belowBubble]: under the bubble, e.g. reactions.
//
// See "Chat page extension points" in docs/design/wecord-design-language.md.
import 'package:flutter/widgets.dart';
import 'package:wecord/shared/models/message.dart';

/// Where in a message an entry sits.
enum BubbleFooterPlacement { insideBubble, belowBubble }

/// How a below-bubble entry is dressed. The bubble layout and the card layout
/// of circle channels space things differently; this picks how.
enum BubbleFooterWrap {
  /// The widget as it is: in a bubble, aligned with the bubble and no wider
  /// than it; in a card, [BubbleFooterEntry.cardGap] below the text.
  plain,

  /// A small status label: in a bubble, a pill that stays readable over a
  /// wallpaper and sits on the message's side; in a card, plain text
  /// [BubbleFooterEntry.cardGap] below.
  pill,

  /// The read receipt of the newest own message: a pill on the right edge.
  receipt,
}

/// What an entry can look at.
class BubbleFooterContext {
  const BubbleFooterContext({
    required this.context,
    required this.message,
    required this.isCurrentUser,
    required this.cards,
    required this.desktop,
    required this.textColor,
    required this.previewUrl,
    required this.showReadReceipt,
    required this.onToggleReaction,
    required this.onShowReactors,
    this.onOpenThread,
  });

  /// A context inside the message, for providers and navigation.
  final BuildContext context;
  final ChatMessage message;
  final bool isCurrentUser;

  /// The card layout of circle channels instead of bubbles.
  final bool cards;
  final bool desktop;

  /// The color of the message's text: what an entry inside the bubble should
  /// draw in.
  final Color textColor;

  /// The link whose preview card shows under the message, if any.
  final String? previewUrl;

  /// This is the newest own message and someone has read it.
  final bool showReadReceipt;
  final Future<void> Function(ChatMessage message, String emoji)
  onToggleReaction;
  final void Function(ChatMessage message, MessageReaction reaction)
  onShowReactors;
  final Future<void> Function(ChatMessage message)? onOpenThread;

  /// The message was deleted for everyone.
  bool get isRecalled => message.recalledAt != null;
}

/// One thing in the footer slot.
class BubbleFooterEntry {
  /// An entry under the bubble. [build] returns null when the entry does not
  /// apply to the message.
  const BubbleFooterEntry.below({
    required this.id,
    required this.order,
    required Widget? Function(BubbleFooterContext ctx) build,
    this.wrap = BubbleFooterWrap.plain,
    this.cardGap = 6,
    this.cardMaxWidth,
  }) : placement = BubbleFooterPlacement.belowBubble,
       _below = build,
       _inside = null;

  /// An entry inside the bubble, after the message's content. [build]
  /// returns the widgets to add (none when it does not apply).
  const BubbleFooterEntry.inside({
    required this.id,
    required this.order,
    required Iterable<Widget> Function(BubbleFooterContext ctx) build,
  }) : placement = BubbleFooterPlacement.insideBubble,
       wrap = BubbleFooterWrap.plain,
       cardGap = 0,
       cardMaxWidth = null,
       _below = null,
       _inside = build;

  /// Unique and stable, e.g. `edited` or `read-status`.
  final String id;

  /// Where it sits among the others of its placement, ascending. The built-in
  /// entries use 100, 200, ...; pick a number in between.
  final int order;
  final BubbleFooterPlacement placement;
  final BubbleFooterWrap wrap;

  /// In the card layout, the space above the entry.
  final double cardGap;

  /// In the card layout, the widest the entry may be (null for no limit).
  final double? cardMaxWidth;

  final Widget? Function(BubbleFooterContext ctx)? _below;
  final Iterable<Widget> Function(BubbleFooterContext ctx)? _inside;
}

/// An entry that has something to show for a message.
class BubbleFooterItem {
  const BubbleFooterItem(this.entry, this.child);

  final BubbleFooterEntry entry;
  final Widget child;
}

/// The footer slot's entries, collected in `order`.
class BubbleFooterRegistry {
  BubbleFooterRegistry(Iterable<BubbleFooterEntry> entries)
    : _entries = _sorted(entries);

  final List<BubbleFooterEntry> _entries;

  /// The widgets to add inside the bubble after the content.
  List<Widget> inside(BubbleFooterContext ctx) => [
    for (final entry in _entries)
      if (entry._inside case final build?) ...build(ctx),
  ];

  /// The entries with something to show under the bubble.
  List<BubbleFooterItem> below(BubbleFooterContext ctx) => [
    for (final entry in _entries)
      if (entry._below case final build?)
        if (build(ctx) case final child?) BubbleFooterItem(entry, child),
  ];

  /// The ids in order (for tests).
  List<String> get ids => [for (final entry in _entries) entry.id];

  static List<BubbleFooterEntry> _sorted(Iterable<BubbleFooterEntry> entries) {
    final list = entries.toList();
    assert(
      list.map((e) => e.id).toSet().length == list.length,
      'Two bubble footer entries share an id',
    );
    final indexed = list.indexed.toList()
      ..sort((a, b) {
        final byOrder = a.$2.order.compareTo(b.$2.order);
        return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
      });
    return [for (final (_, entry) in indexed) entry];
  }
}
