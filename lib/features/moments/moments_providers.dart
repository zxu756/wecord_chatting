import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ImageProvider, NetworkImage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/media_cache.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_repository.dart';

/// Posts per page of the feed.
const momentsPageSize = 20;

/// The signed-in person, so Moments data never outlives a sign-out.
final momentsUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider.select((state) => state.value?.id));
});

/// Runs [action] once things have been quiet for [delay], so a burst of live
/// signals (ten likes in a second) costs one request. Cancelled with the
/// provider.
class _Debouncer {
  _Debouncer(Ref ref, this.delay) {
    ref.onDispose(cancel);
  }

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// How long live signals wait for more before the app reads again.
const momentsLiveDelay = Duration(milliseconds: 500);

/// The live signals of the server ("a post, a like or a comment changed",
/// never what; see migration 202610190020), for as long as the person is
/// signed in and something listens. Providers that show Moments data read
/// it again when a signal says it may be stale.
final momentsSignalsProvider = StreamProvider<MomentsSignal>((ref) {
  if (ref.watch(momentsUserIdProvider) == null) {
    return const Stream.empty();
  }
  return ref.watch(momentsRepositoryProvider).signals();
});

/// Every Moment the app has loaded, by id, so the feed, a person's page and
/// the post detail show the same likes and comments. Changes (a like, a
/// comment) are sent to the server and the post is read back, so what shows
/// is always what the visibility rules allow.
class MomentPostsStore extends Notifier<Map<String, MomentPost>> {
  final _pending = <String>{};

  @override
  Map<String, MomentPost> build() {
    ref.watch(momentsUserIdProvider);
    _pending.clear();
    final debounce = _Debouncer(ref, momentsLiveDelay);
    // Likes and comments on posts that are on screen (or were) arrive live;
    // so does a post's removal.
    ref.listen(momentsSignalsProvider, (previous, next) {
      final signal = next.value;
      final id = signal?.postId;
      if (signal == null || id == null || !state.containsKey(id)) {
        return;
      }
      switch (signal.kind) {
        case MomentsSignalKind.postRemoved:
          remove(id);
        case MomentsSignalKind.reaction:
          _pending.add(id);
          debounce.run(() {
            final ids = [..._pending];
            _pending.clear();
            for (final id in ids) {
              unawaited(refresh(id).then((_) {}, onError: (Object _) {}));
            }
          });
        case MomentsSignalKind.post || MomentsSignalKind.resync:
      }
    });
    return {};
  }

  MomentsRepository get _repository => ref.read(momentsRepositoryProvider);

  void put(MomentPost post) => state = {...state, post.id: post};

  void putAll(Iterable<MomentPost> posts) {
    state = {...state, for (final post in posts) post.id: post};
  }

  void remove(String id) {
    if (state.containsKey(id)) {
      state = {...state}..remove(id);
    }
  }

  /// Reads [id] again; a post that is gone (or no longer visible) leaves
  /// the store. Returns it.
  Future<MomentPost?> refresh(String id) async {
    final post = await _repository.post(id);
    if (post == null) {
      remove(id);
    } else {
      put(post);
    }
    return post;
  }

  /// Likes or unlikes, showing the change at once.
  Future<void> setLiked(String id, {required bool liked}) async {
    final before = state[id];
    if (before != null && before.likedByMe != liked) {
      put(
        before.copyWith(
          likedByMe: liked,
          likeCount: (before.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
        ),
      );
    }
    try {
      await _repository.setLiked(id, liked: liked);
    } on Object {
      if (before != null) {
        put(before);
      }
      rethrow;
    }
    await refresh(id);
  }

  Future<void> addComment(
    String id,
    String body, {
    String? replyToCommentId,
    MomentCommentPicture? picture,
  }) async {
    await _repository.comment(
      postId: id,
      body: body,
      replyToCommentId: replyToCommentId,
      picture: picture,
    );
    await refresh(id);
  }

  Future<void> deleteComment(String postId, String commentId) async {
    final me = ref.read(momentsUserIdProvider);
    final comment = state[postId]?.comments
        .where((comment) => comment.id == commentId)
        .firstOrNull;
    await _repository.deleteComment(
      commentId,
      // Only the commenter can remove the file from their folder.
      imagePath: comment != null && comment.userId == me
          ? comment.image?.path
          : null,
    );
    await refresh(postId);
  }

  /// Pins or unpins the person's own Moment, then reads it again.
  Future<void> setPinned(String id, {required bool pinned}) async {
    await _repository.setPinned(id, pinned: pinned);
    await refresh(id);
  }

  Future<void> deletePost(String id) async {
    await _repository.deletePost(id);
    remove(id);
  }
}

final momentPostsStoreProvider =
    NotifierProvider<MomentPostsStore, Map<String, MomentPost>>(
      MomentPostsStore.new,
    );

/// One Moment from the store.
final momentPostProvider = Provider.autoDispose.family<MomentPost?, String>((
  ref,
  id,
) {
  return ref.watch(momentPostsStoreProvider.select((posts) => posts[id]));
});

@immutable
class MomentsFeedState {
  const MomentsFeedState({
    this.ids = const [],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = true,
    this.failed = false,
    this.moreFailed = false,
    this.newIds = const [],
  });

