import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/media_cache.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/features/moments/moments_video.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/spoken.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A picture of the private bucket: its signed link is fetched (and reused
/// while valid), a quiet block shows meanwhile and when it cannot be read.
class MomentImage extends ConsumerStatefulWidget {
  const MomentImage({
    required this.path,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    this.contain = false,
    super.key,
  });

  final String path;
  final BoxFit fit;
  final String? semanticLabel;

  /// Keeps the whole picture (the full-screen viewer).
  final bool contain;

  @override
  ConsumerState<MomentImage> createState() => _MomentImageState();
}

class _MomentImageState extends ConsumerState<MomentImage> {
  var _retried = false;

  void _retry() {
    if (_retried) {
      return;
    }
    _retried = true;
    // The link may have expired: sign it again once.
    ref
        .read(chatSignedUrlCacheProvider)
        .evict(SignedUrlCache.keyFor(momentsBucket, widget.path));
    ref.invalidate(momentImageUrlProvider(widget.path));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final url = ref.watch(momentImageUrlProvider(widget.path));
    Widget placeholder([IconData? icon]) => ColoredBox(
      color: c.raised,
      child: icon == null
          ? null
          : Center(child: Icon(icon, size: 22, color: c.faint)),
    );
    return url.when(
      loading: placeholder,
      error: (error, stackTrace) => placeholder(Icons.broken_image_outlined),
      data: (url) => Image(
        image: ref.read(momentImageProviderFactory)(url),
        fit: widget.contain ? BoxFit.contain : widget.fit,
        semanticLabel: widget.semanticLabel,
        excludeFromSemantics: widget.semanticLabel == null,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder(),
        errorBuilder: (context, error, stackTrace) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _retry();
            }
          });
          return placeholder(Icons.broken_image_outlined);
        },
      ),
    );
  }
}

/// The pictures of a Moment as a grid of thumbnails: one picture large, two
/// or four in two columns, the rest in three.
class MomentPhotoGrid extends StatelessWidget {
  const MomentPhotoGrid({
    required this.photos,
    required this.onOpen,
    super.key,
  });

  final List<MomentPhoto> photos;
  final ValueChanged<int> onOpen;

  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        Widget tile(int index, double w, double h) {
          return SizedBox(
            key: ValueKey('moment-photo-$index'),
            width: w,
            height: h,
            child: WeCordPressable(
              onPressed: () => onOpen(index),
              pressedScale: 0.98,
              semanticLabel: tr('Photo {number} of {count}', {
                'number': index + 1,
                'count': photos.length,
              }),
              excludeSemantics: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WeCordRadii.sm),
              ),
              builder: (context, states) => ClipRRect(
                borderRadius: BorderRadius.circular(WeCordRadii.sm),
                child: MomentImage(path: photos[index].thumb),
              ),
            ),
          );
        }

        if (photos.length == 1) {
          final ratio = (photos.first.aspectRatio ?? 1.2).clamp(0.7, 1.7);
          final w = width * 0.72;
          final h = (w / ratio).clamp(w * 0.58, w * 1.3);
          return Align(alignment: Alignment.centerLeft, child: tile(0, w, h));
        }
        final columns = photos.length == 2 || photos.length == 4 ? 2 : 3;
        final side = columns == 2
            ? (width * 0.72 - _gap) / 2
            : (width - _gap * 2) / 3;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final (index, _) in photos.indexed) tile(index, side, side),
          ],
        );
      },
    );
  }
}

/// "Name, Name, Name" after a heart: the likes the viewer may see.
class MomentLikesLine extends StatelessWidget {
  const MomentLikesLine({required this.likes, super.key});

  final List<MomentLiker> likes;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.favorite_rounded, size: 15, color: c.accentText),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            likes.map((like) => like.name).join(', '),
            key: const ValueKey('moment-likes-line'),
            style: TextStyle(
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: c.accentText,
            ),
          ),
        ),
      ],
    );
  }
}

/// One comment: "Name: text", or "Name replied Other: text".
class MomentCommentLine extends StatelessWidget {
  const MomentCommentLine({
    required this.comment,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final MomentComment comment;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final nameStyle = TextStyle(
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.w700,
      color: c.accentText,
    );
    final bodyStyle = TextStyle(fontSize: 14, height: 1.4, color: c.ink);
    final spoken = comment.isReply
        ? tr('{name} replied to {other}: {text}', {
            'name': comment.name,
            'other': comment.replyToName ?? '',
            'text': comment.body,
          })
        : tr('{name}: {text}', {'name': comment.name, 'text': comment.body});
    return WeCordPressable(
      onPressed: onTap,
      onLongPress: onLongPress,
      pressedScale: 1,
      semanticLabel: spoken,
      excludeSemantics: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.xs),
      ),
      builder: (context, states) => Container(
        width: double.infinity,
        color: states.contains(WidgetState.hovered)
            ? c.ink.withValues(alpha: 0.04)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: comment.name, style: nameStyle),
              if (comment.isReply) ...[
                TextSpan(
                  text: ' ${tr('replied to')} ',
                  style: bodyStyle.copyWith(color: c.muted),
                ),
                TextSpan(text: comment.replyToName ?? '', style: nameStyle),
              ],
              TextSpan(text: ': ${comment.body}', style: bodyStyle),
            ],
          ),
        ),
      ),
    );
  }
}

