import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_feed_composer.dart';
import 'package:wecord/features/circles/circle_post_grid_card.dart';
import 'package:wecord/features/circles/circle_post_tile.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How the circle's feed lists its posts.
enum CircleFeedLayout { list, grid }

/// The circle's feed: the composer card, a filter row (all, featured, a
/// topic) with a switch between the list and the grid, then the posts.
class CircleFeedView extends StatefulWidget {
  const CircleFeedView({
    required this.circleId,
    required this.posts,
    required this.onChanged,
    this.initialTag,
    this.initialFeaturedOnly = false,
    this.initialLayout = CircleFeedLayout.list,
    this.showComposer = true,
    super.key,
  });

  final String circleId;
  final List<CirclePost> posts;
  final VoidCallback onChanged;

  /// A topic to start filtered by (from a link or the search).
  final String? initialTag;
  final bool initialFeaturedOnly;
  final CircleFeedLayout initialLayout;
  final bool showComposer;

  @override
  State<CircleFeedView> createState() => _CircleFeedViewState();
}

class _CircleFeedViewState extends State<CircleFeedView> {
  late bool _featuredOnly = widget.initialFeaturedOnly;
  late String? _tag = widget.initialTag;
  late CircleFeedLayout _layout = widget.initialLayout;

  /// The topics used in the circle, the most used first.
  List<String> _topics() {
    final counts = <String, int>{};
    for (final post in widget.posts) {
      for (final tag in post.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final tags = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    final shown = tags.take(12).toList();
    final chosen = _tag;
    if (chosen != null && !shown.contains(chosen)) {
      shown.insert(0, chosen);
    }
    return shown;
  }

  List<CirclePost> _visible() {
    final tag = _tag;
    final posts = [
      for (final post in widget.posts)
        if ((!_featuredOnly || post.isFeatured) &&
            (tag == null || post.tags.contains(tag)))
          post,
    ];
    if (_featuredOnly) {
      posts.sort((a, b) => b.featuredAt!.compareTo(a.featuredAt!));
    }
    return posts;
  }

  void _openPost(CirclePost post) {
    context.push(circlePostPath(widget.circleId, post.id));
  }

  void _chooseTag(String tag) =>
      setState(() => _tag = _tag == tag ? null : tag);

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final posts = _visible();
    final filtered = _featuredOnly || _tag != null;
    final grid = _layout == CircleFeedLayout.grid;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 3 : 2;
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showComposer)
          CircleFeedComposer(
            circleId: widget.circleId,
            onPosted: widget.onChanged,
          ),
        if (widget.showComposer) const SizedBox(height: 10),
        _FilterRow(
          featuredOnly: _featuredOnly,
          tag: _tag,
          topics: _topics(),
          layout: _layout,
          onAll: () => setState(() {
            _featuredOnly = false;
            _tag = null;
          }),
          onFeatured: () => setState(() => _featuredOnly = !_featuredOnly),
          onTag: _chooseTag,
          onLayout: (layout) => setState(() => _layout = layout),
        ),
        if (posts.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 40),
            child: Column(
              children: [
                ThingAvatar(
                  icon: filtered
                      ? Icons.filter_alt_off_outlined
                      : Icons.dynamic_feed_outlined,
                  size: 56,
                  color: c.raised,
                  foregroundColor: c.muted,
                ),
                const SizedBox(height: 12),
                Text(
                  filtered ? tr('No posts match') : tr('No posts yet'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: grid ? 900 : 680),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              sliver: SliverToBoxAdapter(child: header),
            ),
            if (grid)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 10, 12, bottom),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: _gridCardHeight(context, width, columns),
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => CirclePostGridCard(
                      post: posts[index],
                      onOpen: () => _openPost(posts[index]),
                    ),
                    childCount: posts.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 10, 12, bottom),
                sliver: SliverList.separated(
                  itemCount: posts.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) => CirclePostTile(
                    post: posts[index],
                    onChanged: widget.onChanged,
                    onOpenTag: _chooseTag,
                    onOpen: () => _openPost(posts[index]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A card is a 4:3 cover and a text block that grows with the text size.
  double _gridCardHeight(BuildContext context, double width, int columns) {
    final contentWidth = (width > 900 ? 900 : width) - 24 - (columns - 1) * 10;
    final cardWidth = contentWidth / columns;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return cardWidth * 3 / 4 + 86 * scale;
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.featuredOnly,
    required this.tag,
    required this.topics,
    required this.layout,
    required this.onAll,
    required this.onFeatured,
    required this.onTag,
    required this.onLayout,
  });

  final bool featuredOnly;
  final String? tag;
  final List<String> topics;
  final CircleFeedLayout layout;
  final VoidCallback onAll;
  final VoidCallback onFeatured;
  final ValueChanged<String> onTag;
  final ValueChanged<CircleFeedLayout> onLayout;

  @override
  Widget build(BuildContext context) {
    final grid = layout == CircleFeedLayout.grid;
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                WeCordChip(
                  label: tr('All'),
                  selected: !featuredOnly && tag == null,
                  onPressed: onAll,
                ),
                const SizedBox(width: 6),
                WeCordChip(
                  label: tr('Featured'),
                  icon: Icons.star_rounded,
                  selected: featuredOnly,
                  onPressed: onFeatured,
                ),
                for (final topic in topics) ...[
                  const SizedBox(width: 6),
                  WeCordChip(
                    label: '#$topic',
                    selected: topic == tag,
                    semanticLabel: tr('Topic {tag}', {'tag': topic}),
                    onPressed: () => onTag(topic),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        WeCordIconButton(
          tooltip: grid ? tr('List view') : tr('Grid view'),
          icon: grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
          variant: WeCordButtonVariant.ghost,
          size: 36,
          onPressed: () =>
              onLayout(grid ? CircleFeedLayout.list : CircleFeedLayout.grid),
        ),
      ],
    );
  }
}
