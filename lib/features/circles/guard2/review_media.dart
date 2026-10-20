import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A short-lived link to a picture in the Review queue, made with the
/// moderator's own access. Keyed by bucket and path.
final reviewImageUrlProvider = FutureProvider.autoDispose
    .family<String, ({String bucket, String path, String mimeType})>((
      ref,
      file,
    ) {
      return ref
          .watch(chatsRepositoryProvider)
          .createImageUrl(
            ImageAttachment(
              bucket: file.bucket,
              path: file.path,
              mimeType: file.mimeType,
              size: 0,
            ),
          );
    });

/// What a held or flagged poll or picture shows in its Review card: the
/// picture, or the poll's options under its question. Nothing for text.
class ReviewMedia extends StatelessWidget {
  const ReviewMedia({required this.type, required this.media, super.key});

  final String type;
  final Map<String, dynamic>? media;

  /// Whether there is anything to show.
  bool get hasContent {
    final media = this.media;
    if (media == null) {
      return false;
    }
    return switch (type) {
      'image' => media['bucket'] is String && media['path'] is String,
      'poll' => (media['options'] as List?)?.isNotEmpty ?? false,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!hasContent) {
      return const SizedBox.shrink();
    }
    return type == 'image'
        ? _ReviewPicture(media: media!)
        : _ReviewPollOptions(
            options: [
              for (final option in (media!['options'] as List)) '$option',
            ],
          );
  }
}

class _ReviewPicture extends ConsumerWidget {
  const _ReviewPicture({required this.media});

  final Map<String, dynamic> media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final alt = media['alt'] as String?;
    final url = ref.watch(
      reviewImageUrlProvider((
        bucket: media['bucket'] as String,
        path: media['path'] as String,
        mimeType: media['mime_type'] as String? ?? 'image/jpeg',
      )),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SizedBox(
            key: const ValueKey('review-picture'),
            width: double.infinity,
            child: url.when(
              loading: () => ColoredBox(
                color: c.well,
                child: const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, stackTrace) => ColoredBox(
                color: c.well,
                child: SizedBox(
                  height: 160,
                  child: Center(
                    child: Text(
                      tr("Couldn't load the picture."),
                      style: TextStyle(fontSize: 13.5, color: c.muted),
                    ),
                  ),
                ),
              ),
              data: (link) => Semantics(
                image: true,
                label: alt ?? tr('Picture waiting for review'),
                child: Image.network(
                  link,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  // Keeps the card from jumping when the picture arrives.
                  frameBuilder: (context, child, frame, loadedSynchronously) =>
                      frame == null && !loadedSynchronously
                      ? ColoredBox(
                          color: c.well,
                          child: const SizedBox(
                            height: 160,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        )
                      : child,
                  errorBuilder: (context, error, stackTrace) => ColoredBox(
                    color: c.well,
                    child: SizedBox(
                      height: 160,
                      child: Center(
                        child: Text(
                          tr("Couldn't load the picture."),
                          style: TextStyle(fontSize: 13.5, color: c.muted),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewPollOptions extends StatelessWidget {
  const _ReviewPollOptions({required this.options});

  final List<String> options;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      key: const ValueKey('review-poll-options'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: ExcludeSemantics(
                      child: Icon(
                        Icons.radio_button_unchecked_rounded,
                        size: 15,
                        color: c.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      option,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.35,
                        color: c.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
