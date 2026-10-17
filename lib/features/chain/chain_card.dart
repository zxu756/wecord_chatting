import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chain/chain_actions.dart';
import 'package:wecord/features/chain/chain_models.dart';
import 'package:wecord/features/chain/chain_repository.dart';
import 'package:wecord/features/chain/chain_sheet.dart';
import 'package:wecord/features/chain/chain_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How many lines the card in the chat shows before "and 5 more".
const chainCardLines = 6;

/// A chain in a chat: the numbered list as it is right now, with a Join
/// button. It follows the chain live (no message per entry); tapping it opens
/// the whole list.
class ChainCardView extends ConsumerWidget {
  const ChainCardView({required this.card, super.key});

  final ChainCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final async = ref.watch(chainProvider(card.chainId));
    final chain = async.value;
    final title = chain?.title.isNotEmpty == true ? chain!.title : card.title;
    final now = DateTime.now();

    void open() => unawaited(
      showChainSheet(context, chainId: card.chainId, fallbackTitle: card.title),
    );

    Widget body() {
      if (chain == null) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: async.hasError
              ? WeCordPressable(
                  onPressed: () => ref.invalidate(chainProvider(card.chainId)),
                  semanticLabel: tr('Try again'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WeCordRadii.sm),
                  ),
                  builder: (context, states) => Text(
                    tr("Couldn't load this chain. Tap to try again."),
                    style: TextStyle(fontSize: 13.5, color: c.muted),
                  ),
                )
              : Text(
                  tr('Loading…'),
                  style: TextStyle(fontSize: 13.5, color: c.muted),
                ),
        );
      }
      final closed = chain.isClosed(now);
      final shown = chain.entries.take(chainCardLines).toList();
      final hidden = chain.entries.length - shown.length;
      final mine = chain.myEntry;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chain.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                chain.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, height: 1.35, color: c.muted),
              ),
            ),
          const SizedBox(height: 10),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                chain.example.isNotEmpty
                    ? tr('Nobody has joined yet. Example: {example}', {
                        'example': chain.example,
                      })
                    : tr('Nobody has joined yet.'),
                style: TextStyle(fontSize: 13.5, color: c.muted),
              ),
            )
          else
            for (final (index, entry) in shown.indexed)
              ChainLine(
                number: index + 1,
                entry: entry,
                mine: entry.id == chain.myEntryId,
              ),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Text(
                tr('and {count} more', {'count': hidden}),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  chainCountText(chain),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (closed)
                const SizedBox.shrink()
              else if (mine != null)
                WeCordButton(
                  key: ValueKey('chain-edit-${card.chainId}'),
                  label: tr('Edit my line'),
                  variant: WeCordButtonVariant.secondary,
                  size: WeCordButtonSize.small,
                  onPressed: () =>
                      unawaited(showChainNoteSheet(context, chain: chain)),
                )
              else if (chain.isFull)
                Text(
                  tr('Full'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: c.muted,
                  ),
                )
              else
                WeCordButton(
                  key: ValueKey('chain-join-${card.chainId}'),
                  label: tr('Join'),
                  variant: WeCordButtonVariant.accent,
                  size: WeCordButtonSize.small,
                  onPressed: () =>
                      unawaited(showChainNoteSheet(context, chain: chain)),
                ),
            ],
          ),
        ],
      );
    }

    final status = chain == null ? null : chainStatusText(context, chain, now);
    final closed = chain?.isClosed(now) ?? false;
    final summary = chain == null
        ? title
        : '$title, ${chainCountText(chain)}, $status';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380, minWidth: 240),
      child: WeCordPressable(
        key: ValueKey('chain-card-${card.chainId}'),
        onPressed: open,
        semanticLabel: tr('Chain: {summary}', {'summary': summary}),
        hint: tr('Opens the whole list'),
        mergeSemantics: false,
        pressedScale: 0.99,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        builder: (context, states) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.well,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(
              color: states.contains(WidgetState.hovered) ? c.line : c.lineSoft,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ChainIconTile(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Chain'),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: c.subtle,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ChainStatusPill(text: status, closed: closed),
                  ),
                ),
              body(),
            ],
          ),
        ),
      ),
    );
  }
}
