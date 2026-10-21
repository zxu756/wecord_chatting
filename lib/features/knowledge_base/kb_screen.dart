import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart'
    show circleDetailProvider;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/knowledge_base/kb_actions.dart';
import 'package:wecord/features/knowledge_base/kb_models.dart';
import 'package:wecord/features/knowledge_base/kb_page_view.dart';
import 'package:wecord/features/knowledge_base/kb_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A circle's knowledge base: its rules, guides and answers as pages in a
/// tree. On a phone the tree is the screen and a page opens over it; on a
/// wide screen the tree sits beside the open page.
class KnowledgeBaseScreen extends ConsumerStatefulWidget {
  const KnowledgeBaseScreen({
    required this.circleId,
    this.initialPageId,
    super.key,
  });

  final String circleId;

  /// Opens this page at once (from the newcomer guide, a link).
  final String? initialPageId;

  static String pathFor(String circleId, {String? pageId}) {
    final base = '/circles/$circleId/knowledge';
    return pageId == null ? base : '$base?page=$pageId';
  }

  @override
  ConsumerState<KnowledgeBaseScreen> createState() =>
      _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends ConsumerState<KnowledgeBaseScreen> {
  String? _openId;
  var _cameWithPage = false;
  final _collapsed = <String>{};
  var _searching = false;
  final _searchController = TextEditingController();
  Timer? _debounce;
  var _query = '';
  List<KbSearchHit>? _hits;
  var _searchFailed = false;

  @override
  void initState() {
    super.initState();
    _openId = widget.initialPageId;
    _cameWithPage = widget.initialPageId != null;
  }

  @override
  void didUpdateWidget(KnowledgeBaseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPageId != oldWidget.initialPageId &&
        widget.initialPageId != null) {
      _openId = widget.initialPageId;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _circleId => widget.circleId;

  void _open(String id) => setState(() => _openId = id);

  void _closePage() {
    if (_cameWithPage && !circleWideLayout(context)) {
      // Opened straight on a page: back leaves the knowledge base.
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _openId = null;
      _cameWithPage = false;
    });
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    final query = text.trim();
    setState(() {
      _query = query;
      if (query.length < 2) {
        _hits = null;
        _searchFailed = false;
      }
    });
    if (query.length < 2) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final hits = await ref
            .read(knowledgeBaseRepositoryProvider)
            .search(_circleId, query);
        if (mounted && _query == query) {
          setState(() {
            _hits = hits;
            _searchFailed = false;
          });
        }
      } on Object {
        if (mounted && _query == query) {
          setState(() {
            _hits = null;
            _searchFailed = true;
          });
        }
      }
    });
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _query = '';
        _hits = null;
        _searchFailed = false;
      }
    });
  }

  Future<void> _addTopLevel() async {
    final id = await addKbPage(context, ref, circleId: _circleId);
    if (id != null && mounted) {
      _open(id);
    }
  }

  bool _canManage() {
    final detail = ref.read(circleDetailProvider(_circleId)).value;
    return detail?.can(CirclePermission.manageChannels) ?? false;
  }

  Future<void> _rowMenu(KbTree tree, KbPage page, Offset? position) async {
    final manage = _canManage();
    final depth = tree.depthOf(page.id);
    final siblings = page.parentId == null
        ? tree.roots
        : tree.childrenOf(page.parentId!);
    final index = siblings.indexWhere((s) => s.id == page.id);
    final items = <CircleMenuItem<_RowAction>>[
      if (page.canEdit &&
          depth < KnowledgeBaseLimits.depth &&
          tree.pages.length < KnowledgeBaseLimits.pages)
        CircleMenuItem(
          value: _RowAction.addInside,
          icon: Icons.note_add_outlined,
          label: tr('Add a page inside'),
        ),
      if (manage) ...[
        CircleMenuItem(
          value: _RowAction.moveTo,
          icon: Icons.drive_file_move_outlined,
          label: tr('Move to…'),
        ),
        if (index > 0)
          CircleMenuItem(
            value: _RowAction.moveUp,
            icon: Icons.arrow_upward_rounded,
            label: tr('Move up'),
          ),
        if (index >= 0 && index < siblings.length - 1)
          CircleMenuItem(
            value: _RowAction.moveDown,
            icon: Icons.arrow_downward_rounded,
            label: tr('Move down'),
          ),
        CircleMenuItem(
          value: _RowAction.access,
          icon: Icons.manage_accounts_outlined,
          label: tr('Who can read and edit…'),
        ),
        CircleMenuItem(
          value: _RowAction.delete,
          icon: Icons.delete_outline_rounded,
          label: tr('Delete page'),
          destructive: true,
        ),
      ],
    ];
    if (items.isEmpty) {
      return;
    }
    final action = await showCircleActionMenu<_RowAction>(
      context,
      items: items,
      title: page.title.trim().isEmpty ? tr('Untitled') : page.title,
      position: position,
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case _RowAction.addInside:
        final id = await addKbPage(
          context,
          ref,
          circleId: _circleId,
          parent: page,
        );
        if (id != null && mounted) {
          setState(() => _collapsed.remove(page.id));
          _open(id);
        }
      case _RowAction.moveTo:
        await moveKbPageTo(
          context,
          ref,
          circleId: _circleId,
          tree: tree,
          page: page,
        );
      case _RowAction.moveUp:
        await shiftKbPage(
          context,
          ref,
          circleId: _circleId,
          tree: tree,
          page: page,
          delta: -1,
        );
      case _RowAction.moveDown:
        await shiftKbPage(
          context,
          ref,
          circleId: _circleId,
          tree: tree,
          page: page,
          delta: 1,
        );
      case _RowAction.access:
        await editKbAccess(context, ref, circleId: _circleId, page: page);
      case _RowAction.delete:
        final deleted = await deleteKbPage(
          context,
          ref,
          circleId: _circleId,
          tree: tree,
          page: page,
        );
        if (deleted && mounted && _openId == page.id) {
          setState(() => _openId = null);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(circleDetailProvider(_circleId)).value;
    final tree = ref.watch(kbTreeProvider(_circleId));
    final wide = circleWideLayout(context);
    final manage = detail?.can(CirclePermission.manageChannels) ?? false;
    final openId = _openId;

    if (!wide && openId != null) {
      return PopScope(
        canPop: _cameWithPage,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _closePage();
          }
        },
        child: Scaffold(
          backgroundColor: context.tokens.colors.panel,
          body: SafeArea(
            bottom: false,
            child: KbPageView(
              circleId: _circleId,
              pageId: openId,
              onBack: _closePage,
              onOpenPage: _open,
              onGone: () => setState(() {
                _openId = null;
                _cameWithPage = false;
              }),
            ),
          ),
        ),
      );
    }

    final list = _ListPane(
      circleId: _circleId,
      tree: tree,
      manage: manage,
      selectedId: wide ? openId : null,
      collapsed: _collapsed,
      searching: _searching,
      searchController: _searchController,
      query: _query,
      hits: _hits,
      searchFailed: _searchFailed,
      onSearchChanged: _onSearchChanged,
      onOpen: _open,
      onToggle: (id) => setState(() {
        if (!_collapsed.add(id)) {
          _collapsed.remove(id);
        }
      }),
      onMenu: _rowMenu,
      onAddTop: _addTopLevel,
      onRetry: () => ref.invalidate(kbPagesProvider(_circleId)),
    );

    final Widget body;
    if (wide) {
      final c = context.tokens.colors;
      body = Row(
        children: [
          SizedBox(width: 340, child: list),
          VerticalDivider(width: 1, thickness: 1, color: c.lineSoft),
          Expanded(
            child: ColoredBox(
              color: c.panel,
              child: openId == null
                  ? const _PickAPage()
                  : KbPageView(
                      circleId: _circleId,
                      pageId: openId,
                      embedded: true,
                      onOpenPage: _open,
                      onGone: () => setState(() => _openId = null),
                    ),
            ),
          ),
        ],
      );
    } else {
      body = list;
    }

    return CirclePageScaffold(
      title: tr('Knowledge base'),
      subtitle: detail?.circle.name,
      constrainBody: !wide,
      actions: [
        WeCordIconButton(
          key: const ValueKey('kb-search-button'),
          tooltip: tr('Search pages'),
          icon: _searching ? Icons.close_rounded : Icons.search_rounded,
          variant: WeCordButtonVariant.onPaper,
          onPressed: _toggleSearch,
        ),
        if (manage)
          WeCordIconButton(
            key: const ValueKey('kb-add-button'),
            tooltip: tr('New page'),
            icon: Icons.add_rounded,
            variant: WeCordButtonVariant.accent,
            onPressed: () => unawaited(_addTopLevel()),
          ),
      ],
      body: body,
    );
  }
}

