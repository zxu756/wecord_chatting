import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry;
import 'package:wecord/features/circles/circle_detail_screen.dart'
    show circleDetailProvider;
import 'package:wecord/features/circles/onboarding/guide_repository.dart'
    show circleGuideProvider;
import 'package:wecord/features/knowledge_base/kb_actions.dart';
import 'package:wecord/features/knowledge_base/kb_models.dart';
import 'package:wecord/features/knowledge_base/kb_repository.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// One page of a circle's knowledge base, open: the notes' editor with the
/// knowledge base around it (where the page sits, who may read and edit it,
/// moving and deleting it). Opening it counts as reading it, for the
/// newcomer guide's required pages.
class KbPageView extends ConsumerStatefulWidget {
  const KbPageView({
    required this.circleId,
    required this.pageId,
    this.embedded = false,
    this.onBack,
    this.onOpenPage,
    this.onGone,
    super.key,
  });

  final String circleId;
  final String pageId;

  /// Inside the two-pane layout on a wide screen: no page chrome of its own.
  final bool embedded;
  final VoidCallback? onBack;

  /// A page of the trail, or a new subpage, was picked.
  final ValueChanged<String>? onOpenPage;

  /// The page was deleted from here (or moved out of sight): close it.
  final VoidCallback? onGone;

  @override
  ConsumerState<KbPageView> createState() => _KbPageViewState();
}

class _KbPageViewState extends ConsumerState<KbPageView> {
  @override
  void initState() {
    super.initState();
    unawaited(_markRead());
  }

  Future<void> _markRead() async {
    try {
      await ref.read(knowledgeBaseRepositoryProvider).markRead(widget.pageId);
      ref
        ..invalidate(kbPagesProvider(widget.circleId))
        ..invalidate(circleGuideProvider(widget.circleId));
    } on Object {
      // Reading counts when it can; the page opens either way.
    }
  }

  List<GlassMenuEntry> _menu(NoteMeta meta) {
    final tree = ref.read(kbTreeProvider(widget.circleId)).value;
    final page = tree?.page(widget.pageId);
    if (tree == null || page == null) {
      return const [];
    }
    final circleId = widget.circleId;
    final depth = tree.depthOf(page.id);
    final siblings = page.parentId == null
        ? tree.roots
        : tree.childrenOf(page.parentId!);
    final index = siblings.indexWhere((s) => s.id == page.id);
    return [
      if (meta.canEdit &&
          depth < KnowledgeBaseLimits.depth &&
          tree.pages.length < KnowledgeBaseLimits.pages)
        GlassMenuEntry(
          icon: Icons.note_add_outlined,
          label: tr('Add a page inside'),
          onSelected: () => unawaited(() async {
            final id = await addKbPage(
              context,
              ref,
              circleId: circleId,
              parent: page,
            );
            if (id != null && mounted) {
              widget.onOpenPage?.call(id);
            }
          }()),
        ),
      if (meta.canManage) ...[
        GlassMenuEntry(
          icon: Icons.drive_file_move_outlined,
          label: tr('Move to…'),
          onSelected: () => unawaited(
            moveKbPageTo(
              context,
              ref,
              circleId: circleId,
              tree: tree,
              page: page,
            ),
          ),
        ),
        if (index > 0)
          GlassMenuEntry(
            icon: Icons.arrow_upward_rounded,
            label: tr('Move up'),
            onSelected: () => unawaited(
              shiftKbPage(
                context,
                ref,
                circleId: circleId,
                tree: tree,
                page: page,
                delta: -1,
              ),
            ),
          ),
        if (index >= 0 && index < siblings.length - 1)
          GlassMenuEntry(
            icon: Icons.arrow_downward_rounded,
            label: tr('Move down'),
            onSelected: () => unawaited(
              shiftKbPage(
                context,
                ref,
                circleId: circleId,
                tree: tree,
                page: page,
                delta: 1,
              ),
            ),
          ),
        GlassMenuEntry(
          icon: Icons.manage_accounts_outlined,
          label: tr('Who can read and edit…'),
          onSelected: () => unawaited(
            editKbAccess(context, ref, circleId: circleId, page: page),
          ),
        ),
        GlassMenuEntry(
          icon: Icons.delete_outline_rounded,
          label: tr('Delete page'),
          destructive: true,
          onSelected: () => unawaited(() async {
            final deleted = await deleteKbPage(
              context,
              ref,
              circleId: circleId,
              tree: tree,
              page: page,
            );
            if (deleted && mounted) {
              (widget.onGone ?? widget.onBack)?.call();
            }
          }()),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(kbTreeProvider(widget.circleId)).value;
    final detail = ref.watch(circleDetailProvider(widget.circleId)).value;
    final ancestors = tree?.ancestorsOf(widget.pageId) ?? const <KbPage>[];
    return NotePage(
      key: ValueKey('kb-page-${widget.pageId}'),
      noteId: widget.pageId,
      circleId: widget.circleId,
      embedded: widget.embedded,
      onBack: widget.onBack,
      selfName: detail?.currentMember?.displayName,
      knowledgeMenu: _menu,
      trail: ancestors.isEmpty
          ? null
          : KbTrail(
              circleName: detail?.circle.name,
              ancestors: ancestors,
              onOpen: widget.onOpenPage,
            ),
    );
  }
}

/// "Rules › Newcomers": the pages above the open one, each a way up.
class KbTrail extends StatelessWidget {
  const KbTrail({
    required this.ancestors,
    this.circleName,
    this.onOpen,
    super.key,
  });

  final String? circleName;
  final List<KbPage> ancestors;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final names = [
      for (final page in ancestors)
        page.title.trim().isEmpty ? tr('Untitled') : page.title,
    ];
    return Semantics(
      container: true,
      label: tr('Path: {path}', {'path': names.join(', ')}),
      child: Container(
        key: const ValueKey('kb-trail'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (index, page) in ancestors.indexed) ...[
              if (index > 0)
                Icon(Icons.chevron_right_rounded, size: 16, color: c.faint),
              WeCordPressable(
                key: ValueKey('kb-trail-${page.id}'),
                onPressed: onOpen == null ? null : () => onOpen!(page.id),
                semanticLabel: names[index],
                minTapSize: const Size(0, 36),
                shape: const StadiumBorder(),
                builder: (context, states) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    '${page.icon} ${names[index]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: states.contains(WidgetState.hovered)
                          ? c.ink
                          : c.muted,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
