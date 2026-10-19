import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/features/stories/stories_repository.dart';
import 'package:wecord/features/stories/story_media.dart';
import 'package:wecord/features/stories/story_ring.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What the reply card shows about a daily: its thumbnail while the daily is
/// still up and visible to the signed-in person, nothing once it has ended.
final storyRefInfoProvider = FutureProvider.autoDispose
    .family<StoryRefInfo?, String>((ref, storyId) async {
      try {
        return await ref.watch(storiesRepositoryProvider).refOf(storyId);
      } on Object {
        return null;
      }
    });

/// The top of a reply to a daily in a chat: its thumbnail and "Replied to
/// your daily" (or, on your own reply, "You replied to a daily"). Once the
/// daily has ended the thumbnail is gone and the card says so. Tapping a live
/// one opens it.
class StoryReplyOrigin extends ConsumerWidget {
  const StoryReplyOrigin({
    required this.message,
    required this.reference,
    required this.foregroundColor,
    super.key,
  });

  final ChatMessage message;
  final StoryRef reference;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authStateProvider).value?.id;
    final mine = me != null && message.senderId == me;
    final info = ref.watch(storyRefInfoProvider(reference.storyId));
    final live = info.value != null;
    final title = mine
        ? tr('You replied to a daily')
        : tr('Replied to your daily');
    final body = live
        ? (reference.kind == StoryMediaKind.video ? tr('Video') : tr('Photo'))
        : tr('This daily has ended');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        container: true,
        button: live,
        label: '$title. $body',
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('story-reply-${reference.storyId}'),
          behavior: HitTestBehavior.opaque,
          onTap: live
              ? () => openStoriesOf(context, ref, reference.ownerId)
              : null,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: foregroundColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(WeCordRadii.sm),
                  child: SizedBox(
                    width: 38,
                    height: 52,
                    child: live
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              StoryImage(path: info.value!.thumbPath),
                              if (reference.kind == StoryMediaKind.video)
                                const Center(
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    size: 22,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          )
                        : ColoredBox(
                            color: foregroundColor.withValues(alpha: 0.12),
                            child: Icon(
                              Icons.hourglass_empty_rounded,
                              size: 18,
                              color: foregroundColor.withValues(alpha: 0.6),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: foregroundColor,
                        ),
                      ),
                      Text(
                        body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: foregroundColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
