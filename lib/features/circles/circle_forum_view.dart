import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/circles/circle_roles_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/circles/forum_post_composer_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/forum.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A forum channel: its posts as cards, newest activity (or newest post)
/// first with pinned posts on top, filtered by tag, loading more while
/// scrolling. Members who can send messages start new posts; tapping a post
/// opens it through [onOpenPost].
class CircleForumView extends ConsumerStatefulWidget {
  const CircleForumView({
    required this.detail,
    required this.channel,
    required this.onOpenPost,
    this.actions = const [],
    this.pageSize = 25,
    super.key,
  });

  final CircleDetail detail;
  final CircleChannel channel;

  /// Opens a post; the list reloads once the returned future completes.
  final Future<void> Function(ForumPost post) onOpenPost;

  /// App bar actions after the built-in ones.
  final List<ChatThreadAction> actions;
  final int pageSize;

  @override
  ConsumerState<CircleForumView> createState() => _CircleForumViewState();
}

class _CircleForumViewState extends ConsumerState<CircleForumView> {
  final _scrollController = ScrollController();
  final _posts = <ForumPost>[];
  var _sort = ForumPostSort.activity;
  String? _tagId;
  var _loading = false;
  var _hasMore = true;
  Object? _error;
  StreamSubscription<void>? _changes;
  Timer? _reloadTimer;

  /// Bumped on every reload, so pages of an old query are dropped.
  var _generation = 0;