  /// Post ids, newest first.
  final List<String> ids;

  /// The first page is on its way.
  final bool loading;
  final bool loadingMore;
  final bool hasMore;

  /// The first page could not be loaded.
  final bool failed;

  /// A later page could not be loaded.
  final bool moreFailed;

  /// Posts that arrived live and are not in [ids] yet: "N new posts".
  final List<String> newIds;

  MomentsFeedState copyWith({
    List<String>? ids,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    bool? failed,
    bool? moreFailed,
    List<String>? newIds,
  }) {
    return MomentsFeedState(
      ids: ids ?? this.ids,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      failed: failed ?? this.failed,
      moreFailed: moreFailed ?? this.moreFailed,
      newIds: newIds ?? this.newIds,
    );
  }
}

/// The feed (no [authorId]) or one person's page, a page at a time (the
/// server pages by time and id, so new posts never shift what was loaded).
class MomentsFeedController extends Notifier<MomentsFeedState> {
  MomentsFeedController(this.authorId, {this.tag});

  /// Null: everyone's Moments.
  final String? authorId;

  /// Only the Moments with this topic (a filter of the feed).
  final String? tag;

  @override
  MomentsFeedState build() {
    ref.watch(momentsUserIdProvider);
    Future.microtask(refresh);
    final debounce = _Debouncer(ref, momentsLiveDelay);
    ref.listen(momentsSignalsProvider, (previous, next) {
      final signal = next.value;
      if (signal == null) {
        return;
      }
      switch (signal.kind) {
        case MomentsSignalKind.post || MomentsSignalKind.resync:
          debounce.run(() => unawaited(_checkForNew()));
        case MomentsSignalKind.postRemoved:
          final id = signal.postId;
          if (id != null) {
            removeId(id);
          }
        case MomentsSignalKind.reaction:
      }
    });
    return const MomentsFeedState();
  }

  /// Reads the newest page again, quietly: posts that are not in the list
  /// become "N new posts" (the list itself does not jump under the
  /// reader's thumb). Goes through the same function as the feed, so a
  /// signal can never reveal a post the person may not see.
  Future<void> _checkForNew() async {
    if (state.loading || state.failed) {
      return;
    }
    try {
      final posts = await _repository.feed(
        limit: momentsPageSize,
        authorId: authorId,
        tag: tag,
      );
      ref.read(momentPostsStoreProvider.notifier).putAll(posts);
      final known = state.ids.toSet();
      final fresh = [
        for (final post in posts)
          if (!known.contains(post.id)) post.id,
      ];
      if (!listEquals(fresh, state.newIds)) {
        state = state.copyWith(newIds: fresh);
      }
    } on Object {
      // The next signal, or pulling down, tries again.
    }
  }

  /// Shows the posts that arrived live at the top of the list.
  Future<void> showNew() => refresh();

  MomentsRepository get _repository => ref.read(momentsRepositoryProvider);

  /// Loads the newest page again.
  Future<void> refresh() async {
    final hadPosts = state.ids.isNotEmpty;
    state = state.copyWith(loading: !hadPosts, failed: false);
    try {
      final posts = await _repository.feed(
        limit: momentsPageSize,
        authorId: authorId,
        tag: tag,
      );
      ref.read(momentPostsStoreProvider.notifier).putAll(posts);
      state = MomentsFeedState(
        ids: [for (final post in posts) post.id],
        loading: false,
        hasMore: posts.length >= momentsPageSize,
      );
    } on Object {
      state = state.copyWith(loading: false, failed: !hadPosts);
    }
  }

  /// Loads the next page, once the list nears its end.
  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore || state.failed) {
      return;
    }
    final store = ref.read(momentPostsStoreProvider);
    final last = state.ids.isEmpty ? null : store[state.ids.last];
    if (last == null) {
      return;
    }
    state = state.copyWith(loadingMore: true, moreFailed: false);
    try {
      final posts = await _repository.feed(
        limit: momentsPageSize,
        beforeAt: last.createdAt,
        beforeId: last.id,
        authorId: authorId,
        tag: tag,
      );
      ref.read(momentPostsStoreProvider.notifier).putAll(posts);
      final known = state.ids.toSet();
      state = state.copyWith(
        ids: [
          ...state.ids,
          for (final post in posts)
            if (!known.contains(post.id)) post.id,
        ],
        loadingMore: false,
        hasMore: posts.length >= momentsPageSize,
      );
    } on Object {
      state = state.copyWith(loadingMore: false, moreFailed: true);
    }
  }

  /// Puts a Moment just posted at the top without reloading.
  Future<void> addPosted(String id) async {
    final post = await ref.read(momentPostsStoreProvider.notifier).refresh(id);
    if (post == null || state.ids.contains(id)) {
      return;
    }
    state = state.copyWith(ids: [id, ...state.ids]);
  }

