import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_feed_view.dart';
import 'package:wecord/features/circles/circle_post_tile.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';

/// A circle's posts on a page of their own, filtered by a topic or to the
/// featured ones (a link from the search or a featured tab).
class CirclePostsScreen extends ConsumerWidget {
  const CirclePostsScreen({
    required this.circleId,
    this.tag,
    this.featuredOnly = false,
    this.embedded = false,
    super.key,
  });

  final String circleId;
  final String? tag;
  final bool featuredOnly;

  /// Inside a tab: no page title bar of its own.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(circleDetailProvider(circleId));
    final body = detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => CircleEmptyState(
        icon: Icons.error_outline_rounded,
        title: tr('Could not load the circle.'),
        message: errorText(error),
      ),
      data: (detail) => CircleFeedView(
        key: ValueKey('posts-$circleId-$tag-$featuredOnly'),
        circleId: circleId,
        posts: detail.posts,
        onChanged: () => ref.invalidate(circleDetailProvider(circleId)),
        initialTag: tag,
        initialFeaturedOnly: featuredOnly,
        showComposer: !embedded && tag == null && !featuredOnly,
      ),
    );
    if (embedded) {
      return body;
    }
    return CirclePageScaffold(
      title: tag != null
          ? '#$tag'
          : featuredOnly
          ? tr('Featured')
          : tr('Feed'),
      subtitle: detail.asData?.value.circle.name,
      constrainBody: false,
      body: body,
    );
  }
}

/// One post of a circle with all its comments (a link from a push, the grid
/// or the search).
class CirclePostDetailScreen extends ConsumerWidget {
  const CirclePostDetailScreen({
    required this.circleId,
    required this.postId,
    super.key,
  });

  final String circleId;
  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(circleDetailProvider(circleId));
    void refresh() => ref.invalidate(circleDetailProvider(circleId));
    return CirclePageScaffold(
      title: tr('Post'),
      subtitle: detail.asData?.value.circle.name,
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => CircleEmptyState(
          icon: Icons.error_outline_rounded,
          title: tr('Could not load the circle.'),
          message: errorText(error),
        ),
        data: (detail) {
          CirclePost? post;
          for (final candidate in detail.posts) {
            if (candidate.id == postId) {
              post = candidate;
            }
          }
          if (post == null) {
            return CircleEmptyState(
              icon: Icons.article_outlined,
              title: tr('This post is not available.'),
              message: tr('It may have been deleted.'),
            );
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(
              12,
              4,
              12,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              CirclePostTile(
                post: post,
                onChanged: refresh,
                commentLimit: null,
                onOpenTag: (tag) =>
                    context.push(circlePostsPath(circleId, tag: tag)),
              ),
            ],
          );
        },
      ),
    );
  }
}
