import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/media_cache.dart';
import 'package:wecord/features/circles/circle_post_tile.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/display_size_image.dart';
import 'package:wecord/shared/ui/ui.dart';

/// One post in the grid view of a circle's feed: the picture as the cover
/// (or the first words on a quiet tile when there is none), the title, who
/// wrote it and the likes. Pressing it opens the post.
class CirclePostGridCard extends ConsumerWidget {
  const CirclePostGridCard({
    required this.post,
    required this.onOpen,
    super.key,
  });

  final CirclePost post;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final image = post.imageAttachment;
    final label = [
      if (post.isFeatured) tr('Featured post'),
      post.headline,
      post.author.displayLabel,
      tr('{count} likes', {'count': post.likeCount}),
    ].join(', ');
    return WeCordPressable(
      onPressed: onOpen,
      semanticLabel: label,
      excludeSemantics: true,
      hint: tr('Opens the post'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      builder: (context, states) => DecoratedBox(
        decoration: BoxDecoration(
          color: c.well,
          borderRadius: BorderRadius.circular(WeCordRadii.xl),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WeCordRadii.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (image != null)
                      _GridCover(attachment: image)
                    else
                      _TextCover(post: post),
                    if (post.isFeatured)
                      const Positioned(left: 8, top: 8, child: FeaturedBadge()),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        CircleNetworkAvatar(
                          name: post.author.displayLabel,
                          url: post.author.avatarUrl,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            post.author.displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.muted,
                            ),
                          ),
                        ),
                        Icon(
                          post.likedByCurrentUser
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 14,
                          color: post.likedByCurrentUser ? c.accent : c.muted,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${post.likeCount}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: c.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The first words of a post without a picture.
class _TextCover extends StatelessWidget {
  const _TextCover({required this.post});

  final CirclePost post;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ColoredBox(
      color: c.raised,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 30, 12, 10),
        child: Text(
          post.body.isEmpty ? post.headline : post.body,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, height: 1.4, color: c.muted),
        ),
      ),
    );
  }
}

class _GridCover extends ConsumerStatefulWidget {
  const _GridCover({required this.attachment});

  final ImageAttachment attachment;

  @override
  ConsumerState<_GridCover> createState() => _GridCoverState();
}

class _GridCoverState extends ConsumerState<_GridCover> {
  late Future<String> _url;

  @override
  void initState() {
    super.initState();
    _url = _sign();
  }

  @override
  void didUpdateWidget(covariant _GridCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.path != widget.attachment.path ||
        oldWidget.attachment.bucket != widget.attachment.bucket) {
      _url = _sign();
    }
  }

  Future<String> _sign() {
    final attachment = widget.attachment;
    return ref
        .read(chatSignedUrlCacheProvider)
        .get(
          SignedUrlCache.keyFor(attachment.bucket, attachment.path),
          () => ref.read(circlesRepositoryProvider).createImageUrl(attachment),
        );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return ColoredBox(
            color: c.raised,
            child: Center(
              child: snapshot.hasError
                  ? Icon(Icons.image_not_supported_outlined, color: c.faint)
                  : const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) => Image(
            image: imageDecodedFor(
              NetworkImage(snapshot.data!),
              box: Size(
                constraints.hasBoundedWidth ? constraints.maxWidth : 240,
                constraints.hasBoundedHeight ? constraints.maxHeight : 180,
              ),
              devicePixelRatio: dpr,
              sourceWidth: widget.attachment.width,
              sourceHeight: widget.attachment.height,
            ),
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        );
      },
    );
  }
}