  void removeId(String id) {
    state = state.copyWith(
      ids: [
        for (final existing in state.ids)
          if (existing != id) existing,
      ],
      newIds: [
        for (final existing in state.newIds)
          if (existing != id) existing,
      ],
    );
  }
}

/// The feed of everyone's Moments.
final momentsFeedProvider =
    NotifierProvider.autoDispose<MomentsFeedController, MomentsFeedState>(
      () => MomentsFeedController(null),
    );

/// One friend's page.
final momentsPageProvider = NotifierProvider.autoDispose
    .family<MomentsFeedController, MomentsFeedState, String>(
      MomentsFeedController.new,
    );

/// The Moments with one topic, as far as the person may see them.
final momentsTagFeedProvider = NotifierProvider.autoDispose
    .family<MomentsFeedController, MomentsFeedState, String>(
      (tag) => MomentsFeedController(null, tag: tag),
    );

/// The topics friends use in their Moments.
final momentsTopicsProvider = FutureProvider.autoDispose<List<MomentTopic>>((
  ref,
) {
  ref.watch(momentsUserIdProvider);
  return ref.watch(momentsRepositoryProvider).topics();
});

/// New Moments from friends since the person last opened Moments.
final momentsUnseenProvider = FutureProvider.autoDispose<MomentsUnseen>((
  ref,
) async {
  ref.watch(momentsUserIdProvider);
  // Chat activity is a good moment to look again.
  ref.listen(conversationsProvider, (previous, next) {
    if (previous != null && previous.hasValue && next is AsyncData) {
      ref.invalidateSelf();
    }
  });
  // So is a friend posting (or taking a post back): the count and the
  // latest poster's avatar on the Moments entry follow live.
  final debounce = _Debouncer(ref, momentsLiveDelay);
  ref.listen(momentsSignalsProvider, (previous, next) {
    final kind = next.value?.kind;
    if (kind == MomentsSignalKind.post ||
        kind == MomentsSignalKind.postRemoved ||
        kind == MomentsSignalKind.resync) {
      debounce.run(ref.invalidateSelf);
    }
  });
  try {
    return await ref.watch(momentsRepositoryProvider).unseen();
  } on Object {
    return MomentsUnseen.none;
  }
});

/// Likes, comments and replies for the Notifications page.
final momentNotificationsProvider =
    FutureProvider.autoDispose<List<MomentNotification>>((ref) async {
      ref.watch(momentsUserIdProvider);
      // A like or comment on my Moment (or a reply to my comment) shows up
      // in Notifications and its badge as it happens.
      final debounce = _Debouncer(ref, momentsLiveDelay);
      ref.listen(momentsSignalsProvider, (previous, next) {
        final kind = next.value?.kind;
        if (kind == MomentsSignalKind.reaction ||
            kind == MomentsSignalKind.resync) {
          debounce.run(ref.invalidateSelf);
        }
      });
      try {
        return await ref.watch(momentsRepositoryProvider).notifications();
      } on Object {
        return const [];
      }
    });

/// Unread Moments notifications, for the Notifications badge.
final momentNotificationsUnreadProvider = Provider.autoDispose<int>((ref) {
  return ref
          .watch(momentNotificationsProvider)
          .value
          ?.where((notification) => notification.isUnread)
          .length ??
      0;
});

final momentsSettingsProvider = FutureProvider.autoDispose<MomentsSettings>((
  ref,
) {
  ref.watch(momentsUserIdProvider);
  return ref.watch(momentsRepositoryProvider).settings();
});

final momentsFriendPrefsProvider =
    FutureProvider.autoDispose<List<MomentsFriendPref>>((ref) {
      ref.watch(momentsUserIdProvider);
      return ref.watch(momentsRepositoryProvider).friendPrefs();
    });

/// The header of a person's Moments page (a null id is the person's own).
final momentsProfileProvider = FutureProvider.autoDispose
    .family<MomentsProfile?, String>((ref, userId) {
      return ref.watch(momentsRepositoryProvider).profile(userId);
    });

/// What the Moment card in a chat shows, or null when the reader may not see
/// the Moment (any more) or it cannot be read.
final momentCardProvider = FutureProvider.autoDispose
    .family<MomentCardInfo?, String>((ref, postId) async {
      ref.watch(momentsUserIdProvider);
      try {
        return await ref.watch(momentsRepositoryProvider).momentCard(postId);
      } on Object {
        return null;
      }
    });

/// How a signed link becomes a picture (a network image; tests show
/// pictures from memory).
final momentImageProviderFactory = Provider<ImageProvider Function(String)>(
  (ref) =>
      (url) => NetworkImage(url),
);

/// A signed link to a picture of the bucket, reused while it is valid.
final momentImageUrlProvider = FutureProvider.autoDispose
    .family<String, String>((ref, path) {
      final repository = ref.watch(momentsRepositoryProvider);
      return ref
          .watch(chatSignedUrlCacheProvider)
          .get(
            SignedUrlCache.keyFor(momentsBucket, path),
            () => repository.signedUrl(path),
          );
    });
