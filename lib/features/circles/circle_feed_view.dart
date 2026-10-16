import 'package:flutter/material.dart';
import 'package:wecord/features/circles/circle_feed_composer.dart';
import 'package:wecord/features/circles/circle_post_tile.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The circle's feed: the composer card, then each post as a card.
class CircleFeedView extends StatelessWidget {
  const CircleFeedView({
    required this.circleId,
    required this.posts,
    required this.onChanged,
    super.key,
  });

  final String circleId;
  final List<CirclePost> posts;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView.separated(
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: posts.length + 1,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CircleFeedComposer(circleId: circleId, onPosted: onChanged),
                  if (posts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 32, 16, 40),
                      child: Column(
                        children: [
                          ThingAvatar(
                            icon: Icons.dynamic_feed_outlined,
                            size: 56,
                            color: c.raised,
                            foregroundColor: c.muted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr('No posts yet'),
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
            }
            return CirclePostTile(post: posts[index - 1], onChanged: onChanged);
          },
        ),
      ),
    );
  }
}
