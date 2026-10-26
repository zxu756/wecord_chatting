// Extension point 3 of the chat page: the composer's "+" menu.
//
// The "+" button next to the message box opens a glass menu. Its entries are
// collected from [ComposerMenuContribution]s in `order`. A feature adds an
// entry by writing a contribution in its own file and listing it in
// `composer_menu_registrations.dart`. See "Chat page extension points" in
// docs/design/wecord-design-language.md.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry;
import 'package:wecord/shared/models/conversation.dart';

/// What the page itself does for its built-in entries. A new feature does not
/// need these: it opens its own sheet from [ComposerMenuContext.context].
class ComposerMenuActions {
  const ComposerMenuActions({
    required this.pickPhotosAndVideos,
    required this.pickFiles,
    required this.createPoll,
    required this.createChain,
    required this.sendContactCard,
    required this.sendLocation,
    required this.shareLiveLocation,
    required this.scheduleMessage,
    required this.insertTime,
    required this.showEvents,
    required this.changeWallpaper,
    required this.pickSticker,
    required this.pickGif,
    this.sendSilently,
    this.draftReply,
  });

  final Future<void> Function() pickPhotosAndVideos;
  final Future<void> Function() pickFiles;
  final Future<void> Function() createPoll;
  final Future<void> Function() createChain;
  final Future<void> Function() sendContactCard;
  final Future<void> Function() sendLocation;
  final Future<void> Function() shareLiveLocation;
  final Future<void> Function() scheduleMessage;
  final Future<void> Function() insertTime;
  final Future<void> Function() showEvents;
  final VoidCallback changeWallpaper;
  final Future<void> Function() pickSticker;
  final Future<void> Function() pickGif;

  /// Sends the text in the box without a push; null where that is not
  /// possible (the note to self, a server without it).
  final Future<void> Function()? sendSilently;

  /// Opens "Help me reply" (F6), which fills the box and never sends; null
  /// where it makes no sense (the note to self).
  final Future<void> Function()? draftReply;
}

/// What a contribution can look at when the menu opens.
class ComposerMenuContext {
  const ComposerMenuContext({
    required this.context,
    required this.conversationId,
    required this.conversationType,
    required this.compact,
    required this.gifAvailable,
    required this.actions,
  });

  /// A context at the "+" button, for navigation and providers.
  final BuildContext context;
  final String conversationId;
  final ConversationType? conversationType;

  /// A phone-width screen: wider screens have the GIF button in the composer
  /// and the wallpaper in the header, so those entries only show here.
  final bool compact;

  /// False once the server said GIF search isn't set up.
  final bool gifAvailable;
  final ComposerMenuActions actions;

  bool get isDirect => conversationType == ConversationType.direct;
  bool get isGroup => conversationType == ConversationType.group;

  /// The app's providers, for a contribution that needs to read one.
  ProviderContainer get container =>
      ProviderScope.containerOf(context, listen: false);
}

/// One feature's entry in the "+" menu.
class ComposerMenuContribution {
  const ComposerMenuContribution({
    required this.id,
    required this.order,
    required this.build,
  });

  /// Unique and stable, e.g. `poll` or `form`.
  final String id;

  /// Where the entry sits among the others, ascending. The built-in entries
  /// use 100, 200, ... in the menu's order; pick a number in between.
  final int order;

  /// The entry, or null when the feature does not apply to this chat.
  final GlassMenuEntry? Function(ComposerMenuContext ctx) build;
}

/// The "+" menu's entries, collected in `order`.
class ComposerMenuRegistry {
  ComposerMenuRegistry(Iterable<ComposerMenuContribution> contributions)
    : _contributions = _sorted(contributions);

  final List<ComposerMenuContribution> _contributions;

  /// The menu's entries for [ctx].
  List<GlassMenuEntry> entriesFor(ComposerMenuContext ctx) => [
    for (final contribution in _contributions) ?contribution.build(ctx),
  ];

  /// The ids in menu order (for tests).
  List<String> get ids => [for (final c in _contributions) c.id];

  static List<ComposerMenuContribution> _sorted(
    Iterable<ComposerMenuContribution> contributions,
  ) {
    final list = contributions.toList();
    assert(
      list.map((c) => c.id).toSet().length == list.length,
      'Two composer menu contributions share an id',
    );
    final indexed = list.indexed.toList()
      ..sort((a, b) {
        final byOrder = a.$2.order.compareTo(b.$2.order);
        return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
      });
    return [for (final (_, contribution) in indexed) contribution];
  }
}
