import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chain/chain_actions.dart';
import 'package:wecord/features/chain/chain_models.dart';
import 'package:wecord/features/chain/chain_repository.dart';
import 'package:wecord/features/chain/chain_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the whole chain: every line, who started it, and the creator's and
/// moderators' tools. It follows the chain live.
Future<void> showChainSheet(
  BuildContext context, {
  required String chainId,
  String fallbackTitle = '',
}) {
  return showWeCordSheet<void>(
    context,
    detents: const [0.6, 0.92],
    builder: (context, scrollController) => ChainSheet(
      chainId: chainId,
      fallbackTitle: fallbackTitle,
      scrollController: scrollController,
    ),
  );
}

class ChainSheet extends ConsumerWidget {
  const ChainSheet({
    required this.chainId,
    this.fallbackTitle = '',
    this.scrollController,
    super.key,
  });

  final String chainId;
  final String fallbackTitle;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final chain = ref.watch(chainProvider(chainId));
    final snapshot = chain.value;
    if (snapshot == null) {
      return Center(
        child: chain.hasError
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr("This chain isn't available any more."),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: c.muted),
                ),
              )
            : const CircularProgressIndicator(),
      );
    }
    return _SheetBody(
      chain: snapshot,
      fallbackTitle: fallbackTitle,
      scrollController: scrollController,
    );
  }
}

class _SheetBody extends ConsumerWidget {
  const _SheetBody({
    required this.chain,
    required this.fallbackTitle,
    required this.scrollController,
  });

  final ChainSnapshot chain;
  final String fallbackTitle;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final now = DateTime.now();
    final closed = chain.isClosed(now);
    final mine = chain.myEntry;
    final title = chain.title.isEmpty ? fallbackTitle : chain.title;

    Widget removeButton(ChainEntry entry) => WeCordIconButton(
      tooltip: tr("Remove {name}'s line", {'name': entry.displayName}),
      icon: Icons.close_rounded,
      size: 32,
      iconSize: 18,
      variant: WeCordButtonVariant.ghost,
      onPressed: () => unawaited(
        runChainAction(
          context,
          ref,
          chain.id,
          () => ref.read(chainRepositoryProvider).removeEntry(entry.id),
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: ListView(
        key: const ValueKey('chain-sheet'),
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ChainIconTile(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (chain.creatorName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          tr('Started by {name}', {'name': chain.creatorName}),
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChainStatusPill(
                text: chainStatusText(context, chain, now),
                closed: closed,
              ),
              Text(
                chainCountText(chain),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
            ],
          ),
          if (chain.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              chain.description,
              style: TextStyle(fontSize: 15, height: 1.4, color: c.ink),
            ),
          ],
          if (chain.example.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: c.well,
                borderRadius: BorderRadius.circular(WeCordRadii.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Example'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: c.subtle,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chain.example,
                    style: TextStyle(fontSize: 14, color: c.ink),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: chain.entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      tr('Nobody has joined yet.'),
                      style: TextStyle(fontSize: 14, color: c.muted),
                    ),
                  )
                : Column(
                    children: [
                      for (final (index, entry) in chain.entries.indexed)
                        ChainLine(
                          key: ValueKey('chain-line-${entry.id}'),
                          number: index + 1,
                          entry: entry,
                          mine: entry.id == chain.myEntryId,
                          avatar: true,
                          trailing: chain.canManage
                              ? removeButton(entry)
                              : null,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          if (closed)
            Text(
              tr('This chain is closed. Nobody can join or change a line.'),
              style: TextStyle(fontSize: 14, color: c.muted),
            )
          else if (mine != null)
            WeCordButton(
              key: const ValueKey('chain-edit-mine'),
              label: tr('Edit my line'),
              icon: Icons.edit_outlined,
              variant: WeCordButtonVariant.secondary,
              size: WeCordButtonSize.large,
              expand: true,
              onPressed: () =>
                  unawaited(showChainNoteSheet(context, chain: chain)),
            )
          else if (chain.isFull)
            Text(
              tr('This chain is full.'),
              style: TextStyle(fontSize: 14, color: c.muted),
            )
          else
            WeCordButton(
              key: const ValueKey('chain-join'),
              label: tr('Join'),
              icon: Icons.add_rounded,
              variant: WeCordButtonVariant.accent,
              size: WeCordButtonSize.large,
              expand: true,
              onPressed: () =>
                  unawaited(showChainNoteSheet(context, chain: chain)),
            ),
          const SizedBox(height: 16),
          SettingsGroup(
            color: c.well,
            children: [
              SettingsRow(
                key: const ValueKey('chain-copy'),
                icon: Icons.copy_rounded,
                title: tr('Copy list'),
                subtitle: tr('As plain text, numbered'),
                onTap: () => unawaited(copyChainList(context, chain)),
              ),
              SettingsRow(
                key: const ValueKey('chain-share'),
                icon: Icons.ios_share_rounded,
                title: tr('Share list'),
                onTap: () => unawaited(shareChainList(context, chain)),
              ),
              if (chain.canManage)
                SettingsRow(
                  key: const ValueKey('chain-close-toggle'),
                  icon: closed
                      ? Icons.lock_open_rounded
                      : Icons.lock_outline_rounded,
                  tone: closed ? SettingsTone.accent : SettingsTone.warning,
                  title: closed ? tr('Reopen chain') : tr('Close chain'),
                  subtitle: closed
                      ? tr('People can join and change their lines again.')
                      : tr(
                          'Nobody can join or change a line until you reopen it.',
                        ),
                  onTap: () => unawaited(
                    runChainAction(
                      context,
                      ref,
                      chain.id,
                      () => ref
                          .read(chainRepositoryProvider)
                          .setClosed(chain.id, closed: !closed),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