enum _RowAction { addInside, moveTo, moveUp, moveDown, access, delete }

class _PickAPage extends StatelessWidget {
  const _PickAPage();

  @override
  Widget build(BuildContext context) {
    return CircleEmptyState(
      icon: Icons.menu_book_outlined,
      title: tr('Pick a page'),
      message: tr('Choose a page on the left to read it.'),
    );
  }
}

/// The tree (or the results of a search), with the banner of pages to read.
class _ListPane extends StatelessWidget {
  const _ListPane({
    required this.circleId,
    required this.tree,
    required this.manage,
    required this.selectedId,
    required this.collapsed,
    required this.searching,
    required this.searchController,
    required this.query,
    required this.hits,
    required this.searchFailed,
    required this.onSearchChanged,
    required this.onOpen,
    required this.onToggle,
    required this.onMenu,
    required this.onAddTop,
    required this.onRetry,
  });

  final String circleId;
  final AsyncValue<KbTree> tree;
  final bool manage;
  final String? selectedId;
  final Set<String> collapsed;
  final bool searching;
  final TextEditingController searchController;
  final String query;
  final List<KbSearchHit>? hits;
  final bool searchFailed;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onToggle;
  final Future<void> Function(KbTree tree, KbPage page, Offset? position)
  onMenu;
  final VoidCallback onAddTop;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return tree.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => CircleEmptyState(
        icon: Icons.cloud_off_rounded,
        title: tr('Could not load the pages.'),
        message: tr('Check your connection and try again.'),
        action: WeCordButton(
          label: tr('Try again'),
          size: WeCordButtonSize.medium,
          onPressed: onRetry,
        ),
      ),
      data: (data) {
        if (data.isEmpty) {
          return CircleEmptyState(
            icon: Icons.menu_book_outlined,
            title: tr('No pages yet'),
            message: manage
                ? tr(
                    'Write down the rules, a guide for newcomers and the '
                    'answers people keep asking for.',
                  )
                : tr('The people who run this circle have not added anything.'),
            action: manage
                ? WeCordButton(
                    key: const ValueKey('kb-add-first'),
                    label: tr('Add the first page'),
                    variant: WeCordButtonVariant.accent,
                    size: WeCordButtonSize.medium,
                    onPressed: onAddTop,
                  )
                : null,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: WeCordTextField(
                  fieldKey: const ValueKey('kb-search-field'),
                  controller: searchController,
                  autofocus: true,
                  hint: tr('Search the knowledge base'),
                  prefixIcon: Icons.search_rounded,
                  textInputAction: TextInputAction.search,
                  onPaper: true,
                  onChanged: onSearchChanged,
                ),
              ),
            Expanded(
              child: searching && query.isNotEmpty
                  ? _Results(
                      query: query,
                      hits: hits,
                      failed: searchFailed,
                      onOpen: onOpen,
                    )
                  : _Tree(
                      tree: data,
                      manage: manage,
                      selectedId: selectedId,
                      collapsed: collapsed,
                      onOpen: onOpen,
                      onToggle: onToggle,
                      onMenu: onMenu,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Tree extends StatelessWidget {
  const _Tree({
    required this.tree,
    required this.manage,
    required this.selectedId,
    required this.collapsed,
    required this.onOpen,
    required this.onToggle,
    required this.onMenu,
  });

  final KbTree tree;

  /// The person manages channels: they can arrange and delete pages.
  final bool manage;
  final String? selectedId;
  final Set<String> collapsed;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onToggle;
  final Future<void> Function(KbTree tree, KbPage page, Offset? position)
  onMenu;

  @override
  Widget build(BuildContext context) {
    final rows = tree.rows(collapsed: collapsed);
    final unread = tree.unreadRequired;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        12,
        4,
        12,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (unread > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ReadFirstBanner(count: unread),
          ),
        for (final row in rows)
          KbTile(
            key: ValueKey('kb-row-${row.page.id}'),
            row: row,
            selected: row.page.id == selectedId,
            onOpen: () => onOpen(row.page.id),
            onToggle: row.hasChildren ? () => onToggle(row.page.id) : null,
            onMenu: manage || row.page.canEdit
                ? (position) => unawaited(onMenu(tree, row.page, position))
                : null,
          ),
      ],
    );
  }
}

class _ReadFirstBanner extends StatelessWidget {
  const _ReadFirstBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: const ValueKey('kb-read-first'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.bookmark_added_outlined, size: 20, color: c.accentText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? tr('1 page is required reading. Start with it.')
                  : tr('{count} pages are required reading. Start with them.', {
                      'count': count,
                    }),
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: c.accentText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One page in the tree.
class KbTile extends StatelessWidget {
  const KbTile({
    required this.row,
    required this.onOpen,
    this.selected = false,
    this.onToggle,
    this.onMenu,
    super.key,
  });

  final KbRow row;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback? onToggle;
  final void Function(Offset? position)? onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final page = row.page;
    final title = page.title.trim().isEmpty ? tr('Untitled') : page.title;
    final tags = <Widget>[
      if (page.restricted)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 13, color: c.subtle),
            const SizedBox(width: 3),
            Text(
              tr('Limited'),
              style: TextStyle(fontSize: 12, color: c.subtle),
            ),
          ],
        ),
      if (page.required && !page.read)
        CircleTag(
          label: tr('Required reading'),
          background: c.accentSoft,
          foreground: c.accentText,
        ),
      if (page.required && page.read)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 13, color: c.successText),
            const SizedBox(width: 3),
            Text(
              tr('Read'),
              style: TextStyle(fontSize: 12, color: c.successText),
            ),
          ],
        ),
    ];
    final semantics = [
      title,
      if (page.restricted) tr('Limited to some roles'),
      if (page.required && !page.read) tr('Required reading'),
      if (page.required && page.read) tr('Read'),
      if (row.hasChildren) row.expanded ? tr('Expanded') : tr('Collapsed'),
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(width: (row.depth - 1) * 14.0),
          SizedBox(
            width: 48,
            child: row.hasChildren
                ? WeCordIconButton(
                    key: ValueKey('kb-toggle-${page.id}'),
                    tooltip: row.expanded
                        ? tr('Collapse {title}', {'title': title})
                        : tr('Expand {title}', {'title': title}),
                    icon: row.expanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    iconSize: 22,
                    size: 40,
                    variant: WeCordButtonVariant.ghost,
                    onPressed: onToggle,
                  )
                : null,
          ),
          Expanded(
            child: WeCordPressable(
              onPressed: onOpen,
              onLongPress: onMenu == null ? null : () => onMenu!(null),
              selected: selected,
              semanticLabel: semantics,
              pressedScale: 0.99,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WeCordRadii.md),
              ),
              builder: (context, states) => Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                decoration: BoxDecoration(
                  color: selected
                      ? c.accentSoft
                      : states.contains(WidgetState.hovered)
                      ? c.raised
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(WeCordRadii.md),
                ),
                child: Row(
                  children: [
                    Text(page.icon, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: selected ? c.accentText : c.ink,
                            ),
                          ),
                          if (tags.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: tags,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (onMenu != null)
                      Builder(
                        builder: (buttonContext) => WeCordIconButton(
                          key: ValueKey('kb-more-${page.id}'),
                          tooltip: tr('Options for {title}', {'title': title}),
                          icon: Icons.more_horiz_rounded,
                          iconSize: 20,
                          size: 40,
                          variant: WeCordButtonVariant.ghost,
                          onPressed: () {
                            final box =
                                buttonContext.findRenderObject() as RenderBox?;
                            onMenu!(
                              box?.localToGlobal(
                                box.size.bottomRight(Offset.zero),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.query,
    required this.hits,
    required this.failed,
    required this.onOpen,
  });

  final String query;
  final List<KbSearchHit>? hits;
  final bool failed;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    if (query.length < 2) {
      return _Hint(tr('Type at least two letters.'));
    }
    if (failed) {
      return _Hint(tr('Could not search. Try again.'));
    }
    final hits = this.hits;
    if (hits == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (hits.isEmpty) {
      return _Hint(tr('No page matches “{query}”.', {'query': query}));
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(
        12,
        4,
        12,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        for (final hit in hits)
          WeCordPressable(
            key: ValueKey('kb-hit-${hit.id}'),
            onPressed: () => onOpen(hit.id),
            semanticLabel: hit.title.trim().isEmpty
                ? tr('Untitled')
                : hit.title,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
            pressedScale: 0.99,
            builder: (context, states) => Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
                color: states.contains(WidgetState.hovered)
                    ? c.raised
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(WeCordRadii.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hit.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hit.title.trim().isEmpty ? tr('Untitled') : hit.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                        if (hit.snippet.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              hit.snippet,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.35,
                                color: c.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Align(
        alignment: Alignment.topCenter,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: context.tokens.colors.muted),
        ),
      ),
    );
  }
}