/// The likes and comments under a Moment, in a quiet block. With
/// [maxComments] the rest is a "View all" row.
class MomentReactions extends StatelessWidget {
  const MomentReactions({
    required this.post,
    required this.onReply,
    required this.onCommentMenu,
    this.myUserId,
    this.maxComments,
    this.onViewAll,
    super.key,
  });

  final MomentPost post;

  /// Tapping somebody else's comment replies to it; tapping the person's
  /// own opens its menu.
  final String? myUserId;
  final ValueChanged<MomentComment> onReply;
  final ValueChanged<MomentComment> onCommentMenu;
  final int? maxComments;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    if (post.likes.isEmpty && post.comments.isEmpty) {
      return const SizedBox.shrink();
    }
    final shown = maxComments == null
        ? post.comments
        : post.comments.take(maxComments!).toList();
    return Container(
      key: const ValueKey('moment-reactions'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.likes.isNotEmpty) MomentLikesLine(likes: post.likes),
          if (post.likes.isNotEmpty && shown.isNotEmpty)
            Divider(height: 14, thickness: 1, color: c.lineSoft),
          for (final comment in shown)
            MomentCommentLine(
              key: ValueKey('moment-comment-${comment.id}'),
              comment: comment,
              onTap: () => comment.userId == myUserId
                  ? onCommentMenu(comment)
                  : onReply(comment),
              onLongPress: () => onCommentMenu(comment),
            ),
          if (shown.length < post.comments.length && onViewAll != null)
            WeCordPressable(
              key: const ValueKey('moment-view-all-comments'),
              onPressed: onViewAll,
              pressedScale: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WeCordRadii.xs),
              ),
              builder: (context, states) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr('View all {count} comments', {
                    'count': post.comments.length,
                  }),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: c.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A link a Moment shares: a quiet card with the title and address.
class MomentLinkCard extends ConsumerWidget {
  const MomentLinkCard({required this.url, this.title, super.key});

