import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_repository.dart';
import 'package:wecord/features/whiteboard/whiteboard_routes.dart';
import 'package:wecord/features/whiteboard/whiteboard_versions_sheet.dart'
    show formatWhiteboardTime;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The whiteboards of a chat, newest change first, and a way to start one.
/// `/chats/<id>/whiteboards`.
class WhiteboardListPage extends ConsumerStatefulWidget {
  const WhiteboardListPage({required this.conversationId, super.key});

  final String conversationId;

  static const newKey = ValueKey('whiteboard-new');

  @override
  ConsumerState<WhiteboardListPage> createState() => _WhiteboardListPageState();
}

class _WhiteboardListPageState extends ConsumerState<WhiteboardListPage> {
  var _creating = false;

  Future<void> _create() async {
    final text = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('New whiteboard')),
        content: TextField(
          key: const ValueKey('whiteboard-new-name'),
          controller: text,
          autofocus: true,
          maxLength: WhiteboardLimits.maxTitle,
          decoration: InputDecoration(hintText: tr('Whiteboard name')),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            key: const ValueKey('whiteboard-new-create'),
            onPressed: () => Navigator.of(context).pop(text.text),
            child: Text(tr('Create')),
          ),
        ],
      ),
    );
    text.dispose();
    if (name == null || !mounted) {
      return;
    }
    setState(() => _creating = true);
    try {
      final board = await ref
          .read(whiteboardRepositoryProvider)
          .createBoard(
            widget.conversationId,
            title: name.trim(),
            id: newWhiteboardId(),
          );
      ref.invalidate(whiteboardListProvider(widget.conversationId));
      if (mounted) {
        openWhiteboard(
          context,
          conversationId: widget.conversationId,
          boardId: board.id,
          title: board.title,
        );
      }
    } on Object catch (error) {
      if (mounted) {
        final full = '$error'.contains('20');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              full
                  ? tr(
                      'This chat already has {max} whiteboards. Delete one to make another.',
                      {'max': WhiteboardLimits.maxBoardsPerChat},
                    )
                  : tr('Could not make a whiteboard.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final boards = ref.watch(whiteboardListProvider(widget.conversationId));
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(title: tr('Whiteboards')),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: WeCordButton(
                      key: WhiteboardListPage.newKey,
                      label: tr('New whiteboard'),
                      icon: Icons.add_rounded,
                      variant: WeCordButtonVariant.secondary,
                      size: WeCordButtonSize.small,
                      loading: _creating,
                      onPressed: () => unawaited(_create()),
                    ),
                  ),
                ),
                Expanded(
                  child: boards.when(
                    loading: () => Center(
                      child: CircularProgressIndicator(color: c.muted),
                    ),
                    error: (error, stack) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tr("That couldn't load. Try again."),
                            style: TextStyle(fontSize: 15, color: c.muted),
                          ),
                          const SizedBox(height: 12),
                          WeCordButton(
                            label: tr('Try again'),
                            variant: WeCordButtonVariant.secondary,
                            onPressed: () => ref.invalidate(
                              whiteboardListProvider(widget.conversationId),
                            ),
                          ),
                        ],
                      ),
                    ),
                    data: (list) => list.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                tr(
                                  'No whiteboards yet. Start one to sketch, plan or brainstorm together.',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.4,
                                  color: c.muted,
                                ),
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            children: [
                              SettingsGroup(
                                color: c.panel,
                                separatorIndent: 58,
                                children: [
                                  for (final board in list)
                                    SettingsRow(
                                      key: ValueKey(
                                        'whiteboard-row-${board.id}',
                                      ),
                                      icon: board.managersOnly
                                          ? Icons.lock_outline_rounded
                                          : Icons.draw_outlined,
                                      title: board.title.isEmpty
                                          ? tr('Untitled whiteboard')
                                          : board.title,
                                      subtitle: _subtitle(context, board),
                                      onTap: () => openWhiteboard(
                                        context,
                                        conversationId: widget.conversationId,
                                        boardId: board.id,
                                        title: board.title,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle(BuildContext context, WhiteboardSummary board) {
    final parts = <String>[
      tr('{count} items', {'count': board.elementCount}),
      if (board.updatedAt != null)
        formatWhiteboardTime(context, board.updatedAt!),
      if (board.updatedByName != null && board.updatedByName!.isNotEmpty)
        board.updatedByName!,
      if (board.managersOnly) tr('Only managers can draw'),
    ];
    return parts.join(' · ');
  }
}
