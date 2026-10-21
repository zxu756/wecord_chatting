import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/forum.dart';
import 'package:wecord/shared/ui/display_size_image.dart';
import 'package:wecord/shared/ui/ui.dart';

/// One entry of a tile's menu.
class MediaTileAction {
  const MediaTileAction({
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
}

/// How many columns a wall of [width] gets: about 170 logical pixels a tile,
/// two on a phone and at most six.
int mediaWallColumns(double width) {
  return math.max(2, math.min(6, (width / 170).floor()));
}

/// The posts of a media channel as a wall of pictures: each post is its first
/// picture with the title on it, loading more at the end like the forum's
/// list. [controller] is the list's scroll controller (the forum view loads
/// the next page from it).
class MediaWall extends StatelessWidget {
  const MediaWall({
    required this.posts,
    required this.controller,
    required this.onOpen,
    required this.actionsFor,
    this.footer,
    this.now,
    super.key,
  });

  final List<ForumPost> posts;
  final ScrollController controller;
  final void Function(ForumPost post) onOpen;
  final List<MediaTileAction> Function(ForumPost post) actionsFor;

  /// Under the last row: a spinner, a retry button or nothing.
  final Widget? footer;

  /// The current time, for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Large text would cover a small square: one wide tile per row.
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.5;
        final columns = largeText
            ? 1
            : mediaWallColumns(constraints.maxWidth - 24);
        return CustomScrollView(
          key: const ValueKey('media-wall'),
          controller: controller,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: largeText ? 1.4 : 1,
                ),
                delegate: SliverChildBuilderDelegate(childCount: posts.length, (
                  context,
                  index,
                ) {
                  final post = posts[index];
                  return MediaWallTile(
                    key: ValueKey('media-post-${post.id}'),
                    post: post,
                    onTap: () => onOpen(post),
                    actions: actionsFor(post),
                    now: now,
                  );
                }),
              ),
            ),
            if (footer != null) SliverToBoxAdapter(child: footer),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        );
      },
    );
  }
}

/// A post as a square: its picture, with the title, who posted it and how
/// many replies it has on a shade at the bottom.
class MediaWallTile extends ConsumerStatefulWidget {
  const MediaWallTile({
    required this.post,
    required this.onTap,
    this.actions = const [],
    this.now,
    super.key,
  });

  final ForumPost post;
  final VoidCallback onTap;
  final List<MediaTileAction> actions;
  final DateTime? now;

  @override
  ConsumerState<MediaWallTile> createState() => _MediaWallTileState();
}

class _MediaWallTileState extends ConsumerState<MediaWallTile> {
  Future<String>? _url;

  /// Whether the URL was signed again after the picture failed to load.
  bool _resigned = false;

  @override
  void initState() {
    super.initState();
    _url = _load();
  }

  @override
  void didUpdateWidget(MediaWallTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.post.thumbnail;
    final after = widget.post.thumbnail;
    if (before?.path != after?.path || before?.bucket != after?.bucket) {
      _url = _load();
      _resigned = false;
    }
  }

  Future<String>? _load() {
    final thumbnail = widget.post.thumbnail;
    if (thumbnail == null) {
      return null;
    }
    return ref.read(circlesRepositoryProvider).createImageUrl(thumbnail);
  }

  /// The signed URL may have expired while the wall stayed open: sign it
  /// again, once.
  void _resignAfterError() {
    if (_resigned) {
      return;
    }
    _resigned = true;
    scheduleMicrotask(() {
      if (mounted) {
        setState(() {
          _url = _load();
        });
      }
    });
  }

  Future<void> _showActions(Offset? position) async {
    final picked = await showCircleActionMenu<MediaTileAction>(
      context,
      title: widget.post.title,
      position: position,
      items: [
        for (final action in widget.actions)
          CircleMenuItem(value: action, icon: action.icon, label: action.label),
      ],
    );
    picked?.onSelected();
  }

