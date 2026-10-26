import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/hashtags/hashtag_routes.dart';
import 'package:wecord/features/hashtags/hashtag_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A circle of the person's with posts that use a topic.
class HashtagCircle {
  const HashtagCircle({
    required this.circleId,
    required this.name,
    required this.postCount,
    this.avatarUrl,
  });

  factory HashtagCircle.fromJson(Map<String, dynamic> json) {
    return HashtagCircle(
      circleId: json['circle_id'] as String,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      postCount: (json['post_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String circleId;
  final String name;
  final String? avatarUrl;
  final int postCount;
}

/// Where a topic is used, for what the person may see: Moments of theirs and
/// their friends', and the circles they belong to.
class HashtagOverview {
  const HashtagOverview({
    required this.tag,
    required this.momentCount,
    required this.circles,
  });

  factory HashtagOverview.fromJson(Map<String, dynamic> json) {
    return HashtagOverview(
      tag: json['tag'] as String? ?? '',
      momentCount: (json['moments'] as num?)?.toInt() ?? 0,
      circles: [
        for (final circle in (json['circles'] as List<dynamic>? ?? const []))
          HashtagCircle.fromJson(Map<String, dynamic>.from(circle as Map)),
      ],
    );
  }

  final String tag;
  final int momentCount;
  final List<HashtagCircle> circles;

  bool get isEmpty => momentCount == 0 && circles.isEmpty;
}

class HashtagRepository {
  HashtagRepository(this._rpc);

  final CircleRpc _rpc;

  Future<HashtagOverview> overview(String tag) async {
    final result = await _rpc('hashtag_overview', {'p_tag': tag});
    return HashtagOverview.fromJson(rpcObject(result));
  }
}

final hashtagRepositoryProvider = Provider<HashtagRepository>((ref) {
  return HashtagRepository(ref.watch(circleRpcProvider));
});

final hashtagOverviewProvider = FutureProvider.autoDispose
    .family<HashtagOverview, String>((ref, tag) {
      return ref.watch(hashtagRepositoryProvider).overview(tag);
    });

/// The first topic written in a search [query], or null.
String? searchedHashtag(String query) {
  final spans = hashtagSpans(query, limit: 1);
  return spans.isEmpty ? null : spans.first.tag;
}

/// Above the search results when the query has a #topic: where it is used
/// (the person's Moments and circles), nothing about what they cannot see.
class HashtagSearchStrip extends ConsumerWidget {
  const HashtagSearchStrip({required this.query, super.key});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tag = searchedHashtag(query);
    if (tag == null) {
      return const SizedBox.shrink();
    }
    final overview = ref.watch(hashtagOverviewProvider(tag)).value;
    if (overview == null || overview.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    return Padding(
      key: const ValueKey('search-topic-strip'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: BorderRadius.circular(WeCordRadii.xl),
          boxShadow: context.tokens.shadows.hairline,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
              child: Semantics(
                header: true,
                child: Text(
                  tr('Topic #{tag}', {'tag': overview.tag}),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
              ),
            ),
            if (overview.momentCount > 0)
              SettingsRow(
                key: const ValueKey('search-topic-moments'),
                icon: Icons.auto_awesome_motion_outlined,
                tone: SettingsTone.accent,
                title: tr('Moments'),
                value: tr('{count} Moments', {'count': overview.momentCount}),
                onTap: () => context.push(momentTagPath(overview.tag)),
              ),
            for (final circle in overview.circles)
              SettingsRow(
                key: ValueKey('search-topic-circle-${circle.circleId}'),
                icon: Icons.forum_outlined,
                tone: SettingsTone.success,
                title: circle.name,
                value: tr('{count} posts', {'count': circle.postCount}),
                onTap: () => context.push(
                  circlePostsPath(circle.circleId, tag: overview.tag),
                ),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