  CircleChannel get _channel => widget.channel;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    _listen();
    _loadMore();
  }

  @override
  void didUpdateWidget(CircleForumView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != _channel.id) {
      _listen();
      _restart();
    } else if (_tagId != null && !_channel.tags.any((t) => t.id == _tagId)) {
      // The filtered tag was deleted.
      _setTag(null);
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    _reloadTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _listen() {
    _changes?.cancel();
    _changes = ref
        .read(circlesRepositoryProvider)
        .forumChanges(
          channelId: _channel.id,
          conversationId: _channel.conversationId,
        )
        .listen((_) {
          // Replies arrive in bursts; reload once they settle.
          _reloadTimer?.cancel();
          _reloadTimer = Timer(const Duration(milliseconds: 300), _reload);
        });
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  ForumPostCursor? get _cursor {
    for (final post in _posts.reversed) {
      if (!post.isPinned) {
        return post.cursorFor(_sort);
      }
    }
    return null;
  }

  int get _unpinnedCount => _posts.where((post) => !post.isPinned).length;

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) {
      return;
    }
    final generation = _generation;
    final cursor = _cursor;
    // Pinned posts come with the first page only.
    final first = _posts.isEmpty;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(circlesRepositoryProvider)
          .listForumPosts(
            channelId: _channel.id,
            sort: _sort,
            tagId: _tagId,
            before: first ? null : cursor,
            limit: widget.pageSize,
          );
      if (!mounted || generation != _generation) {
        return;
      }
      final known = {for (final post in _posts) post.id};
      setState(() {
        _posts.addAll(page.where((post) => !known.contains(post.id)));
        _hasMore =
            page.where((post) => !post.isPinned).length >= widget.pageSize;
        _loading = false;
      });
      // A short first page may not fill the screen enough to scroll.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _maybeLoadMore();
        }
      });
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// Reloads what is listed, keeping as many posts as were loaded.
  Future<void> _reload() async {
    if (!mounted) {
      return;
    }
    final generation = ++_generation;
    final limit = _unpinnedCount.clamp(widget.pageSize, 100);
    try {
      final page = await ref
          .read(circlesRepositoryProvider)
          .listForumPosts(
            channelId: _channel.id,
            sort: _sort,
            tagId: _tagId,
            limit: limit,
          );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _posts
          ..clear()
          ..addAll(page);
        _hasMore = page.where((post) => !post.isPinned).length >= limit;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      // Keep what is shown; the next change or scroll tries again.
    }
  }

  void _restart() {
    setState(() {
      _generation += 1;
      _posts.clear();
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _loadMore();
  }

  void _setSort(ForumPostSort sort) {
    if (sort == _sort) {
      return;
    }
    _sort = sort;
    _restart();
  }

  void _setTag(String? tagId) {
    if (tagId == _tagId) {
      return;
    }
    _tagId = tagId;
    _restart();
  }

  Future<void> _open(ForumPost post) async {
    await widget.onOpenPost(post);
    // Opening marks the post read.
    await _reload();
  }

  Future<void> _newPost() async {
    final post = await showForumPostComposer(context, channel: _channel);
    if (post == null || !mounted) {
      return;
    }
    unawaited(_reload());
    await _open(post);
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String failure,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
      await _reload();
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  Future<void> _onPostAction(ForumPost post, ForumPostAction action) async {
    switch (action) {
      case ForumPostAction.pin:
      case ForumPostAction.unpin:
        await _run(
          () => ref
              .read(circlesRepositoryProvider)
              .pinForumPost(
                threadId: post.id,
                pinned: action == ForumPostAction.pin,
              ),
          failure: tr('Could not change the pin. Try again.'),
        );
      case ForumPostAction.editTags:
        final tagIds = await showForumTagPicker(
          context,
          tags: _channel.tags,
          selected: {for (final tag in post.tags) tag.id},
        );
        if (tagIds == null || !mounted) {
          return;
        }
        await _run(
          () => ref
              .read(circlesRepositoryProvider)
              .setForumPostTags(threadId: post.id, tagIds: tagIds),
          failure: tr('Could not change the tags. Try again.'),
        );
      case ForumPostAction.archive:
      case ForumPostAction.unarchive:
        await _run(
          () => ref
              .read(chatsRepositoryProvider)
              .setThreadArchived(
                threadId: post.id,
                archived: action == ForumPostAction.archive,
              ),
          failure: tr('Could not archive the post. Try again.'),
        );
    }
  }

  void _showTopic(String topic) {
    showCircleDialog<void>(
      context,
      builder: (context) => CircleDialog(
        title: _channel.name,
        content: SelectableText(
          topic,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.45,
            color: context.tokens.colors.ink,
          ),
        ),
        actions: [
          CircleDialogAction(
            label: tr('Close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSort(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    final sort = await showCircleActionMenu<ForumPostSort>(
      context,
      title: tr('Sort posts'),
      position: box?.localToGlobal(box.size.bottomRight(Offset.zero)),
      items: [
        for (final sort in ForumPostSort.values)
          CircleMenuItem(
            value: sort,
            icon: sort == _sort
                ? Icons.check_rounded
                : switch (sort) {
                    ForumPostSort.activity => Icons.bolt_rounded,
                    ForumPostSort.created => Icons.schedule_rounded,
                  },
            tone: sort == _sort ? SettingsTone.accent : SettingsTone.neutral,
            label: tr(sort.label),
          ),
      ],
    );
    if (sort != null && mounted) {
      _setSort(sort);
    }
  }

  /// The title block as a button that shows the whole [topic], when the
  /// forum has one.
  Widget _topicButton(String? topic, Widget title) {
    if (topic == null || topic.isEmpty) {
      return title;
    }
    return WeCordPressable(
      key: const ValueKey('forum-topic'),
      onPressed: () => _showTopic(topic),
      hint: tr('Shows the topic'),
      pressedScale: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.sm),
      ),
      builder: (context, states) =>
          Align(alignment: Alignment.centerLeft, widthFactor: 1, child: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final touch = usesTouchInput(context);
    final detail = widget.detail;
    final canPost = detail.canInChannel(
      _channel,
      CirclePermission.sendMessages,
    );
    final canPin = detail.canInChannel(
      _channel,
      CirclePermission.manageMessages,
    );
    final topic = _channel.topic?.trim();
    final subtitleStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      color: c.muted,
    );

    return Scaffold(
      backgroundColor: c.panel,
      appBar: AppBar(
        backgroundColor: c.panel,
        toolbarHeight: 58,
        leadingWidth: 60,
        shape: Border(bottom: BorderSide(color: c.lineSoft)),
        leading: Center(
          child: ThingAvatar(
            icon: Icons.forum_outlined,
            size: 36,
            color: c.raised,
            foregroundColor: c.ink,
          ),
        ),
        titleSpacing: 4,
        title: _topicButton(
          topic,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              if (topic != null && topic.isNotEmpty)
                Text(
                  topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleStyle,
                )
              else
                Text(tr('Forum'), style: subtitleStyle),
            ],
          ),
        ),
        actions: [
          for (final action in widget.actions) action.toIconButton(),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
            // Phones show the sort as an icon; its menu names the choices.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 420;
                return Row(
                  children: [
                    if (canPost)
                      Flexible(
                        child: WeCordButton(
                          key: const ValueKey('forum-new-post'),
                          variant: WeCordButtonVariant.accent,
                          size: touch
                              ? WeCordButtonSize.medium
                              : WeCordButtonSize.small,
                          onPressed: _newPost,
                          icon: Icons.add_rounded,
                          label: tr('New post'),
                        ),
                      )
                    else
                      Expanded(
                        child: Text(
                          tr('You cannot post in this forum.'),
                          key: const ValueKey('forum-read-only'),
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                      ),
                    if (canPost) const Spacer(),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (buttonContext) => WeCordPressable(
                        key: const ValueKey('forum-sort-button'),
                        tooltip: tr('Sort posts: {sort}', {
                          'sort': tr(_sort.label),
                        }),
                        onPressed: () => _pickSort(buttonContext),
                        builder: (context, states) {
                          final hovered = states.contains(WidgetState.hovered);
                          return ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: touch ? minTouchTargetSize : 32,
                              minWidth: touch ? minTouchTargetSize : 32,
                            ),
                            child: Center(
                              widthFactor: 1,
                              child: AnimatedContainer(
                                duration: WeCordMotion.quick,
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                decoration: ShapeDecoration(
                                  color: hovered
                                      ? Color.alphaBlend(
                                          c.ink.withValues(alpha: 0.05),
                                          c.raised,
                                        )
                                      : c.raised,
                                  shape: const StadiumBorder(),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.sort_rounded,
                                      size: 17,
                                      color: c.ink,
                                    ),
                                    if (!compact) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        tr(_sort.label),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: c.ink,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.expand_more_rounded,
                                      size: 17,
                                      color: c.muted,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_channel.tags.isNotEmpty)
            SizedBox(
              height: touch ? 62 : 44,
              child: ListView(
                key: const ValueKey('forum-tag-filters'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                children: [
                  for (final tag in _channel.tags)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Center(
                        child: WeCordChip(
                          key: ValueKey('forum-tag-filter-${tag.id}'),
                          label: tag.label,
                          height: 32,
                          selected: tag.id == _tagId,
                          onPressed: () =>
                              _setTag(tag.id == _tagId ? null : tag.id),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _buildList(canPin: canPin, canPost: canPost),
          ),
        ],
      ),
    );
  }

  Widget _buildList({required bool canPin, required bool canPost}) {
    if (_posts.isEmpty) {
      if (_error != null) {
        return CircleEmptyState(
          icon: Icons.forum_outlined,
          title: tr('Could not load posts.'),
          action: WeCordButton(
            label: tr('Retry'),
            variant: WeCordButtonVariant.secondary,
            onPressed: _loadMore,
          ),
        );
      }
      if (_loading || _hasMore) {
        return const Center(child: CircularProgressIndicator());
      }
      return CircleEmptyState(
        icon: Icons.forum_outlined,
        title: _tagId == null
            ? tr('No posts yet')
            : tr('No posts with this tag'),
        message: canPost && _tagId == null
            ? tr('Start the first conversation with New post.')
            : null,
      );
    }
    return ListView.builder(
      key: const ValueKey('forum-post-list'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      itemCount: _posts.length + 1,
      itemBuilder: (context, index) {
        if (index == _posts.length) {
          if (_error != null) {
            return Center(
              child: WeCordButton(
                label: tr('Could not load more. Retry'),
                variant: WeCordButtonVariant.ghost,
                onPressed: _loadMore,
              ),
            );
          }
          if (_hasMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return const SizedBox(height: 16);
        }
        final post = _posts[index];
        final actions = [
          if (canPin)
            post.isPinned ? ForumPostAction.unpin : ForumPostAction.pin,
          if (post.canManage && _channel.tags.isNotEmpty)
            ForumPostAction.editTags,
          if (post.canManage)
            post.isArchived
                ? ForumPostAction.unarchive
                : ForumPostAction.archive,
        ];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ForumPostCard(
            post: post,
            onTap: () => _open(post),
            actions: actions,
            onAction: (action) => _onPostAction(post, action),
          ),
        );
      },
    );
  }
}

/// What can be done to a post from its card.
enum ForumPostAction {
  pin('Pin post', Icons.push_pin_outlined),
  unpin('Unpin post', Icons.push_pin),
  editTags('Edit tags', Icons.sell_outlined),
  archive('Archive post', Icons.archive_outlined),
  unarchive('Unarchive post', Icons.unarchive_outlined);

  const ForumPostAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// A post in a forum's list: title, author, tags, the start of its body,
/// reply count and last activity, with the first image as a thumbnail.
class ForumPostCard extends StatelessWidget {
  const ForumPostCard({
    required this.post,
    required this.onTap,
    this.actions = const [],
    this.onAction,
    this.now,
    super.key,
  });

  final ForumPost post;
  final VoidCallback onTap;
  final List<ForumPostAction> actions;
  final ValueChanged<ForumPostAction>? onAction;

  /// The current time, for tests.
  final DateTime? now;

  Future<void> _showActions(BuildContext context, Offset? position) async {
    final action = await showCircleActionMenu<ForumPostAction>(
      context,
      title: post.title,
      position: position,
      items: [
        for (final action in actions)
          CircleMenuItem(
            value: action,
            icon: action.icon,
            label: tr(action.label),
          ),
      ],
    );
    if (action != null) {
      onAction?.call(action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final unread = post.unreadCount > 0;
    final snippet = plainTextFromMarkdown(
      post.body,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    final author = post.author;
    final replies = switch (post.replyCount) {
      0 => tr('No replies'),
      1 => tr('1 reply'),
      final count => tr('{count} replies', {'count': count}),
    };
    final thumbnail = post.thumbnail;
    final radius = BorderRadius.circular(18);
    final hasMenu = actions.isNotEmpty && onAction != null;

    return WeCordPressable(
      key: ValueKey('forum-post-${post.id}'),
      onPressed: onTap,
      pressedScale: 0.99,
      shape: RoundedRectangleBorder(borderRadius: radius),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: EdgeInsets.fromLTRB(14, 12, hasMenu ? 4 : 14, 12),
          decoration: BoxDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.03), c.well)
                : c.well,
            borderRadius: radius,
            border: Border.all(
              color: unread ? c.accent.withValues(alpha: 0.35) : c.well,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post.isPinned || post.isArchived)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            if (post.isPinned)
                              _Badge(
                                key: const ValueKey('forum-post-pinned'),
                                icon: Icons.push_pin_rounded,
                                label: tr('Pinned'),
                                color: c.accentText,
                              ),
                            if (post.isArchived)
                              _Badge(
                                icon: Icons.archive_outlined,
                                label: tr('Archived'),
                                color: c.muted,
                              ),
                          ],
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            post.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15.5,
                              letterSpacing: -0.2,
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                        ),
                        if (unread)
                          Padding(
                            padding: const EdgeInsets.only(left: 6, top: 6),
                            child: Container(
                              key: const ValueKey('forum-post-unread'),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: c.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      author?.name ?? tr('Deleted user'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: switch (author?.roleColor) {
                          final color? => circleRoleColor(color),
                          null => c.muted,
                        },
                      ),
                    ),
                    if (post.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final tag in post.tags) ForumTagLabel(tag: tag),
                        ],
                      ),
                    ],
                    if (snippet.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: c.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 14,
                          color: unread ? c.accentText : c.subtle,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '$replies · '
                            '${formatThreadActivity(post.lastActivityAt, now: now)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: unread ? c.accentText : c.muted,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (thumbnail != null) ...[
                const SizedBox(width: 12),
                ForumThumbnail(attachment: thumbnail),
              ],
              if (hasMenu)
                Builder(
                  builder: (buttonContext) => WeCordIconButton(
                    tooltip: tr('Post options'),
                    icon: Icons.more_horiz_rounded,
                    variant: WeCordButtonVariant.ghost,
                    size: 32,
                    iconSize: 18,
                    onPressed: () {
                      final box =
                          buttonContext.findRenderObject() as RenderBox?;
                      _showActions(
                        context,
                        box?.localToGlobal(box.size.bottomRight(Offset.zero)),
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

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// A small tag pill.
class ForumTagLabel extends StatelessWidget {
  const ForumTagLabel({required this.tag, super.key});

  final ForumTag tag;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: ShapeDecoration(
        color: c.raised,
        shape: const StadiumBorder(),
      ),
      child: Text(
        tag.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: c.ink,
        ),
      ),
    );
  }
}

/// A post's first image, as a small square.
class ForumThumbnail extends ConsumerStatefulWidget {
  const ForumThumbnail({required this.attachment, this.size = 64, super.key});

  final ImageAttachment attachment;
  final double size;

  @override
  ConsumerState<ForumThumbnail> createState() => _ForumThumbnailState();
}

class _ForumThumbnailState extends ConsumerState<ForumThumbnail> {
  late Future<String> _url = _load();

  /// Whether the URL was signed again after the image failed to load.
  bool _resigned = false;

  /// The signed URL may have expired while the list stayed open: sign it
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

  Future<String> _load() {
    return ref
        .read(circlesRepositoryProvider)
        .createImageUrl(widget.attachment);
  }

  @override
  void didUpdateWidget(ForumThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.path != widget.attachment.path ||
        oldWidget.attachment.bucket != widget.attachment.bucket) {
      _url = _load();
      _resigned = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final c = context.tokens.colors;
    final placeholder = Container(
      width: size,
      height: size,
      color: c.raised,
      child: Icon(Icons.image_outlined, color: c.faint),
    );
    return ClipRRect(
      key: const ValueKey('forum-post-thumbnail'),
      borderRadius: BorderRadius.circular(WeCordRadii.sm),
      child: FutureBuilder<String>(
        future: _url,
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url == null) {
            return placeholder;
          }
          return Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              _resignAfterError();
              return placeholder;
            },
          );
        },
      ),
    );
  }
}

/// Picks up to [ForumTag.maxPerPost] of a forum's [tags]. Returns the
/// chosen ids in the forum's order, or null when cancelled.
Future<List<String>?> showForumTagPicker(
  BuildContext context, {
  required List<ForumTag> tags,
  required Set<String> selected,
}) {
  return showCircleDialog<List<String>>(
    context,
    builder: (context) => _ForumTagPickerDialog(tags: tags, selected: selected),
  );
}

class _ForumTagPickerDialog extends StatefulWidget {
  const _ForumTagPickerDialog({required this.tags, required this.selected});

  final List<ForumTag> tags;
  final Set<String> selected;

  @override
  State<_ForumTagPickerDialog> createState() => _ForumTagPickerDialogState();
}

class _ForumTagPickerDialogState extends State<_ForumTagPickerDialog> {
  late final _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: tr('Edit tags'),
      content: ForumTagSelector(
        tags: widget.tags,
        selected: _selected,
        onChanged: (selected) => setState(() {
          _selected
            ..clear()
            ..addAll(selected);
        }),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          label: tr('Save'),
          onPressed: () => Navigator.of(context).pop([
            for (final tag in widget.tags)
              if (_selected.contains(tag.id)) tag.id,
          ]),
        ),
      ],
    );
  }
}

/// Chips for choosing up to [ForumTag.maxPerPost] tags.
class ForumTagSelector extends StatelessWidget {
  const ForumTagSelector({
    required this.tags,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final List<ForumTag> tags;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final full = selected.length >= ForumTag.maxPerPost;
    final height = usesTouchInput(context) ? minTouchTargetSize : 34.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in tags)
              Opacity(
                opacity: !enabled || (full && !selected.contains(tag.id))
                    ? 0.45
                    : 1,
                child: WeCordChip(
                  key: ValueKey('forum-tag-choice-${tag.id}'),
                  label: tag.label,
                  height: height,
                  icon: selected.contains(tag.id) ? Icons.check_rounded : null,
                  selected: selected.contains(tag.id),
                  onPressed: !enabled || (full && !selected.contains(tag.id))
                      ? null
                      : () => onChanged(
                          selected.contains(tag.id)
                              ? ({...selected}..remove(tag.id))
                              : {...selected, tag.id},
                        ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          tr('Up to {max} tags · {count} chosen', {
            'max': ForumTag.maxPerPost,
            'count': selected.length,
          }),
          style: TextStyle(fontSize: 12.5, color: c.muted),
        ),
      ],
    );
  }
}