  final String url;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final uri = Uri.tryParse(url);
    final host = uri?.host.isNotEmpty == true ? uri!.host : url;
    final heading = (title?.trim().isNotEmpty ?? false) ? title!.trim() : host;
    return WeCordPressable(
      key: const ValueKey('moment-link'),
      onPressed: uri == null
          ? null
          : () => ref
                .read(linkLauncherProvider)(context, uri)
                .catchError((Object _) {}),
      pressedScale: 0.98,
      semanticLabel: tr('Link: {title}', {'title': heading}),
      excludeSemantics: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.well,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        child: Row(
          children: [
            const SettingsIconTile(
              icon: Icons.link_rounded,
              tone: SettingsTone.accent,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    heading,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A Moment on a white card: who and when, the text, pictures or link, the
/// place, the like and comment buttons and what friends reacted. In the
/// feed [maxComments] limits the comments shown.
class MomentCard extends ConsumerWidget {
  const MomentCard({
    required this.post,
    required this.myUserId,
    required this.onOpenAuthor,
    required this.onOpenPhoto,
    required this.onComment,
    required this.onReply,
    required this.onCommentMenu,
    required this.onDelete,
    required this.onLike,
    this.onOpen,
    this.maxComments,
    super.key,
  });

  final MomentPost post;
  final String? myUserId;
  final VoidCallback onOpenAuthor;
  final ValueChanged<int> onOpenPhoto;
  final VoidCallback onComment;
  final ValueChanged<MomentComment> onReply;
  final ValueChanged<MomentComment> onCommentMenu;
  final VoidCallback onDelete;
  final VoidCallback onLike;

  /// Opens the detail; null on the detail itself.
  final VoidCallback? onOpen;
  final int? maxComments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final mine = post.authorId == myUserId;
    final age = spokenAge(post.createdAt);
    return Container(
      key: ValueKey('moment-${post.id}'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              WeCordPressable(
                key: ValueKey('moment-author-${post.id}'),
                onPressed: onOpenAuthor,
                pressedScale: 0.96,
                semanticLabel: tr("{name}'s Moments", {
                  'name': post.authorName,
                }),
                excludeSemantics: true,
                shape: const CircleBorder(),
                builder: (context, states) => ProfileAvatar(
                  name: post.authorName,
                  avatarUrl: post.authorAvatarUrl,
                  size: 40,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(age, style: TextStyle(fontSize: 12, color: c.subtle)),
                  ],
                ),
              ),
              if (mine && post.visibility != MomentVisibility.friends)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _AudienceChip(visibility: post.visibility),
                ),
            ],
          ),
          if (post.body.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Tappable(
              onTap: onOpen,
              child: SelectableText(
                post.body,
                key: ValueKey('moment-body-${post.id}'),
                style: TextStyle(fontSize: 15.5, height: 1.45, color: c.ink),
              ),
            ),
          ],
          if (post.photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            MomentPhotoGrid(photos: post.photos, onOpen: onOpenPhoto),
          ],
          if (post.video != null) ...[
            const SizedBox(height: 10),
            MomentVideoTile(video: post.video!),
          ],
          if (post.linkUrl != null) ...[
            const SizedBox(height: 10),
            MomentLinkCard(url: post.linkUrl!, title: post.linkTitle),
          ],
          if (post.location != null && post.location!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 15, color: c.subtle),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    post.location!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              _ActionButton(
                key: ValueKey('moment-like-${post.id}'),
                icon: post.likedByMe
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: post.likedByMe ? c.accentText : c.muted,
                label: post.likedByMe ? tr('Unlike') : tr('Like'),
                count: post.likeCount,
                onPressed: onLike,
              ),
              const SizedBox(width: 4),
              _ActionButton(
                key: ValueKey('moment-comment-button-${post.id}'),
                icon: Icons.chat_bubble_outline_rounded,
                color: c.muted,
                label: tr('Comment'),
                count: post.commentCount,
                onPressed: onComment,
              ),
              const Spacer(),
              if (mine)
                WeCordIconButton(
                  key: ValueKey('moment-delete-${post.id}'),
                  icon: Icons.delete_outline_rounded,
                  tooltip: tr('Delete Moment'),
                  variant: WeCordButtonVariant.ghost,
                  size: 36,
                  iconSize: 19,
                  onPressed: onDelete,
                ),
            ],
          ),
          if (post.likes.isNotEmpty || post.comments.isNotEmpty) ...[
            const SizedBox(height: 4),
            MomentReactions(
              post: post,
              myUserId: myUserId,
              maxComments: maxComments,
              onReply: onReply,
              onCommentMenu: onCommentMenu,
              onViewAll: onOpen,
            ),
          ],
        ],
      ),
    );
  }
}

class _Tappable extends StatelessWidget {
  const _Tappable({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onPressed,
      semanticLabel: count > 0 ? '$label, $count' : label,
      excludeSemantics: true,
      builder: (context, states) => Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: ShapeDecoration(
          color: states.contains(WidgetState.hovered)
              ? c.ink.withValues(alpha: 0.05)
              : Colors.transparent,
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: c.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows the author (only) that a Moment is not for every friend.
class _AudienceChip extends StatelessWidget {
  const _AudienceChip({required this.visibility});

  final MomentVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final (icon, label) = switch (visibility) {
      MomentVisibility.private => (Icons.lock_outline_rounded, tr('Only me')),
      MomentVisibility.only => (Icons.group_outlined, tr('Some friends')),
      MomentVisibility.except => (
        Icons.group_off_outlined,
        tr('Hidden from some'),
      ),
      MomentVisibility.friends => (Icons.group_outlined, tr('Friends')),
    };
    return Container(
      key: const ValueKey('moment-audience-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: ShapeDecoration(
        color: c.raised,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.muted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: c.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// The badge on the Moments entry when friends posted since the person
/// last looked: the latest poster's picture on a ring. Nothing when nothing
/// is new.
class MomentsUnseenAvatar extends ConsumerWidget {
  const MomentsUnseenAvatar({
    required this.ringColor,
    this.size = 22,
    super.key,
  });

  final Color ringColor;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unseen = ref.watch(momentsUnseenProvider).value;
    if (unseen == null || unseen.count == 0) {
      return const SizedBox.shrink();
    }
    final name = unseen.latestAuthorName ?? '';
    return Semantics(
      label: unseen.count == 1
          ? tr('New Moment from {name}', {'name': name})
          : tr('{count} new Moments, the latest from {name}', {
              'count': unseen.count,
              'name': name,
            }),
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('moments-unseen-avatar'),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: ringColor, shape: BoxShape.circle),
        child: ProfileAvatar(
          name: name,
          avatarUrl: unseen.latestAuthorAvatarUrl,
          size: size,
        ),
      ),
    );
  }
}
