import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/discovery/circle_discovery_repository.dart';
import 'package:wecord/features/discovery/discovery_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The newest public circles (of [DiscoveryCategory], or all), for the
/// "New" row.
final discoveryNewCirclesProvider = FutureProvider.autoDispose
    .family<List<DiscoverableCircle>, DiscoveryCategory?>((
      ref,
      category,
    ) async {
      final page = await ref
          .watch(circleDiscoveryRepositoryProvider)
          .list(category: category, sort: DiscoverySort.newest, pageSize: 8);
      return page.circles;
    });

/// Explore public circles: search, category chips, the newest circles and
/// the popular ones (or search results), page by page as the list
/// scrolls. Cards open a preview to join from.
class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  static const path = '/discover';

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  var _query = '';
  DiscoveryCategory? _category;

  // The list below the sections: popular circles, or search results.
  var _items = <DiscoverableCircle>[];
  var _hasMore = true;
  var _loading = false;
  Object? _error;
  var _generation = 0;
  var _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _searching => _query.trim().isNotEmpty;

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || value.trim() == _query.trim()) {
        return;
      }
      setState(() => _query = value);
      _reload();
    });
  }

  void _selectCategory(DiscoveryCategory? category) {
    if (category == _category) {
      return;
    }
    setState(() => _category = category);
    _reload();
  }

  void _reload() {
    _generation++;
    setState(() {
      _items = [];
      _hasMore = true;
      _error = null;
      _loading = false;
      _loadedOnce = false;
    });
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    unawaited(_loadMore());
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) {
      return;
    }
    if (_scroll.position.extentAfter < 600) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _error != null) {
      return;
    }
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(circleDiscoveryRepositoryProvider)
          .list(
            query: _query,
            category: _category,
            sort: _searching ? DiscoverySort.relevance : DiscoverySort.popular,
            offset: _items.length,
          );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _items = [..._items, ...page.circles];
        _hasMore = page.hasMore;
        _loading = false;
        _loadedOnce = true;
      });
      // Short pages on tall windows: keep filling until the list scrolls.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeLoadMore();
      });
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
        _loadedOnce = true;
      });
    }
  }

  void _retry() {
    setState(() => _error = null);
    unawaited(_loadMore());
  }

  void _markJoined(String circleId) {
    setState(() {
      _items = [
        for (final circle in _items)
          circle.id == circleId
              ? circle.copyWith(
                  isMember: true,
                  memberCount: circle.isMember
                      ? circle.memberCount
                      : circle.memberCount + 1,
                )
              : circle,
      ];
    });
    ref.invalidate(discoveryNewCirclesProvider);
  }

  void _open(DiscoverableCircle circle) {
    unawaited(
      showDiscoverableCirclePreview(
        context,
        circle: circle,
        onJoined: _markJoined,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final width = MediaQuery.sizeOf(context).width;
    final wide = isWideLayout(width);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const maxContent = 1180.0;
            final gutter = wide ? 32.0 : 16.0;
            final content = (constraints.maxWidth - gutter * 2).clamp(
              0.0,
              maxContent,
            );
            final side = (constraints.maxWidth - content) / 2;
            const gap = 14.0;
            final columns = wide
                ? ((content + gap) / (300 + gap)).floor().clamp(1, 4)
                : (content >= 560 ? 2 : 1);
            final padding = EdgeInsets.symmetric(horizontal: side);

            return CustomScrollView(
              key: const ValueKey('discovery-scroll'),
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: wide
                        ? EdgeInsets.fromLTRB(side - 16, 18, side - 16, 0)
                        : EdgeInsets.zero,
                    child: PaperPageHeader(
                      title: tr('Explore circles'),
                      actions: [
                        WeCordIconButton(
                          key: const ValueKey('discovery-search-messages'),
                          icon: Icons.manage_search_rounded,
                          tooltip: tr('Search messages'),
                          variant: WeCordButtonVariant.onPaper,
                          size: 42,
                          onPressed: () =>
                              openPage(context, GlobalMessageSearchScreen.path),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: padding,
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
                          child: Text(
                            tr(
                              'Find public circles to join, or make yours '
                              'public in its settings.',
                            ),
                            style: TextStyle(fontSize: 14.5, color: c.muted),
                          ),
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: WeCordTextField(
                              fieldKey: const ValueKey('discovery-search'),
                              controller: _search,
                              onPaper: true,
                              hint: tr('Search circles, topics and tags'),
                              prefixIcon: Icons.search_rounded,
                              textInputAction: TextInputAction.search,
                              onChanged: _onQueryChanged,
                              onSubmitted: (value) {
                                _debounce?.cancel();
                                setState(() => _query = value);
                                _reload();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _CategoryChips(
                    selected: _category,
                    onSelected: _selectCategory,
                    padding: padding,
                    wrap: wide,
                  ),
                ),
                if (!_searching) ...[
                  SliverPadding(
                    padding: padding,
                    sliver: SliverToBoxAdapter(
                      child: _NewSection(
                        category: _category,
                        columns: columns,
                        wide: wide,
                        onOpen: _open,
                      ),
                    ),
                  ),
                ],
                SliverPadding(
                  padding: padding,
                  sliver: SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: _searching
                          ? tr('Results')
                          : (_category == null
                                ? tr('Popular')
                                : tr('Popular in {category}', {
                                    'category': _category!.label,
                                  })),
                      subtitle: _searching
                          ? null
                          : tr('Most members and most active lately'),
                    ),
                  ),
                ),
                ..._listSlivers(context, padding, columns, gap),
                SliverToBoxAdapter(child: SizedBox(height: 40 + bottom)),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _listSlivers(
    BuildContext context,
    EdgeInsets padding,
    int columns,
    double gap,
  ) {
    final c = context.tokens.colors;
    if (_items.isEmpty) {
      final Widget state;
      if (_error != null) {
        state = _InlineState(
          key: const ValueKey('discovery-error'),
          icon: Icons.cloud_off_rounded,
          title: tr('Could not load circles.'),
          message: tr('Check your connection and try again.'),
          action: WeCordButton(
            label: tr('Try again'),
            variant: WeCordButtonVariant.onPaper,
            onPressed: _retry,
          ),
        );
      } else if (!_loadedOnce || _loading) {
        state = const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        );
      } else if (_searching) {
        state = _InlineState(
          key: const ValueKey('discovery-no-results'),
          icon: Icons.search_off_rounded,
          title: tr('No circles match “{query}”', {'query': _query.trim()}),
          message: tr('Try another word, or another category.'),
        );
      } else {
        state = _InlineState(
          key: const ValueKey('discovery-empty'),
          icon: Icons.explore_outlined,
          title: _category == null
              ? tr('No public circles yet')
              : tr('No public circles in {category} yet', {
                  'category': _category!.label,
                }),
          message: tr(
            'Circles show up here once a manager turns on Public in '
            'Circle settings → Discovery.',
          ),
        );
      }
      return [
        SliverPadding(
          padding: padding,
          sliver: SliverToBoxAdapter(child: state),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: padding,
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: DiscoveryCircleCard.height,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => DiscoveryCircleCard(
              circle: _items[index],
              onOpen: () => _open(_items[index]),
            ),
            childCount: _items.length,
          ),
        ),
      ),
      SliverPadding(
        padding: padding,
        sliver: SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: switch ((_loading, _error, _hasMore)) {
              (true, _, _) => const Center(
                key: ValueKey('discovery-loading-more'),
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
              (_, Object(), _) => Column(
                key: const ValueKey('discovery-more-error'),
                children: [
                  Text(
                    tr('Could not load more circles.'),
                    style: TextStyle(fontSize: 13.5, color: c.dangerText),
                  ),
                  const SizedBox(height: 8),
                  WeCordButton(
                    label: tr('Try again'),
                    variant: WeCordButtonVariant.onPaper,
                    size: WeCordButtonSize.small,
                    onPressed: _retry,
                  ),
                ],
              ),
              (_, _, true) => const SizedBox(height: 24),
              _ => Center(
                child: Text(
                  tr("That's everything for now."),
                  style: TextStyle(fontSize: 13, color: c.subtle),
                ),
              ),
            },
          ),
        ),
      ),
    ];
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.selected,
    required this.onSelected,
    required this.padding,
    required this.wrap,
  });

  final DiscoveryCategory? selected;
  final ValueChanged<DiscoveryCategory?> onSelected;
  final EdgeInsets padding;

  /// Wraps onto more lines (wide screens) instead of scrolling sideways.
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final chips = [
      WeCordChip(
        key: const ValueKey('discovery-category-all'),
        label: tr('All'),
        icon: Icons.explore_outlined,
        onPaper: true,
        selected: selected == null,
        onPressed: () => onSelected(null),
      ),
      for (final category in DiscoveryCategory.values)
        WeCordChip(
          key: ValueKey('discovery-category-${category.value}'),
          label: category.label,
          icon: category.icon,
          onPaper: true,
          selected: selected == category,
          onPressed: () => onSelected(category),
        ),
    ];
    if (wrap) {
      return Padding(
        padding: padding,
        child: Wrap(spacing: 8, runSpacing: 8, children: chips),
      );
    }
    return SizedBox(
      height: 34,
      child: ListView.separated(
        key: const ValueKey('discovery-categories'),
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => chips[index],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final subtitle = this.subtitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 26, 2, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: c.ink,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 13, color: c.muted)),
          ],
        ],
      ),
    );
  }
}

