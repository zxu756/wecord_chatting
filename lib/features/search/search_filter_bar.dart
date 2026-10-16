import 'package:flutter/material.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/search_query.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The label of a `has:` kind.
String searchHasLabel(SearchHas kind) => switch (kind) {
  SearchHas.file => tr('File'),
  SearchHas.image => tr('Image'),
  SearchHas.video => tr('Video'),
  SearchHas.link => tr('Link'),
  SearchHas.poll => tr('Poll'),
  SearchHas.voice => tr('Voice message'),
  SearchHas.sticker => tr('Sticker'),
};

IconData searchHasIcon(SearchHas kind) => switch (kind) {
  SearchHas.file => Icons.insert_drive_file_outlined,
  SearchHas.image => Icons.image_outlined,
  SearchHas.video => Icons.movie_outlined,
  SearchHas.link => Icons.link_rounded,
  SearchHas.poll => Icons.poll_outlined,
  SearchHas.voice => Icons.mic_none_rounded,
  SearchHas.sticker => Icons.emoji_emotions_outlined,
};

/// What an operator does, for the options list and its chip.
String searchOperatorLabel(SearchOperator operator) => switch (operator) {
  SearchOperator.from => tr('From a person'),
  SearchOperator.mentions => tr('Mentions a person'),
  SearchOperator.inPlace => tr('In a channel or chat'),
  SearchOperator.has => tr('Has a file, link, image…'),
  SearchOperator.before => tr('Before a date'),
  SearchOperator.after => tr('After a date'),
  SearchOperator.during => tr('On a date'),
  SearchOperator.pinned => tr('Pinned messages'),
};

String searchOperatorExample(SearchOperator operator) => switch (operator) {
  SearchOperator.from => 'from:@user',
  SearchOperator.mentions => 'mentions:@user',
  SearchOperator.inPlace => 'in:#channel',
  SearchOperator.has => 'has:link',
  SearchOperator.before => 'before:2026-10-01',
  SearchOperator.after => 'after:2026-10-01',
  SearchOperator.during => 'during:2026-10-01',
  SearchOperator.pinned => 'pinned:true',
};

IconData searchOperatorIcon(SearchOperator operator) => switch (operator) {
  SearchOperator.from => Icons.person_outline_rounded,
  SearchOperator.mentions => Icons.alternate_email_rounded,
  SearchOperator.inPlace => Icons.tag_rounded,
  SearchOperator.has => Icons.attach_file_rounded,
  SearchOperator.before ||
  SearchOperator.after ||
  SearchOperator.during => Icons.event_outlined,
  SearchOperator.pinned => Icons.push_pin_outlined,
};

/// The label of a scope segment.
String searchScopeLabel(MessageSearchScope scope) => switch (scope) {
  EverywhereScope() => tr('Everywhere'),
  CircleScope() => tr('This circle'),
  ConversationScope(:final type) => switch (type) {
    ConversationType.channel => tr('This channel'),
    ConversationType.thread => tr('This thread'),
    _ => tr('This conversation'),
  },
};

/// What a filter token's chip says: "From @ada", "Has link".
String searchTokenChipLabel(SearchToken token) {
  final value = token.value;
  return switch (token.operator!) {
    SearchOperator.from => tr('From {name}', {'name': '@$value'}),
    SearchOperator.mentions => tr('Mentions {name}', {'name': '@$value'}),
    SearchOperator.inPlace => tr('In {name}', {'name': value}),
    SearchOperator.has => switch (SearchHas.tryParse(value)) {
      final kind? => tr('Has {kind}', {
        'kind': searchHasLabel(kind).toLowerCase(),
      }),
      null => tr('Has {kind}', {'kind': value}),
    },
    SearchOperator.before => tr('Before {date}', {'date': value}),
    SearchOperator.after => tr('After {date}', {'date': value}),
    SearchOperator.during => tr('On {date}', {'date': value}),
    SearchOperator.pinned =>
      parseSearchBool(value) == false ? tr('Not pinned') : tr('Pinned'),
  };
}

/// The filter chips under the search box: the filters in the query (tap to
/// remove) and one to add each kind.
class SearchFilterBar extends StatelessWidget {
  const SearchFilterBar({
    required this.parsed,
    required this.onRemove,
    required this.onAdd,
    super.key,
  });

  final ParsedSearchQuery parsed;
  final ValueChanged<SearchToken> onRemove;

  /// Opens the picker for a kind of filter (dates share one).
  final ValueChanged<SearchOperator> onAdd;

  static const _addable = [
    SearchOperator.from,
    SearchOperator.inPlace,
    SearchOperator.has,
    SearchOperator.mentions,
    SearchOperator.during,
    SearchOperator.pinned,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    // An operator still waiting for its value has no chip yet.
    final active = [
      for (final token in parsed.operatorTokens)
        if (token.value.isNotEmpty) token,
    ];
    final hasDate = active.any((token) => token.operator!.takesDate);
    final hasPinned = active.any(
      (token) => token.operator == SearchOperator.pinned,
    );
    final chips = <Widget>[
      for (final token in active)
        _ActiveChip(
          key: ValueKey('search-filter-${token.start}'),
          label: searchTokenChipLabel(token),
          valid: token.isValid,
          onRemove: () => onRemove(token),
        ),
      if (active.isNotEmpty)
        Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: c.line,
        ),
      for (final operator in _addable)
        if (!(operator.takesDate && hasDate) &&
            !(operator == SearchOperator.pinned && hasPinned))
          WeCordChip(
            key: ValueKey('search-add-${operator.keyword}'),
            label: switch (operator) {
              SearchOperator.from => tr('From'),
              SearchOperator.inPlace => tr('In'),
              SearchOperator.has => tr('Has'),
              SearchOperator.mentions => trIn('search', 'Mentions'),
              SearchOperator.pinned => tr('Pinned'),
              _ => tr('Date'),
            },
            icon: searchOperatorIcon(operator),
            onPaper: true,
            height: 32,
            onPressed: () => onAdd(operator),
          ),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: chips.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) =>
            Align(alignment: Alignment.center, child: chips[index]),
      ),
    );
  }
}

/// A filter in the query: ink pill with a close mark.
class _ActiveChip extends StatelessWidget {
  const _ActiveChip({
    required this.label,
    required this.valid,
    required this.onRemove,
    super.key,
  });

  final String label;
  final bool valid;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final background = valid ? c.ink : c.dangerSoft;
    final foreground = valid ? c.onInk : c.dangerText;
    return WeCordPressable(
      onPressed: onRemove,
      tooltip: tr('Remove filter'),
      semanticLabel: tr('Remove filter {name}', {'name': label}),
      builder: (context, states) {
        return Container(
          height: 32,
          padding: const EdgeInsets.only(left: 12, right: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(WeCordRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.close_rounded, size: 15, color: foreground),
            ],
          ),
        );
      },
    );
  }
}
