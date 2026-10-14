import 'package:flutter/material.dart';
import 'package:wecord/features/circles/circle_feed_composer.dart';
import 'package:wecord/features/circles/circle_post_tile.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';

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
    return ListView.separated(
      itemCount: posts.length + 1,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CircleFeedComposer(circleId: circleId, onPosted: onChanged),
              if (posts.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 40),
                  child: Center(child: Text(tr('No posts yet'))),
                ),
            ],
          );
        }
        return CirclePostTile(post: posts[index - 1], onChanged: onChanged);
      },
    );
  }
}