  String _summary() {
    final post = widget.post;
    final replies = switch (post.replyCount) {
      0 => tr('No replies'),
      1 => tr('1 reply'),
      final count => tr('{count} replies', {'count': count}),
    };
    final description = post.thumbnail?.alt;
    return [
      post.title,
      tr('Posted by {name}', {'name': post.author?.name ?? tr('Deleted user')}),
      replies,
      if (post.unreadCount > 0) tr('Unread'),
      if (post.isPinned) tr('Pinned'),
      ?description,
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final post = widget.post;
    final radius = BorderRadius.circular(WeCordRadii.lg);
    final unread = post.unreadCount > 0;
    final touch = usesTouchInput(context);
    final replyCount = post.replyCount;

    final placeholder = ColoredBox(
      color: c.raised,
      child: Center(child: Icon(Icons.image_outlined, color: c.faint)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        return ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Semantics(
                container: true,
                button: true,
                label: _summary(),
                onTap: widget.onTap,
                child: ExcludeSemantics(
                  child: WeCordPressable(
                    onPressed: widget.onTap,
                    pressedScale: 0.98,
                    shape: RoundedRectangleBorder(borderRadius: radius),
                    builder: (context, states) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          FutureBuilder<String>(
                            future: _url,
                            builder: (context, snapshot) {
                              final url = snapshot.data;
                              if (url == null) {
                                return placeholder;
                              }
                              return Image(
                                key: const ValueKey('media-wall-picture'),
                                image: avatarImageFor(
                                  NetworkImage(url),
                                  size: size,
                                  devicePixelRatio:
                                      MediaQuery.devicePixelRatioOf(context),
                                ),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (context, error, stackTrace) {
                                  _resignAfterError();
                                  return placeholder;
                                },
                              );
                            },
                          ),
                          // The shade the title sits on.
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  // Dark enough under the words that they read on a
                                  // white picture too.
                                  stops: const [0, 0.3, 1],
                                  colors: [
                                    Colors.black.withValues(alpha: 0),
                                    Colors.black.withValues(alpha: 0.74),
                                    Colors.black.withValues(alpha: 0.78),
                                  ],
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  22,
                                  10,
                                  8,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      post.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        height: 1.2,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            post.author?.name ??
                                                tr('Deleted user'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: Color(0xFFE8E8EC),
                                            ),
                                          ),
                                        ),
                                        if (replyCount > 0) ...[
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.chat_bubble_outline_rounded,
                                            size: 12,
                                            color: Color(0xFFE8E8EC),
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '$replyCount',
                                            key: const ValueKey(
                                              'media-wall-replies',
                                            ),
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFE8E8EC),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (post.isPinned)
                            Positioned(
                              left: 8,
                              top: 8,
                              child: _Chip(
                                key: const ValueKey('media-wall-pinned'),
                                child: Icon(
                                  Icons.push_pin_rounded,
                                  size: 14,
                                  color: c.accentText,
                                ),
                              ),
                            ),
                          if (unread)
                            Positioned(
                              left: post.isPinned ? 40 : 8,
                              top: 8,
                              child: _Chip(
                                key: const ValueKey('media-wall-unread'),
                                child: Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: c.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              if (widget.actions.isNotEmpty)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Builder(
                    builder: (buttonContext) {
                      final box = touch ? minTouchTargetSize : 32.0;
                      return Tooltip(
                        message: tr('Post options'),
                        child: Semantics(
                          button: true,
                          label: tr('Post options'),
                          child: ExcludeSemantics(
                            child: InkResponse(
                              key: const ValueKey('media-wall-options'),
                              onTap: () {
                                final renderBox =
                                    buttonContext.findRenderObject()
                                        as RenderBox?;
                                unawaited(
                                  _showActions(
                                    renderBox?.localToGlobal(
                                      renderBox.size.bottomRight(Offset.zero),
                                    ),
                                  ),
                                );
                              },
                              child: SizedBox(
                                width: box,
                                height: box,
                                child: Center(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.42,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.more_horiz_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.tokens.colors.panel.withValues(alpha: 0.92),
        shape: BoxShape.circle,
      ),
      child: child,
    );
  }
}
