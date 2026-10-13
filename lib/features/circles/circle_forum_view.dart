import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/circles/circle_roles_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/circles/forum_post_composer_sheet.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/forum.dart';
import 'package:wecord/shared/models/message.dart';

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
          failure: 'Could not change the pin. Try again.',
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
          failure: 'Could not change the tags. Try again.',
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
          failure: 'Could not archive the post. Try again.',
        );
    }
  }

  void _showTopic(String topic) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(_channel.name),
        content: SelectableText(topic),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(8),
          child: CircleAvatar(child: Icon(Icons.forum_outlined)),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (topic != null && topic.isNotEmpty)
              InkWell(
                key: const ValueKey('forum-topic'),
                onTap: () => _showTopic(topic),
                child: Text(
                  topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              )
            else
              Text('Forum', style: theme.textTheme.labelSmall),
          ],
        ),
        actions: [for (final action in widget.actions) action.toIconButton()],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            // Phones show the sort as an icon; its menu names the choices.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 420;
                return Row(
                  children: [
                    if (canPost)
                      Flexible(
                        child: FilledButton.icon(
                          key: const ValueKey('forum-new-post'),
                          onPressed: _newPost,
                          icon: const Icon(Icons.add),
                          label: const Text(
                            'New post',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: Text(
                          'You cannot post in this forum.',
                          key: const ValueKey('forum-read-only'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (canPost) const Spacer(),
                    const SizedBox(width: 8),
                    PopupMenuButton<ForumPostSort>(
                      key: const ValueKey('forum-sort-button'),
                      tooltip: 'Sort posts: ${_sort.label}',
                      initialValue: _sort,
                      onSelected: _setSort,
                      itemBuilder: (context) => [
                        for (final sort in ForumPostSort.values)
                          CheckedPopupMenuItem(
                            value: sort,
                            checked: sort == _sort,
                            child: Text(sort.label),
                          ),
                      ],
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: usesTouchInput(context)
                              ? minTouchTargetSize
                              : 36,
                          minWidth: usesTouchInput(context)
                              ? minTouchTargetSize
                              : 36,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.sort, size: 20),
                            if (!compact) ...[
                              const SizedBox(width: 4),
                              Text(
                                _sort.label,
                                style: theme.textTheme.labelLarge,
                              ),
                            ],
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_channel.tags.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                key: const ValueKey('forum-tag-filters'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final tag in _channel.tags)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        key: ValueKey('forum-tag-filter-${tag.id}'),
                        label: Text(tag.label),
                        selected: tag.id == _tagId,
                        onSelected: (selected) =>
                            _setTag(selected ? tag.id : null),
                      ),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _buildList(canPin: canPin, canPost: canPost),
          ),
        ],
      ),
    );
  }

  Widget _buildList({required bool canPin, required bool canPost}) {
    final theme = Theme.of(context);
    if (_posts.isEmpty) {
      if (_error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load posts.'),
              TextButton(onPressed: _loadMore, child: const Text('Retry')),
            ],
          ),
        );
      }
      if (_loading || _hasMore) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                _tagId == null ? 'No posts yet' : 'No posts with this tag',
                style: theme.textTheme.titleMedium,
              ),
              if (canPost && _tagId == null)
                Text(
                  'Start the first conversation with New post.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('forum-post-list'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: _posts.length + 1,
      itemBuilder: (context, index) {
        if (index == _posts.length) {
          if (_error != null) {
            return Center(
              child: TextButton(
                onPressed: _loadMore,
                child: const Text('Could not load more. Retry'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final unread = post.unreadCount > 0;
    final snippet = plainTextFromMarkdown(
      post.body,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    final author = post.author;
    final replies = switch (post.replyCount) {
      0 => 'No replies',
      1 => '1 reply',
      final count => '$count replies',
    };
    final thumbnail = post.thumbnail;

    return Material(
      key: ValueKey('forum-post-${post.id}'),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post.isPinned || post.isArchived)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            if (post.isPinned)
                              _Badge(
                                key: const ValueKey('forum-post-pinned'),
                                icon: Icons.push_pin,
                                label: 'Pinned',
                                color: colorScheme.primary,
                              ),
                            if (post.isArchived)
                              _Badge(
                                icon: Icons.archive_outlined,
                                label: 'Archived',
                                color: colorScheme.onSurfaceVariant,
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
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
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
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      author?.name ?? 'Deleted user',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: switch (author?.roleColor) {
                          final color? => circleRoleColor(color),
                          null => colorScheme.onSurfaceVariant,
                        },
                      ),
                    ),
                    if (post.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
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
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '$replies · '
                            '${formatThreadActivity(post.lastActivityAt, now: now)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: unread
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: unread ? FontWeight.w700 : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (thumbnail != null) ...[
                const SizedBox(width: 10),
                ForumThumbnail(attachment: thumbnail),
              ],
              if (actions.isNotEmpty && onAction != null)
                PopupMenuButton<ForumPostAction>(
                  tooltip: 'Post options',
                  icon: const Icon(Icons.more_vert),
                  onSelected: onAction,
                  itemBuilder: (context) => [
                    for (final action in actions)
                      PopupMenuItem(
                        value: action,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(action.icon),
                          title: Text(action.label),
                        ),
                      ),
                  ],
                )
              else
                const SizedBox(width: 10),
            ],
          ),
        ),
      ),
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
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        tag.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.image_outlined),
    );
    return ClipRRect(
      key: const ValueKey('forum-post-thumbnail'),
      borderRadius: BorderRadius.circular(8),
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
            errorBuilder: (context, error, stackTrace) => placeholder,
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
  return showDialog<List<String>>(
    context: context,
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
    return AlertDialog(
      scrollable: true,
      title: const Text('Edit tags'),
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop([
            for (final tag in widget.tags)
              if (_selected.contains(tag.id)) tag.id,
          ]),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Filter chips for choosing up to [ForumTag.maxPerPost] tags.
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
    final full = selected.length >= ForumTag.maxPerPost;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final tag in tags)
              FilterChip(
                key: ValueKey('forum-tag-choice-${tag.id}'),
                label: Text(tag.label),
                selected: selected.contains(tag.id),
                onSelected: !enabled || (full && !selected.contains(tag.id))
                    ? null
                    : (value) => onChanged(
                        value
                            ? {...selected, tag.id}
                            : ({...selected}..remove(tag.id)),
                      ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Up to ${ForumTag.maxPerPost} tags · ${selected.length} chosen',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
