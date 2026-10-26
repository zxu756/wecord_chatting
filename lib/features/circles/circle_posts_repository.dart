import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/hashtags/hashtag_text.dart';
import 'package:wecord/shared/models/message.dart';

/// Writing circle posts 2.0 (B8): a title, topics, editing, and the
/// moderators' "featured" mark. Reading goes through the circle detail.
class CirclePostsRepository {
  CirclePostsRepository(this._rpc);

  final CircleRpc _rpc;

  /// The longest title, as the database has it.
  static const maxTitleLength = 80;

  /// Posts a new post. The topics written in the title and the text are
  /// found by the database too; [tags] are the ones picked on top.
  Future<String> create({
    required String circleId,
    required String body,
    String? title,
    List<String> tags = const [],
    ImageAttachment? image,
  }) async {
    final id = await _rpc('create_circle_post', {
      'target_circle_id': circleId,
      'body': body.trim(),
      'attachment': image?.toJson(),
      'post_title': _cleanTitle(title),
      'post_tags': cleanHashtagList(tags),
    });
    return id as String;
  }

  /// Changes a post of the caller's: title, text and the picked topics. The
  /// picture stays.
  Future<void> update({
    required String postId,
    required String body,
    String? title,
    List<String> tags = const [],
  }) async {
    await _rpc('update_circle_post', {
      'target_post_id': postId,
      'post_title': _cleanTitle(title),
      'body': body.trim(),
      'post_tags': cleanHashtagList(tags),
    });
  }

  /// Features or un-features a post (moderators who manage messages).
  /// Returns whether the mark changed.
  Future<bool> setFeatured({
    required String postId,
    required bool featured,
  }) async {
    final changed = await _rpc('set_circle_post_featured', {
      'target_post_id': postId,
      'featured': featured,
    });
    return changed == true;
  }

  static String? _cleanTitle(String? title) {
    final flat = (title ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.isEmpty ? null : flat;
  }
}

final circlePostsRepositoryProvider = Provider<CirclePostsRepository>((ref) {
  return CirclePostsRepository(ref.watch(circleRpcProvider));
});
