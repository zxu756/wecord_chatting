import 'dart:async';

import 'package:flutter/widgets.dart' show ImageProvider, NetworkImage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/media_cache.dart';
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/features/stories/stories_repository.dart';
import 'package:wecord/shared/app_visibility.dart';

/// The signed-in person, so Daily data never outlives a sign-out.
final storiesUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider.select((state) => state.value?.id));
});

/// How long live signals wait for more before the app reads again.
const storiesLiveDelay = Duration(milliseconds: 600);

/// The live signals of the server ("a daily appeared or was taken down",
/// never what; see migration 202610240240), for as long as the person is
/// signed in and something listens.
final storiesSignalsProvider = StreamProvider<StorySignal>((ref) {
  if (ref.watch(storiesUserIdProvider) == null) {
    return const Stream.empty();
  }
  return ref.watch(storiesRepositoryProvider).signals();
});

/// Who has dailies for the signed-in person: their own row first, then
/// friends with something new. Read again when a signal says it may be stale
/// and when the app comes back to the screen, so a daily that ended drops
/// out. Every visibility rule is applied by the server.
final storiesTrayProvider = FutureProvider<List<StoryTrayEntry>>((ref) async {
  final user = ref.watch(storiesUserIdProvider);
  if (user == null) {
    return const [];
  }
  Timer? debounce;
  ref.onDispose(() => debounce?.cancel());
  ref.listen(storiesSignalsProvider, (previous, next) {
    if (next.value == null) {
      return;
    }
    debounce?.cancel();
    debounce = Timer(storiesLiveDelay, ref.invalidateSelf);
  });
  final visible = ref.watch(appVisibleProvider);
  void onVisible() {
    if (visible.value) {
      ref.invalidateSelf();
    }
  }

  visible.addListener(onVisible);
  ref.onDispose(() => visible.removeListener(onVisible));
  try {
    return await ref.watch(storiesRepositoryProvider).tray();
  } on Object {
    // The row of rings is a courtesy: no row when it cannot be read.
    return const [];
  }
});

/// The tray entry of one person, or null when they have nothing up.
final storyTrayEntryProvider = Provider.autoDispose
    .family<StoryTrayEntry?, String>((ref, userId) {
      final tray = ref.watch(storiesTrayProvider).value ?? const [];
      for (final entry in tray) {
        if (entry.authorId == userId) {
          return entry;
        }
      }
      return null;
    });

/// One person's dailies, oldest first.
final authorStoriesProvider = FutureProvider.autoDispose
    .family<List<Story>, String>((ref, authorId) {
      ref.watch(storiesUserIdProvider);
      return ref.watch(storiesRepositoryProvider).storiesOf(authorId);
    });

/// The ids of the signed-in person's close friends.
final closeFriendsProvider = FutureProvider.autoDispose<Set<String>>((ref) {
  ref.watch(storiesUserIdProvider);
  return ref.watch(storiesRepositoryProvider).closeFriends();
});

/// How a signed link becomes a picture (a network image; tests show pictures
/// from memory).
final storyImageProviderFactory = Provider<ImageProvider Function(String)>(
  (ref) =>
      (url) => NetworkImage(url),
);

/// A signed link to a file of the bucket, reused while it is valid.
final storyFileUrlProvider = FutureProvider.autoDispose.family<String, String>((
  ref,
  path,
) {
  final repository = ref.watch(storiesRepositoryProvider);
  return ref
      .watch(chatSignedUrlCacheProvider)
      .get(
        SignedUrlCache.keyFor(storiesBucket, path),
        () => repository.signedUrl(path),
      );
});