/// The newest public circles: a row of cards (scrolling sideways on
/// phones). Hidden when there are none or they fail to load; the list
/// below says so.
class _NewSection extends ConsumerWidget {
  const _NewSection({
    required this.category,
    required this.columns,
    required this.wide,
    required this.onOpen,
  });

  final DiscoveryCategory? category;
  final int columns;
  final bool wide;
  final ValueChanged<DiscoverableCircle> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circles = ref.watch(discoveryNewCirclesProvider(category));
    final items = circles.value ?? const <DiscoverableCircle>[];
    if (circles.isLoading && items.isEmpty) {
      return const SizedBox(height: 12);
    }
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    const gap = 14.0;
    final Widget row;
    if (wide) {
      row = LayoutBuilder(
        builder: (context, constraints) {
          final shown = items.take(columns).toList();
          final cardWidth =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, circle) in shown.indexed) ...[
                if (index > 0) const SizedBox(width: gap),
                SizedBox(
                  width: cardWidth,
                  height: DiscoveryCircleCard.height,
                  child: DiscoveryCircleCard(
                    circle: circle,
                    onOpen: () => onOpen(circle),
                  ),
                ),
              ],
            ],
          );
        },
      );
    } else {
      row = SizedBox(
        height: DiscoveryCircleCard.height + 8,
        child: OverflowBox(
          // Bleeds to the screen edges so cards scroll under the gutter.
          maxWidth: MediaQuery.sizeOf(context).width,
          child: ListView.separated(
            key: const ValueKey('discovery-new-row'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => SizedBox(
              width: 280,
              child: DiscoveryCircleCard(
                circle: items[index],
                onOpen: () => onOpen(items[index]),
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      key: const ValueKey('discovery-new'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: tr('New'), subtitle: tr('Recently made public')),
        row,
      ],
    );
  }
}

class _InlineState extends StatelessWidget {
  const _InlineState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final message = this.message;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        children: [
          ThingAvatar(
            icon: icon,
            size: 60,
            color: c.raised,
            foregroundColor: c.muted,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: c.ink,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.muted, height: 1.45),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}
